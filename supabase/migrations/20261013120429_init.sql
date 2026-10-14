-- SIGAP Banjir: skema awal (PRD §10). Postgres + PostGIS di Supabase.
-- Aturan akses: warga hanya lewat RLS; logika lintas tabel di trigger/fungsi skema `private`
-- (tidak diekspos ke Data API).

create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron;

create schema if not exists private;
grant usage on schema private to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Tipe
-- ---------------------------------------------------------------------------
create type public.depth_category as enum ('none', 'ankle', 'knee', 'waist', 'chest');
create type public.user_role as enum ('warga', 'verifikator', 'admin');
create type public.point_status as enum ('active', 'needs_confirmation', 'receded');
create type public.verification as enum ('unverified', 'verified', 'official'); -- urutan = tingkat kepercayaan
create type public.report_status as enum ('pending', 'approved', 'rejected');
create type public.reject_reason as enum ('foto_tidak_relevan', 'lokasi_salah', 'duplikat', 'lainnya');
create type public.shelter_type as enum ('posko', 'faskes');
create type public.shelter_status as enum ('open', 'full', 'closed');
create type public.risk_level as enum ('kadang', 'sering', 'sangat_sering');

-- ---------------------------------------------------------------------------
-- Profil & peran
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  role public.user_role not null default 'warga',
  is_blocked boolean not null default false,
  created_at timestamptz not null default now()
);

-- Peran dibaca dari tabel, bukan dari user_metadata (bisa diubah pengguna sendiri).
create function private.my_role() returns public.user_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid()) and not is_blocked
$$;

create function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.my_role() in ('verifikator', 'admin'), false)
$$;

create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.my_role() = 'admin', false)
$$;

revoke execute on function private.my_role(), private.is_staff(), private.is_admin() from public;
grant execute on function private.my_role(), private.is_staff(), private.is_admin() to anon, authenticated;

create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function private.handle_new_user();

-- Warga boleh mengganti nama sendiri; peran dan blokir hanya oleh admin.
create function private.guard_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (new.role, new.is_blocked) is distinct from (old.role, old.is_blocked) and not private.is_admin() then
    raise exception 'Hanya admin yang bisa mengubah peran atau status blokir' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger guard_profile before update on public.profiles
for each row execute function private.guard_profile();

alter table public.profiles enable row level security;
grant select, update (name, role, is_blocked) on public.profiles to authenticated;

create policy "profil sendiri atau admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select private.is_admin()));
create policy "ubah profil sendiri atau admin" on public.profiles for update to authenticated
using (id = (select auth.uid()) or (select private.is_admin()))
with check (id = (select auth.uid()) or (select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Titik genangan
-- ---------------------------------------------------------------------------
create table public.flood_points (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 2 and 120),
  district text,
  location extensions.geography(point, 4326) not null,
  -- Ruas hanya digambar Verifikator/Admin di panel web, tidak pernah otomatis (PRD §10).
  segment extensions.geography(linestring, 4326)
    check (segment is null or extensions.st_length(segment) <= 2000),
  segment_length_m int generated always as (round(extensions.st_length(segment))::int) stored,
  depth public.depth_category not null,
  status public.point_status not null default 'active',
  verification public.verification not null default 'unverified',
  source text not null,
  report_count int not null default 0,
  receded_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index flood_points_location_idx on public.flood_points using gist (location);
create index flood_points_open_idx on public.flood_points (updated_at) where status = 'active';

alter table public.flood_points enable row level security;
grant select on public.flood_points to anon, authenticated;
grant insert, update, delete on public.flood_points to authenticated;

create policy "semua bisa lihat" on public.flood_points for select to anon, authenticated using (true);
create policy "staf kelola" on public.flood_points for all to authenticated
using ((select private.is_staff())) with check ((select private.is_staff()));

-- Satu baris per kejadian; sumber estimasi surut (F18) dan lapisan rawan (F19).
create table public.flood_events (
  id bigint generated always as identity primary key,
  flood_point_id bigint not null references public.flood_points on delete cascade,
  started_at timestamptz not null default now(),
  receded_at timestamptz,
  max_depth public.depth_category not null
);

create index flood_events_point_idx on public.flood_events (flood_point_id, started_at desc);
create unique index flood_events_one_open on public.flood_events (flood_point_id) where receded_at is null;

alter table public.flood_events enable row level security;
grant select on public.flood_events to anon, authenticated;
create policy "semua bisa lihat" on public.flood_events for select to anon, authenticated using (true);

-- Catat kejadian otomatis sejak hari pertama (PRD §12 fase 3).
create function private.track_flood_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'receded' then
    new.receded_at := coalesce(new.receded_at, now());
    new.depth := 'none';
    update public.flood_events set receded_at = new.receded_at
    where flood_point_id = new.id and receded_at is null;
  elsif new.depth <> 'none' then
    insert into public.flood_events (flood_point_id, started_at, max_depth)
    values (new.id, now(), new.depth)
    on conflict (flood_point_id) where receded_at is null
    do update set max_depth = greatest(public.flood_events.max_depth, excluded.max_depth);
    new.receded_at := null;
  end if;
  return new;
end $$;

-- BEFORE untuk update (agar bisa mengubah NEW); insert ditangani AFTER karena butuh id.
create trigger track_flood_event_update before update of status, depth on public.flood_points
for each row execute function private.track_flood_event();

create function private.track_flood_event_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'receded' and new.depth <> 'none' then
    insert into public.flood_events (flood_point_id, started_at, max_depth) values (new.id, new.created_at, new.depth);
  end if;
  return null;
end $$;

create trigger track_flood_event_insert after insert on public.flood_points
for each row execute function private.track_flood_event_insert();

-- ---------------------------------------------------------------------------
-- Laporan warga
-- ---------------------------------------------------------------------------
create table public.reports (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  flood_point_id bigint references public.flood_points on delete set null,
  location extensions.geography(point, 4326) not null,
  place_name text check (char_length(place_name) <= 120),
  depth public.depth_category not null,
  photo_paths text[] not null check (cardinality(photo_paths) between 1 and 3),
  note text check (char_length(note) <= 200),
  status public.report_status not null default 'pending',
  reject_reason public.reject_reason,
  reviewed_by uuid references auth.users on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check ((status = 'rejected') = (reject_reason is not null))
);

create index reports_user_idx on public.reports (user_id, created_at desc);
create index reports_point_idx on public.reports (flood_point_id);
create index reports_pending_idx on public.reports (created_at desc) where status = 'pending';
create index reports_location_idx on public.reports using gist (location);

-- Koordinat pelapor tidak pernah terbaca warga lain (PRD §9): hanya pemilik dan staf.
alter table public.reports enable row level security;
grant select on public.reports to authenticated;
grant insert (location, place_name, depth, photo_paths, note) on public.reports to authenticated;
grant update (status, reject_reason, reviewed_by, reviewed_at, flood_point_id) on public.reports to authenticated;

create policy "pemilik atau staf lihat" on public.reports for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_staff()));
create policy "warga kirim laporan sendiri" on public.reports for insert to authenticated
with check (user_id = (select auth.uid()) and private.my_role() is not null);
create policy "staf tinjau" on public.reports for update to authenticated
using ((select private.is_staff())) with check ((select private.is_staff()));

-- Sebelum laporan masuk: batas 5/jam, foto harus di folder sendiri, tempel ke titik aktif ≤ 100 m.
create function private.before_report() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  p_id bigint;
begin
  if (select count(*) from public.reports
      where user_id = new.user_id and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Kamu sudah mengirim 5 laporan dalam 1 jam. Coba lagi nanti.' using errcode = 'P0001', hint = 'RATE_LIMITED';
  end if;

  if exists (select 1 from unnest(new.photo_paths) p where p not like new.user_id::text || '/%') then
    raise exception 'Foto tidak valid' using errcode = '22023';
  end if;

  select id into p_id from public.flood_points
  where status <> 'receded' and extensions.st_dwithin(location, new.location, 100)
  order by extensions.st_distance(location, new.location)
  limit 1;

  if p_id is null then
    insert into public.flood_points (name, location, depth, source)
    values (coalesce(nullif(trim(new.place_name), ''), 'Laporan warga'), new.location, new.depth, 'Laporan warga')
    returning id into p_id;
  else
    -- Laporan baru menyegarkan titik, tapi kategori/verifikasi baru berubah setelah disetujui.
    update public.flood_points set status = 'active', updated_at = now() where id = p_id and status = 'needs_confirmation';
  end if;

  new.flood_point_id := p_id;
  new.status := 'pending';
  return new;
end $$;

create trigger before_report before insert on public.reports
for each row execute function private.before_report();

create function private.count_reports() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.flood_points p set report_count = (
    select count(*) from public.reports r where r.flood_point_id = p.id and r.status <> 'rejected'
  ) where p.id in (new.flood_point_id, old.flood_point_id);
  return null;
end $$;

create trigger count_reports after insert or update of status or delete on public.reports
for each row execute function private.count_reports();

-- ---------------------------------------------------------------------------
-- Posko, faskes, kontak darurat (diinput Admin)
-- ---------------------------------------------------------------------------
create table public.shelters (
  id bigint generated always as identity primary key,
  type public.shelter_type not null,
  name text not null,
  address text not null,
  location extensions.geography(point, 4326) not null,
  phone text,
  status public.shelter_status not null default 'open',
  note text,
  updated_by uuid references auth.users on delete set null,
  updated_at timestamptz not null default now()
);

create table public.emergency_contacts (
  id bigint generated always as identity primary key,
  name text not null,
  phone text not null,
  category text not null,
  sort_order int not null default 0
);

alter table public.shelters enable row level security;
alter table public.emergency_contacts enable row level security;
grant select on public.shelters, public.emergency_contacts to anon, authenticated;
grant insert, update, delete on public.shelters, public.emergency_contacts to authenticated;

create policy "semua bisa lihat" on public.shelters for select to anon, authenticated using (true);
create policy "admin kelola" on public.shelters for all to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "semua bisa lihat" on public.emergency_contacts for select to anon, authenticated using (true);
create policy "admin kelola" on public.emergency_contacts for all to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Lokasi pantauan, perangkat, notifikasi
-- ---------------------------------------------------------------------------
create table public.watch_locations (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  label text not null check (char_length(label) between 1 and 24),
  place text not null check (char_length(place) <= 120),
  location extensions.geography(point, 4326) not null,
  radius_m int not null check (radius_m between 500 and 2000),
  created_at timestamptz not null default now()
);

create index watch_locations_user_idx on public.watch_locations (user_id);
create index watch_locations_location_idx on public.watch_locations using gist (location);

create function private.max_five_watch() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.watch_locations where user_id = new.user_id) >= 5 then
    raise exception 'Batas 5 lokasi tercapai. Hapus salah satu untuk menambah lokasi baru.' using errcode = 'P0001', hint = 'WATCH_LIMIT';
  end if;
  return new;
end $$;

create trigger max_five_watch before insert on public.watch_locations
for each row execute function private.max_five_watch();

create table public.device_tokens (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  fcm_token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  last_seen_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  flood_point_id bigint references public.flood_points on delete cascade,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_point_idx on public.notifications (flood_point_id);

alter table public.watch_locations enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
grant select, insert, delete on public.watch_locations, public.device_tokens to authenticated;
grant update (label, radius_m) on public.watch_locations to authenticated;
grant update (last_seen_at) on public.device_tokens to authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create policy "milik sendiri" on public.watch_locations for all to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "milik sendiri" on public.device_tokens for all to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "milik sendiri" on public.notifications for all to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- US-07/US-03: kabari pemantau saat titik Terverifikasi/Resmi ≥ selutut, atau saat surut.
-- Laporan Belum Terverifikasi tidak pernah memicu notifikasi.
create function private.notify_watchers() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  became_danger boolean := new.verification <> 'unverified' and new.status = 'active'
    and new.depth >= 'knee'
    and (old.verification = 'unverified' or old.depth < 'knee' or old.status <> 'active');
  became_dry boolean := new.status = 'receded' and old.status <> 'receded';
  depth_label text := case new.depth
    when 'knee' then 'selutut (± 40 cm)' when 'waist' then 'sepinggang (± 80 cm)' when 'chest' then 'sedada ke atas (> 100 cm)' end;
begin
  if not (became_danger or became_dry) then return null; end if;
  insert into public.notifications (user_id, flood_point_id, title, body)
  select distinct on (w.user_id) w.user_id, new.id,
    case when became_dry then new.name || ' sudah surut' else w.label || ' · ' || new.name end,
    case when became_dry then 'Surut pukul ' || to_char(new.receded_at at time zone 'Asia/Jakarta', 'HH24.MI') || '. Jalan bisa dilalui lagi.'
         else 'Air ' || depth_label || '. ' || case new.verification when 'official' then 'Resmi.' else 'Terverifikasi.' end end
  from public.watch_locations w
  where extensions.st_dwithin(w.location, new.location, w.radius_m)
  order by w.user_id, w.radius_m;
  return null;
end $$;

create trigger notify_watchers after update on public.flood_points
for each row execute function private.notify_watchers();

-- ---------------------------------------------------------------------------
-- Prakiraan BMKG (diisi Edge Function) dan lapisan rawan (diisi cron)
-- ---------------------------------------------------------------------------
create table public.forecast_cache (
  district text primary key,
  forecast_json jsonb not null,
  rain_end_at timestamptz,
  fetched_at timestamptz not null default now()
);

create table public.risk_areas_cache (
  id bigint generated always as identity primary key,
  label text not null,
  area extensions.geography(polygon, 4326) not null,
  event_count_12m int not null,
  level public.risk_level not null,
  computed_at timestamptz not null default now()
);

alter table public.forecast_cache enable row level security;
alter table public.risk_areas_cache enable row level security;
grant select on public.forecast_cache, public.risk_areas_cache to anon, authenticated;
create policy "semua bisa lihat" on public.forecast_cache for select to anon, authenticated using (true);
create policy "semua bisa lihat" on public.risk_areas_cache for select to anon, authenticated using (true);

-- ponytail: area rawan = buffer 300 m di sekitar titik dengan ≥ 3 kejadian/12 bulan.
-- Ganti ke poligon kelurahan kalau data batas wilayah resmi sudah ada.
create function private.refresh_risk_areas() returns void
language sql security definer set search_path = '' as $$
  delete from public.risk_areas_cache;
  insert into public.risk_areas_cache (label, area, event_count_12m, level)
  select p.name || coalesce(', ' || p.district, ''),
         extensions.st_buffer(p.location, 300)::extensions.geography(polygon, 4326),
         e.n,
         case when e.n > 10 then 'sangat_sering' when e.n >= 6 then 'sering' else 'kadang' end::public.risk_level
  from public.flood_points p
  join (select flood_point_id, count(*) as n from public.flood_events
        where started_at > now() - interval '12 months' group by 1) e on e.flood_point_id = p.id
  where e.n >= 3;
$$;

-- ---------------------------------------------------------------------------
-- Audit (aksi verifikator dan admin)
-- ---------------------------------------------------------------------------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users on delete set null,
  action text not null,
  target_type text not null,
  target_id text not null,
  created_at timestamptz not null default now()
);

alter table public.audit_logs enable row level security;
grant select on public.audit_logs to authenticated;
grant insert (actor_id, action, target_type, target_id) on public.audit_logs to authenticated;
create policy "admin lihat" on public.audit_logs for select to authenticated using ((select private.is_admin()));
create policy "staf mencatat" on public.audit_logs for insert to authenticated
with check ((select private.is_staff()) and actor_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- RPC untuk aplikasi
-- ---------------------------------------------------------------------------

-- GET /flood-points?lat&lng&radius (maks 10 km) + detail lengkap per titik (PRD §11).
create function public.flood_points_near(at_lat double precision, at_lng double precision, radius_m int default 10000)
returns table (
  id bigint, name text, district text, lat double precision, lng double precision, segment jsonb, segment_length_m int,
  depth public.depth_category, status public.point_status, verification public.verification, source text,
  report_count int, updated_at timestamptz, receded_at timestamptz, recession_estimate jsonb, history jsonb
)
language sql stable set search_path = '' as $$
  with here as (select extensions.st_setsrid(extensions.st_makepoint(at_lng, at_lat), 4326)::extensions.geography g)
  select p.id, p.name, p.district,
    extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
    extensions.st_asgeojson(p.segment)::jsonb, p.segment_length_m,
    p.depth, p.status, p.verification, p.source, p.report_count, p.updated_at, p.receded_at,
    -- US-12: median, hanya jika ≥ 5 kejadian yang sudah surut.
    (select case when count(*) >= 5 then jsonb_build_object(
        'median_hours', round(extract(epoch from percentile_cont(0.5) within group (order by e.receded_at - e.started_at)) / 3600),
        'sample_size', count(*), 'basis', 'history') end
     from public.flood_events e where e.flood_point_id = p.id and e.receded_at is not null),
    (select case when count(*) > 0 then jsonb_build_object(
        'last_event_at', max(e.started_at),
        'count_12m', count(*),
        'monthly_counts', (select jsonb_agg(coalesce(c.n, 0) order by m.i)
          from generate_series(11, 0, -1) m(i)
          left join (select date_trunc('month', e2.started_at) mo, count(*) n from public.flood_events e2
                     where e2.flood_point_id = p.id group by 1) c
            on c.mo = date_trunc('month', now() - make_interval(months => m.i)))) end
     from public.flood_events e where e.flood_point_id = p.id and e.started_at > now() - interval '12 months')
  from public.flood_points p, here
  where extensions.st_dwithin(p.location, here.g, least(radius_m, 10000))
$$;

-- Posko & faskes dengan koordinat siap pakai.
create function public.shelters_list()
returns table (id bigint, type public.shelter_type, name text, address text, lat double precision, lng double precision,
  phone text, status public.shelter_status, note text)
language sql stable set search_path = '' as $$
  select id, type, name, address, extensions.st_y(location::extensions.geometry), extensions.st_x(location::extensions.geometry), phone, status, note
  from public.shelters order by type, name
$$;

create function public.risk_areas()
returns table (label text, level public.risk_level, event_count_12m int, polygon jsonb)
language sql stable set search_path = '' as $$
  select label, level, event_count_12m, extensions.st_asgeojson(area)::jsonb from public.risk_areas_cache
$$;

-- Lokasi pantauan dengan koordinat (tabel menyimpan geography).
create function public.my_watch_locations()
returns table (id bigint, label text, place text, lat double precision, lng double precision, radius_m int)
language sql stable set search_path = '' as $$
  select id, label, place, extensions.st_y(location::extensions.geometry), extensions.st_x(location::extensions.geometry), radius_m
  from public.watch_locations where user_id = (select auth.uid()) order by created_at
$$;

-- Foto laporan yang sudah disetujui untuk detail lokasi (path saja; klien membuat signed URL).
create function public.point_photos(point_id bigint)
returns setof text
language sql stable security definer set search_path = '' as $$
  select unnest(photo_paths) from public.reports
  where flood_point_id = point_id and status = 'approved'
  order by 1 limit 6
$$;

-- US-05: setujui / tolak. Dipanggil dari panel web.
create function public.review_report(report_id bigint, approve boolean, reason public.reject_reason default null)
returns void
language plpgsql set search_path = '' as $$
declare
  r public.reports;
begin
  if not private.is_staff() then
    raise exception 'Hanya verifikator' using errcode = '42501';
  end if;
  update public.reports set
    status = case when approve then 'approved' else 'rejected' end::public.report_status,
    reject_reason = case when approve then null else coalesce(reason, 'lainnya') end,
    reviewed_by = (select auth.uid()), reviewed_at = now()
  where id = report_id returning * into r;
  if r.id is null then raise exception 'Laporan tidak ditemukan' using errcode = 'P0002'; end if;

  if approve then
    update public.flood_points set
      verification = greatest(verification, 'verified'), depth = r.depth, status = 'active', updated_at = now()
    where id = r.flood_point_id;
  else
    -- Ditolak dan tidak ada laporan lain yang masih berlaku: titik hilang dari peta.
    delete from public.flood_points p where p.id = r.flood_point_id and p.verification = 'unverified'
      and not exists (select 1 from public.reports x where x.flood_point_id = p.id and x.status <> 'rejected');
  end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id)
  values ((select auth.uid()), case when approve then 'approve' else 'reject' end, 'report', report_id::text);
end $$;

-- US-06: hapus akun setelah ketik ulang kata sandi. Foto dihapus klien lewat Storage API dulu.
create function public.delete_my_account(password text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '42501'; end if;
  if not exists (select 1 from auth.users u where u.id = uid
                 and u.encrypted_password = extensions.crypt(password, u.encrypted_password)) then
    raise exception 'Kata sandi salah.' using errcode = '28P01';
  end if;
  delete from auth.users where id = uid; -- laporan, pantauan, notifikasi ikut terhapus (cascade)
end $$;

revoke execute on function public.review_report, public.delete_my_account, public.point_photos from public, anon;
grant execute on function public.review_report, public.delete_my_account to authenticated;
grant execute on function public.point_photos to anon, authenticated;
grant execute on function public.flood_points_near, public.shelters_list, public.risk_areas to anon, authenticated;
revoke execute on function public.my_watch_locations from public, anon;
grant execute on function public.my_watch_locations to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: foto laporan (privat, maks 5 MB, JPG/PNG)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-photos', 'report-photos', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create function private.photo_is_public(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.reports where status = 'approved' and object_name = any(photo_paths))
$$;
revoke execute on function private.photo_is_public from public;
grant execute on function private.photo_is_public to anon, authenticated;

create policy "unggah ke folder sendiri" on storage.objects for insert to authenticated
with check (bucket_id = 'report-photos' and (storage.foldername(name))[1] = (select auth.uid()::text)
  and private.my_role() is not null);
create policy "pemilik, staf, atau foto laporan disetujui" on storage.objects for select to anon, authenticated
using (bucket_id = 'report-photos' and (
  (storage.foldername(name))[1] = (select auth.uid()::text)
  or (select private.is_staff())
  or private.photo_is_public(name)));
create policy "hapus foto sendiri" on storage.objects for delete to authenticated
using (bucket_id = 'report-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

-- ---------------------------------------------------------------------------
-- Jadwal
-- ---------------------------------------------------------------------------
-- US-02: > 3 jam tanpa pembaruan → Perlu Konfirmasi (penanda memudar).
select cron.schedule('needs-confirmation', '*/10 * * * *', $$
  update public.flood_points set status = 'needs_confirmation'
  where status = 'active' and updated_at < now() - interval '3 hours'
$$);
select cron.schedule('refresh-risk-areas', '15 0 * * *', 'select private.refresh_risk_areas()');
select cron.schedule('cleanup-cron-history', '30 0 * * 0', $$
  delete from cron.job_run_details where end_time < now() - interval '7 days'
$$);

-- Moderasi se-Indonesia: verifikasi otomatis oleh ≥ N warga di wilayah tanpa verifikator,
-- laporan foto tidak pantas, daftar wilayah tanpa verifikator, dan daftar posko/faskes per area.

-- ---------------------------------------------------------------------------
-- Verifikasi otomatis (konfirmasi warga)
-- ---------------------------------------------------------------------------
alter table public.app_settings
  add column crowd_min_reporters int not null default 3 check (crowd_min_reporters = 0 or crowd_min_reporters between 2 and 10),
  add column crowd_window_min int not null default 60 check (crowd_window_min between 15 and 240);
grant update (crowd_min_reporters, crowd_window_min) on public.app_settings to authenticated;
comment on column public.app_settings.crowd_min_reporters is '0 = verifikasi otomatis nonaktif';

-- Ada verifikator aktif untuk kab/kota desa ini? (admin nasional tidak dihitung: dia bukan penjaga wilayah)
create function private.has_reviewer(code text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.staff_regions s join public.profiles p on p.id = s.user_id
    where s.region = left(code, 5) and p.role = 'verifikator' and not p.is_blocked)
$$;
revoke execute on function private.has_reviewer from public;

-- Setelah laporan masuk: bila wilayahnya tanpa verifikator dan ≥ N akun berbeda melaporkan titik yang sama
-- dalam jendela waktu, semua laporan itu disetujui otomatis dan titik jadi Terverifikasi.
-- Kategori = median laporan. Label sumber menyebut "otomatis" agar warga tahu belum dicek petugas.
create function private.crowd_verify() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  s public.app_settings;
  n int;
  d public.depth_category;
begin
  select * into s from public.app_settings;
  if s.crowd_min_reporters = 0 or new.adm4 is null or private.has_reviewer(new.adm4) then return null; end if;
  if not exists (select 1 from public.flood_points p where p.id = new.flood_point_id and p.verification = 'unverified') then
    return null;
  end if;

  select count(distinct r.user_id), percentile_disc(0.5) within group (order by r.depth)
  into n, d
  from public.reports r
  where r.flood_point_id = new.flood_point_id and r.status = 'pending'
    and r.created_at > now() - make_interval(mins => s.crowd_window_min);
  if n < s.crowd_min_reporters then return null; end if;

  update public.reports set status = 'approved', reviewed_at = now() -- reviewed_by kosong = otomatis
  where flood_point_id = new.flood_point_id and status = 'pending'
    and created_at > now() - make_interval(mins => s.crowd_window_min);
  update public.flood_points set verification = 'verified', depth = d, status = 'active', updated_at = now(),
    source = 'Laporan warga · terverifikasi otomatis (' || n || ' warga)'
  where id = new.flood_point_id;
  perform private.audit('auto_verify', 'point', new.flood_point_id::text,
    concat_ws(' · ', (select p.name from public.flood_points p where p.id = new.flood_point_id), n || ' warga', private.depth_label(d)));
  return null;
end $$;
create trigger crowd_verify after insert on public.reports
for each row execute function private.crowd_verify();

-- Begitu petugas menyetujui laporan di titik itu, label "otomatis" dilepas.
create function private.human_checked() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.flood_points set source = 'Laporan warga'
  where id = new.flood_point_id and source like 'Laporan warga · terverifikasi otomatis%';
  return null;
end $$;
create trigger human_checked after update of status on public.reports
for each row when (new.status = 'approved' and new.reviewed_by is not null)
execute function private.human_checked();

-- Admin: kab/kota yang 7 hari terakhir punya laporan tetapi belum ada verifikatornya.
create function public.uncovered_regions()
returns table (region text, name text, province text, pending bigint, reports_7d bigint, last_report_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select k.code, k.name, pv.name,
    count(*) filter (where r.status = 'pending'), count(*), max(r.created_at)
  from public.reports r
  join public.regions k on k.code = left(r.adm4, 5)
  left join public.regions pv on pv.code = left(r.adm4, 2)
  where private.is_admin() and r.created_at > now() - interval '7 days' and not private.has_reviewer(r.adm4)
  group by k.code, k.name, pv.name
  order by count(*) filter (where r.status = 'pending') desc, max(r.created_at) desc
$$;
revoke execute on function public.uncovered_regions from public, anon;
grant execute on function public.uncovered_regions to authenticated;

-- ---------------------------------------------------------------------------
-- Laporkan foto
-- ---------------------------------------------------------------------------
-- Foto yang disembunyikan petugas (atau otomatis setelah banyak laporan) tidak lagi bisa dibuka publik.
alter table public.reports add column hidden_photos text[] not null default '{}';

create type public.flag_reason as enum ('tidak_pantas', 'bukan_banjir', 'data_pribadi', 'lainnya');

create table public.photo_flags (
  id bigint generated always as identity primary key,
  report_id bigint not null references public.reports on delete cascade,
  photo_path text not null,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  reason public.flag_reason not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (photo_path, user_id)
);
create index photo_flags_open_idx on public.photo_flags (photo_path) where resolved_at is null;
alter table public.photo_flags enable row level security;
grant select on public.photo_flags to authenticated;
create policy "pemilik atau staf lihat" on public.photo_flags for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_staff()));
-- Tulis hanya lewat flag_photo() / resolve_photo().

create or replace function public.point_photos(point_id bigint)
returns setof text
language sql stable security definer set search_path = '' as $$
  select p from public.reports r, unnest(r.photo_paths) p
  where r.flood_point_id = point_id and r.status = 'approved' and p <> all (r.hidden_photos)
  order by 1 limit 6
$$;

create or replace function private.photo_is_public(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.reports where status = 'approved'
    and object_name = any(photo_paths) and object_name <> all (hidden_photos))
$$;

-- Warga melaporkan foto. 3 akun berbeda = disembunyikan dulu sampai petugas memutuskan.
create function public.flag_photo(path text, reason public.flag_reason) returns void
language plpgsql security definer set search_path = '' as $$
declare
  rid bigint;
begin
  if private.my_role() is null then raise exception 'Masuk dulu untuk melaporkan foto' using errcode = '42501'; end if;
  if (select count(*) from public.photo_flags where user_id = (select auth.uid())
      and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Terlalu banyak laporan foto. Coba lagi nanti.' using errcode = 'P0001', hint = 'RATE_LIMITED';
  end if;
  select id into rid from public.reports where status = 'approved' and path = any(photo_paths);
  if rid is null then raise exception 'Foto tidak ditemukan' using errcode = 'P0002'; end if;

  insert into public.photo_flags (report_id, photo_path, reason) values (rid, path, reason)
  on conflict (photo_path, user_id) do nothing;
  if (select count(*) from public.photo_flags where photo_path = path and resolved_at is null) >= 3 then
    update public.reports set hidden_photos = array_append(hidden_photos, path)
    where id = rid and path <> all (hidden_photos);
  end if;
end $$;
revoke execute on function public.flag_photo from public, anon;
grant execute on function public.flag_photo to authenticated;

-- Antrean foto yang dilaporkan, untuk staf di wilayahnya.
create function public.photo_flag_queue()
returns table (photo_path text, report_id bigint, point_id bigint, point_name text, district text, adm4 text,
  flags bigint, reasons public.flag_reason[], first_at timestamptz, hidden boolean)
language sql stable security definer set search_path = '' as $$
  select f.photo_path, r.id, r.flood_point_id, p.name, p.district, r.adm4,
    count(*), array_agg(distinct f.reason), min(f.created_at), f.photo_path = any(r.hidden_photos)
  from public.photo_flags f
  join public.reports r on r.id = f.report_id
  left join public.flood_points p on p.id = r.flood_point_id
  where f.resolved_at is null and private.can_review(r.adm4)
  group by f.photo_path, r.id, p.name, p.district
  order by count(*) desc, min(f.created_at)
$$;
revoke execute on function public.photo_flag_queue from public, anon;
grant execute on function public.photo_flag_queue to authenticated;

-- Petugas memutuskan: sembunyikan foto (hide) atau tampilkan lagi & abaikan laporan.
create function public.resolve_photo(path text, hide boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.reports;
begin
  select * into r from public.reports where path = any(photo_paths);
  if r.id is null then raise exception 'Foto tidak ditemukan' using errcode = 'P0002'; end if;
  if not private.can_review(r.adm4) then raise exception 'Di luar wilayah tugasmu' using errcode = '42501'; end if;
  update public.reports set hidden_photos = case
      when hide then (case when path = any(hidden_photos) then hidden_photos else array_append(hidden_photos, path) end)
      else array_remove(hidden_photos, path) end
  where id = r.id;
  update public.photo_flags set resolved_at = now() where photo_path = path and resolved_at is null;
  perform private.audit(case when hide then 'hide_photo' else 'keep_photo' end, 'report', r.id::text,
    (select p.name from public.flood_points p where p.id = r.flood_point_id));
end $$;
revoke execute on function public.resolve_photo from public, anon;
grant execute on function public.resolve_photo to authenticated;

-- ---------------------------------------------------------------------------
-- Posko & faskes per area (data se-Indonesia terlalu banyak untuk dimuat sekaligus)
-- ---------------------------------------------------------------------------
-- Aplikasi: sekitar titik peta (lat/lng). Panel: per wilayah (kode awalan). Tanpa keduanya: posko
-- dan faskes yang diinput manual saja (faskes OpenStreetMap ribuan baris).
drop function public.shelters_list();
create function public.shelters_list(
  region text default null, lat double precision default null, lng double precision default null,
  radius_m int default 30000)
returns table (id bigint, type public.shelter_type, name text, address text, lat double precision, lng double precision,
  phone text, status public.shelter_status, note text, adm4 text, source text)
language sql stable set search_path = '' as $$
  select s.id, s.type, s.name, s.address,
    extensions.st_y(s.location::extensions.geometry), extensions.st_x(s.location::extensions.geometry),
    s.phone, s.status, s.note, s.adm4, s.source
  from public.shelters s
  where (region is null or s.adm4 like region || '%')
    and (shelters_list.lat is null or extensions.st_dwithin(s.location,
      extensions.st_setsrid(extensions.st_makepoint(shelters_list.lng, shelters_list.lat), 4326)::extensions.geography,
      least(radius_m, 100000)))
    and (region is not null or shelters_list.lat is not null or s.osm_ref is null)
  order by s.type, s.name
  limit 3000
$$;
grant execute on function public.shelters_list to anon, authenticated;

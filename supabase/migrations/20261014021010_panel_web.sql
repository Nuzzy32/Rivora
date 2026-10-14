-- Panel web Verifikator & Admin (PRD §8 W01–W06): pengaturan ambang, RPC panel, log aktivitas.
-- Semua aksi panel lewat RPC/trigger di database supaya log aktivitas tidak bisa dilewati klien.

-- ---------------------------------------------------------------------------
-- Pengaturan (W06 "Ambang & batas"), satu baris
-- ---------------------------------------------------------------------------
create table public.app_settings (
  id boolean primary key default true check (id),
  notify_min_depth public.depth_category not null default 'knee' check (notify_min_depth <> 'none'),
  notify_official boolean not null default true,
  notify_verified boolean not null default true,
  stale_hours int not null default 3 check (stale_hours between 1 and 12),
  reports_per_hour int not null default 5 check (reports_per_hour between 1 and 20),
  merge_radius_m int not null default 100 check (merge_radius_m between 50 and 500),
  updated_at timestamptz not null default now()
);
insert into public.app_settings default values;

alter table public.app_settings enable row level security;
grant select on public.app_settings to anon, authenticated;
grant update (notify_min_depth, notify_official, notify_verified, stale_hours, reports_per_hour, merge_radius_m)
  on public.app_settings to authenticated;
create policy "semua bisa lihat" on public.app_settings for select to anon, authenticated using (true);
create policy "admin ubah" on public.app_settings for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Log aktivitas: hanya ditulis fungsi database, tidak lagi langsung dari klien
-- ---------------------------------------------------------------------------
alter table public.audit_logs add column detail text;
create index audit_logs_created_idx on public.audit_logs (created_at desc);
drop policy "staf mencatat" on public.audit_logs;
revoke insert on public.audit_logs from authenticated;

create function private.audit(act text, t_type text, t_id text, info text default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.audit_logs (actor_id, action, target_type, target_id, detail)
  values ((select auth.uid()), act, t_type, t_id, info)
$$;
revoke execute on function private.audit from public;

create function private.depth_label(d public.depth_category) returns text
language sql immutable set search_path = '' as $$
  select case d when 'none' then 'Surut' when 'ankle' then 'Semata kaki' when 'knee' then 'Selutut'
    when 'waist' then 'Sepinggang' else 'Sedada ke atas' end
$$;

-- Catatan tolak "Lainnya" (dibaca pelapor) dan catatan sumber status Resmi.
alter table public.reports add column reject_note text check (char_length(reject_note) <= 120);
alter table public.flood_points add column source_note text check (char_length(source_note) <= 300);

-- ---------------------------------------------------------------------------
-- Aturan yang kini membaca app_settings
-- ---------------------------------------------------------------------------
create or replace function private.before_report() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  s public.app_settings;
  p_id bigint;
begin
  select * into s from public.app_settings;
  if (select count(*) from public.reports
      where user_id = new.user_id and created_at > now() - interval '1 hour') >= s.reports_per_hour then
    raise exception 'Kamu sudah mengirim % laporan dalam 1 jam. Coba lagi nanti.', s.reports_per_hour
      using errcode = 'P0001', hint = 'RATE_LIMITED';
  end if;

  if exists (select 1 from unnest(new.photo_paths) p where p not like new.user_id::text || '/%') then
    raise exception 'Foto tidak valid' using errcode = '22023';
  end if;

  select id into p_id from public.flood_points
  where status <> 'receded' and extensions.st_dwithin(location, new.location, s.merge_radius_m)
  order by extensions.st_distance(location, new.location)
  limit 1;

  if p_id is null then
    insert into public.flood_points (name, location, depth, source)
    values (coalesce(nullif(trim(new.place_name), ''), 'Laporan warga'), new.location, new.depth, 'Laporan warga')
    returning id into p_id;
  else
    update public.flood_points set status = 'active', updated_at = now() where id = p_id and status = 'needs_confirmation';
  end if;

  new.flood_point_id := p_id;
  new.status := 'pending';
  return new;
end $$;

-- Notifikasi: ambang & sumber dari pengaturan; kini juga saat titik Resmi baru ditambahkan.
create or replace function private.notify_watchers() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  s public.app_settings;
  is_danger boolean;
  was_danger boolean := false;
  became_dry boolean := false;
begin
  select * into s from public.app_settings;
  is_danger := new.status = 'active' and new.depth >= s.notify_min_depth
    and ((new.verification = 'official' and s.notify_official) or (new.verification = 'verified' and s.notify_verified));
  if tg_op = 'UPDATE' then
    -- Titik yang sempat "Perlu Konfirmasi" lalu aktif lagi bukan bahaya baru.
    was_danger := coalesce(old.status in ('active', 'needs_confirmation') and old.depth >= s.notify_min_depth
      and ((old.verification = 'official' and s.notify_official) or (old.verification = 'verified' and s.notify_verified)), false);
    became_dry := new.status = 'receded' and old.status <> 'receded';
  end if;
  if not ((is_danger and not was_danger) or became_dry) then return null; end if;

  insert into public.notifications (user_id, flood_point_id, title, body)
  select distinct on (w.user_id) w.user_id, new.id,
    case when became_dry then new.name || ' sudah surut' else w.label || ' · ' || new.name end,
    case when became_dry then 'Surut pukul ' || to_char(new.receded_at at time zone 'Asia/Jakarta', 'HH24.MI') || '. Jalan bisa dilalui lagi.'
         else 'Air ' || case new.depth when 'ankle' then 'semata kaki (± 10 cm)' when 'knee' then 'selutut (± 40 cm)'
           when 'waist' then 'sepinggang (± 80 cm)' else 'sedada ke atas (> 100 cm)' end || '. ' || case new.verification when 'official' then 'Resmi.' else 'Terverifikasi.' end end
  from public.watch_locations w
  where extensions.st_dwithin(w.location, new.location, w.radius_m)
  order by w.user_id, w.radius_m;
  return null;
end $$;

drop trigger notify_watchers on public.flood_points;
create trigger notify_watchers after insert or update on public.flood_points
for each row execute function private.notify_watchers();

select cron.schedule('needs-confirmation', '*/10 * * * *', $$
  update public.flood_points set status = 'needs_confirmation'
  where status = 'active' and updated_at < now() - make_interval(hours => (select stale_hours from public.app_settings))
$$);

-- ---------------------------------------------------------------------------
-- W03 Antrean verifikasi
-- ---------------------------------------------------------------------------
-- Nama pelapor disamarkan; reputasi = laporan sebelumnya yang disetujui. Duplikat = laporan lebih
-- awal dalam radius gabung dengan kategori sama, dalam jendela "Perlu Konfirmasi".
create function public.review_queue(st public.report_status default 'pending')
returns table (
  id bigint, created_at timestamptz, place_name text, district text, point_id bigint, point_name text,
  lat double precision, lng double precision, depth public.depth_category, photo_paths text[], note text,
  status public.report_status, reject_reason public.reject_reason, reject_note text, reviewed_at timestamptz,
  reviewer text, reporter text, prior_total bigint, prior_approved bigint, dup_id bigint, dup_distance_m int
)
language sql stable security definer set search_path = '' as $$
  select r.id, r.created_at, r.place_name, p.district, r.flood_point_id, p.name,
    extensions.st_y(r.location::extensions.geometry), extensions.st_x(r.location::extensions.geometry),
    r.depth, r.photo_paths, r.note, r.status, r.reject_reason, r.reject_note, r.reviewed_at,
    rv.name, 'Warga #' || upper(left(md5(r.user_id::text), 4)),
    h.total, h.approved, d.id, d.dist
  from public.reports r
  cross join public.app_settings s
  left join public.flood_points p on p.id = r.flood_point_id
  left join public.profiles rv on rv.id = r.reviewed_by
  cross join lateral (
    select count(*) as total, count(*) filter (where x.status = 'approved') as approved
    from public.reports x where x.user_id = r.user_id and x.id <> r.id and x.status <> 'pending') h
  left join lateral (
    select x.id, round(extensions.st_distance(x.location, r.location))::int as dist
    from public.reports x
    where x.id <> r.id and x.status <> 'rejected' and x.depth = r.depth
      and x.created_at >= r.created_at - make_interval(hours => s.stale_hours)
      and (x.created_at, x.id) < (r.created_at, r.id)
      and extensions.st_dwithin(x.location, r.location, s.merge_radius_m)
    order by x.created_at limit 1) d on true
  where r.status = st and (select private.is_staff())
  order by r.created_at desc
  limit case when st = 'pending' then 500 else 100 end
$$;

-- US-05: setujui (opsional koreksi kategori) atau tolak dengan alasan. Hanya laporan yang masih menunggu.
drop function public.review_report(bigint, boolean, public.reject_reason);
create function public.review_report(
  report_id bigint, approve boolean, reason public.reject_reason default null,
  note text default null, corrected_depth public.depth_category default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.reports;
  why text;
  place text;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  if not approve and reason is null then raise exception 'Pilih alasan penolakan' using errcode = '22023'; end if;

  update public.reports set
    status = case when approve then 'approved' else 'rejected' end::public.report_status,
    reject_reason = case when approve then null else reason end,
    reject_note = case when approve then null else nullif(left(trim(review_report.note), 120), '') end,
    reviewed_by = (select auth.uid()), reviewed_at = now()
  where id = report_id and status = 'pending' returning * into r;
  if r.id is null then raise exception 'Laporan sudah ditinjau atau tidak ditemukan' using errcode = 'P0002'; end if;
  place := coalesce(nullif(r.place_name, ''), (select p.name from public.flood_points p where p.id = r.flood_point_id));

  if approve then
    update public.flood_points set
      verification = greatest(verification, 'verified'), depth = coalesce(corrected_depth, r.depth), status = 'active', updated_at = now()
    where id = r.flood_point_id;
    why := case when corrected_depth is not null and corrected_depth <> r.depth
      then 'kategori dikoreksi ke ' || private.depth_label(corrected_depth) end;
  else
    -- Ditolak dan tidak ada laporan lain yang masih berlaku: titik hilang dari peta.
    delete from public.flood_points p where p.id = r.flood_point_id and p.verification = 'unverified'
      and not exists (select 1 from public.reports x where x.flood_point_id = p.id and x.status <> 'rejected');
    why := coalesce(r.reject_note, case reason when 'foto_tidak_relevan' then 'Foto tidak relevan'
      when 'lokasi_salah' then 'Lokasi salah' when 'duplikat' then 'Duplikat' else 'Lainnya' end);
  end if;
  perform private.audit(case when approve then 'approve' else 'reject' end, 'report', report_id::text,
    concat_ws(' · ', place, why));
end $$;

-- ---------------------------------------------------------------------------
-- W02/W04 Status lokasi
-- ---------------------------------------------------------------------------
create function public.flood_points_all()
returns table (
  id bigint, name text, district text, lat double precision, lng double precision,
  depth public.depth_category, status public.point_status, verification public.verification,
  source text, source_note text, report_count int, updated_at timestamptz, receded_at timestamptz
)
language sql stable set search_path = '' as $$
  select p.id, p.name, p.district,
    extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
    p.depth, p.status, p.verification, p.source, p.source_note, p.report_count, p.updated_at, p.receded_at
  from public.flood_points p order by p.updated_at desc
$$;

-- US-03: tandai surut pada jam tertentu (tidak lebih awal dari awal kejadian, tidak di masa depan).
create function public.mark_receded(point_id bigint, at_time timestamptz default now()) returns void
language plpgsql security definer set search_path = '' as $$
declare
  n text;
  t timestamptz;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  if at_time > now() + interval '5 minutes' then raise exception 'Jam surut tidak boleh di masa depan' using errcode = '22023'; end if;
  t := greatest(at_time, (select started_at from public.flood_events where flood_point_id = point_id and receded_at is null));
  update public.flood_points set status = 'receded', receded_at = t, updated_at = now()
  where id = point_id and status <> 'receded' returning name into n;
  if n is null then raise exception 'Lokasi sudah surut atau tidak ditemukan' using errcode = 'P0002'; end if;
  perform private.audit('mark_receded', 'flood_point', point_id::text,
    n || ' · ' || to_char(t at time zone 'Asia/Jakarta', 'HH24.MI'));
end $$;

-- Koreksi "surut" yang keliru: kejadian terakhir dibuka lagi (bukan kejadian baru) dengan kategori terakhirnya.
create function public.reopen_point(point_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.flood_events;
  n text;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  -- Kejadian yang ditutup oleh tanda surut ini (trigger menulis jam surut yang sama ke titik dan kejadian).
  select e2.* into e from public.flood_events e2 join public.flood_points p on p.id = e2.flood_point_id
  where e2.flood_point_id = point_id and e2.receded_at = p.receded_at order by e2.started_at desc limit 1;
  update public.flood_events set receded_at = null where id = e.id;
  update public.flood_points set status = 'active', depth = coalesce(e.max_depth, 'ankle'), updated_at = now()
  where id = point_id and status = 'receded' returning name into n;
  if n is null then raise exception 'Lokasi belum surut atau tidak ditemukan' using errcode = 'P0002'; end if;
  perform private.audit('reopen', 'flood_point', point_id::text, n);
end $$;

-- Status Resmi dari kanal Pemkot/BPBD. Ada titik aktif dalam radius gabung → titik itu dinaikkan jadi Resmi.
create function public.publish_official(
  name text, district text, lat double precision, lng double precision,
  depth public.depth_category, source text, note text default null)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  g extensions.geography := extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography;
  p_id bigint;
  n text;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  if depth = 'none' or nullif(trim(source), '') is null or lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'Data status Resmi belum lengkap' using errcode = '22023';
  end if;

  select p.id into p_id from public.flood_points p
  where p.status <> 'receded'
    and extensions.st_dwithin(p.location, g, (select merge_radius_m from public.app_settings))
  order by extensions.st_distance(p.location, g) limit 1;

  if p_id is null then
    insert into public.flood_points (name, district, location, depth, verification, source, source_note)
    values (trim(publish_official.name), nullif(trim(publish_official.district), ''), g, publish_official.depth,
      'official', trim(source), nullif(trim(note), ''))
    returning id, flood_points.name into p_id, n;
  else
    update public.flood_points p set verification = 'official', depth = publish_official.depth, status = 'active',
      source = trim(publish_official.source), source_note = nullif(trim(note), ''),
      district = coalesce(p.district, nullif(trim(publish_official.district), '')), updated_at = now()
    where p.id = p_id returning p.name into n;
  end if;
  perform private.audit('publish_official', 'flood_point', p_id::text, n || ' · ' || trim(source));
  return p_id;
end $$;

-- ---------------------------------------------------------------------------
-- W05 Posko, faskes, kontak: cap pengubah + log
-- ---------------------------------------------------------------------------
create function private.stamp_shelter() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_by := (select auth.uid());
  new.updated_at := now();
  return new;
end $$;

create trigger stamp_shelter before insert or update on public.shelters
for each row execute function private.stamp_shelter();

create function private.audit_data() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Geser urutan kontak bukan perubahan data; tidak dicatat.
  if tg_op = 'UPDATE' and tg_table_name = 'emergency_contacts'
     and to_jsonb(new) - 'sort_order' = to_jsonb(old) - 'sort_order' then
    return null;
  end if;
  perform private.audit(lower(tg_op), tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end::text,
    case when tg_op = 'DELETE' then old.name else new.name end);
  return null;
end $$;

create trigger audit_data after insert or update or delete on public.shelters
for each row execute function private.audit_data();
create trigger audit_data after insert or update or delete on public.emergency_contacts
for each row execute function private.audit_data();

-- ---------------------------------------------------------------------------
-- W06 Pengguna & pengaturan
-- ---------------------------------------------------------------------------
create function public.admin_users()
returns table (id uuid, name text, email text, role public.user_role, is_blocked boolean, created_at timestamptz, report_count bigint)
language sql stable security definer set search_path = '' as $$
  select p.id, p.name, u.email::text, p.role, p.is_blocked, p.created_at,
    (select count(*) from public.reports r where r.user_id = p.id)
  from public.profiles p join auth.users u on u.id = p.id
  where (select private.is_admin())
  order by p.role desc, p.created_at desc
  -- ponytail: tanpa paginasi; tambahkan range() + pencarian di server kalau pengguna > beberapa ribu.
$$;

-- Ganti peran / blokir dicatat. Blokir juga menolak laporan akun itu yang belum ditinjau (hilang dari peta).
create function private.after_profile_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  pts bigint[];
begin
  if new.role is distinct from old.role then
    perform private.audit('set_role', 'user', new.id::text, new.name || ' → ' || new.role);
  end if;
  if new.is_blocked and not old.is_blocked then
    perform private.audit('block', 'user', new.id::text, new.name);
    with rej as (
      update public.reports set status = 'rejected', reject_reason = 'lainnya', reject_note = 'Akun diblokir',
        reviewed_by = (select auth.uid()), reviewed_at = now()
      where user_id = new.id and status = 'pending' returning flood_point_id)
    select array_agg(distinct flood_point_id) into pts from rej;
    delete from public.flood_points p where p.id = any(pts) and p.verification = 'unverified'
      and not exists (select 1 from public.reports x where x.flood_point_id = p.id and x.status <> 'rejected');
  elsif old.is_blocked and not new.is_blocked then
    perform private.audit('unblock', 'user', new.id::text, new.name);
  end if;
  return null;
end $$;

create trigger after_profile_change after update of role, is_blocked on public.profiles
for each row execute function private.after_profile_change();

create function private.audit_settings() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  perform private.audit('update_settings', 'settings', 'app', format('ambang %s, %s jam, %s laporan/jam, radius %s m',
    lower(private.depth_label(new.notify_min_depth)), new.stale_hours, new.reports_per_hour, new.merge_radius_m));
  return new;
end $$;

create trigger audit_settings before update on public.app_settings
for each row execute function private.audit_settings();

-- ---------------------------------------------------------------------------
-- Hak eksekusi
-- ---------------------------------------------------------------------------
revoke execute on function public.review_queue, public.review_report, public.mark_receded, public.reopen_point,
  public.publish_official, public.admin_users from public, anon;
grant execute on function public.review_queue, public.review_report, public.mark_receded, public.reopen_point,
  public.publish_official, public.admin_users, public.flood_points_all to authenticated;

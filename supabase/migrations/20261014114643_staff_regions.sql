-- Panel se-Indonesia (tahap 3): verifikator dibatasi wilayah tugas (kab/kota), admin tetap nasional.
-- Semua pemeriksaan di database (RLS & RPC), bukan hanya disembunyikan di panel.

-- ---------------------------------------------------------------------------
-- Wilayah tugas
-- ---------------------------------------------------------------------------
create table public.staff_regions (
  user_id uuid references public.profiles on delete cascade,
  region text collate "C" references public.regions on update cascade check (length(region) = 5), -- kab/kota
  primary key (user_id, region)
);
alter table public.staff_regions enable row level security;
grant select on public.staff_regions to authenticated;
create policy "milik sendiri atau admin" on public.staff_regions for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));

-- Boleh meninjau data di desa ini? Admin: semua. Verifikator: hanya kab/kota tugasnya (tanpa tugas = tidak ada).
create function private.can_review(code text) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_admin() or (private.is_staff() and code is not null and exists (
    select 1 from public.staff_regions s where s.user_id = (select auth.uid()) and s.region = left(code, 5)))
$$;
revoke execute on function private.can_review from public;
grant execute on function private.can_review to authenticated;

create function private.tz_label(code text) returns text
language sql immutable set search_path = '' as $$
  select case public.tz_of(code) when 'Asia/Makassar' then 'WITA' when 'Asia/Jayapura' then 'WIT' else 'WIB' end
$$;

-- Admin menetapkan wilayah tugas seorang verifikator (daftar lengkap menggantikan yang lama).
create function public.set_staff_regions(uid uuid, regions text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare
  bad text;
begin
  if not private.is_admin() then raise exception 'Hanya admin' using errcode = '42501'; end if;
  select r into bad from unnest(regions) r
  where not exists (select 1 from public.regions x where x.code = r and x.level = 2) limit 1;
  if bad is not null then raise exception 'Wilayah % bukan kab/kota', bad using errcode = '22023'; end if;
  delete from public.staff_regions where user_id = uid and region <> all (regions);
  insert into public.staff_regions (user_id, region) select uid, r from unnest(regions) r on conflict do nothing;
  perform private.audit('set_regions', 'user', uid::text, concat_ws(' → ',
    (select name from public.profiles where id = uid),
    coalesce((select string_agg(x.name, ', ' order by x.name) from public.regions x where x.code = any (regions)), 'tanpa wilayah')));
end $$;
revoke execute on function public.set_staff_regions from public, anon;
grant execute on function public.set_staff_regions to authenticated;

-- Pusat & daftar wilayah untuk pemilih di panel (parent null = provinsi).
create function public.regions_in(parent_code text default null)
returns table (code text, name text, lat double precision, lng double precision)
language sql stable set search_path = '' as $$
  select r.code, r.name, extensions.st_y(r.location::extensions.geometry), extensions.st_x(r.location::extensions.geometry)
  from public.regions r
  where case when parent_code is null then r.level = 1 else r.parent = parent_code end
  order by r.name
$$;
grant execute on function public.regions_in to anon, authenticated;

-- Wilayah tugas akun yang sedang masuk, beserta titik tengahnya (filter & peta di panel).
create function public.my_regions()
returns table (code text, name text, lat double precision, lng double precision)
language sql stable set search_path = '' as $$
  select r.code, r.name, extensions.st_y(r.location::extensions.geometry), extensions.st_x(r.location::extensions.geometry)
  from public.staff_regions s join public.regions r on r.code = s.region
  where s.user_id = (select auth.uid())
  order by r.name
$$;
revoke execute on function public.my_regions from public, anon;
grant execute on function public.my_regions to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: laporan & titik genangan sesuai wilayah tugas
-- ---------------------------------------------------------------------------
drop policy "pemilik atau staf lihat" on public.reports;
create policy "pemilik atau peninjau wilayah lihat" on public.reports for select to authenticated
using (user_id = (select auth.uid()) or private.can_review(adm4));
drop policy "staf tinjau" on public.reports;
create policy "peninjau wilayah tinjau" on public.reports for update to authenticated
using (private.can_review(adm4)) with check (private.can_review(adm4));

drop policy "staf kelola (tambah)" on public.flood_points;
drop policy "staf kelola (ubah)" on public.flood_points;
drop policy "staf kelola (hapus)" on public.flood_points;
create policy "peninjau wilayah (tambah)" on public.flood_points for insert to authenticated with check (private.can_review(adm4));
create policy "peninjau wilayah (ubah)" on public.flood_points for update to authenticated
using (private.can_review(adm4)) with check (private.can_review(adm4));
create policy "peninjau wilayah (hapus)" on public.flood_points for delete to authenticated using (private.can_review(adm4));

-- Kontak darurat per daerah (null = nasional) + nomor nasional BNPB & Basarnas.
alter table public.emergency_contacts add column region text collate "C" references public.regions on update cascade;
update public.emergency_contacts set region = '35.78' where name = 'BPBD Kota Surabaya';
insert into public.emergency_contacts (name, phone, category, sort_order) values
  ('BNPB (Badan Nasional Penanggulangan Bencana)', '117', 'bnpb', 5),
  ('Basarnas (SAR Nasional)', '115', 'sar', 6);

-- ---------------------------------------------------------------------------
-- RPC panel
-- ---------------------------------------------------------------------------


-- Jam surut di notifikasi mengikuti zona waktu lokasi (WIB/WITA/WIT).
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
    case when became_dry then 'Surut pukul ' || to_char(new.receded_at at time zone public.tz_of(new.adm4), 'HH24.MI') || ' ' || private.tz_label(new.adm4) || '. Jalan bisa dilalui lagi.'
         else 'Air ' || case new.depth when 'ankle' then 'semata kaki (± 10 cm)' when 'knee' then 'selutut (± 40 cm)'
           when 'waist' then 'sepinggang (± 80 cm)' else 'sedada ke atas (> 100 cm)' end || '. ' || case new.verification when 'official' then 'Resmi.' else 'Terverifikasi.' end end
  from public.watch_locations w
  where extensions.st_dwithin(w.location, new.location, w.radius_m)
  order by w.user_id, w.radius_m;
  return null;
end $$;

drop function public.review_queue(public.report_status);
create function public.review_queue(st public.report_status default 'pending')
returns table (
  id bigint, created_at timestamptz, place_name text, district text, point_id bigint, point_name text,
  lat double precision, lng double precision, depth public.depth_category, photo_paths text[], note text,
  status public.report_status, reject_reason public.reject_reason, reject_note text, reviewed_at timestamptz,
  reviewer text, reporter text, prior_total bigint, prior_approved bigint, dup_id bigint, dup_distance_m int,
  adm4 text
)
language sql stable security definer set search_path = '' as $$
  select r.id, r.created_at, r.place_name, p.district, r.flood_point_id, p.name,
    extensions.st_y(r.location::extensions.geometry), extensions.st_x(r.location::extensions.geometry),
    r.depth, r.photo_paths, r.note, r.status, r.reject_reason, r.reject_note, r.reviewed_at,
    rv.name, 'Warga #' || upper(left(md5(r.user_id::text), 4)),
    h.total, h.approved, d.id, d.dist, r.adm4
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
  where r.status = st and private.can_review(r.adm4)
  order by r.created_at desc
  limit case when st = 'pending' then 500 else 100 end
$$;

create or replace function public.review_report(
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
  if not private.can_review((select x.adm4 from public.reports x where x.id = report_id)) then
    raise exception 'Laporan di luar wilayah tugasmu' using errcode = '42501';
  end if;
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

create or replace function public.mark_receded(point_id bigint, at_time timestamptz default now()) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a text := (select p.adm4 from public.flood_points p where p.id = point_id);
  n text;
  t timestamptz;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  if not private.can_review((select p.adm4 from public.flood_points p where p.id = point_id)) then
    raise exception 'Lokasi di luar wilayah tugasmu' using errcode = '42501';
  end if;
  if at_time > now() + interval '5 minutes' then raise exception 'Jam surut tidak boleh di masa depan' using errcode = '22023'; end if;
  t := greatest(at_time, (select started_at from public.flood_events where flood_point_id = point_id and receded_at is null));
  update public.flood_points set status = 'receded', receded_at = t, updated_at = now()
  where id = point_id and status <> 'receded' returning name into n;
  if n is null then raise exception 'Lokasi sudah surut atau tidak ditemukan' using errcode = 'P0002'; end if;
  perform private.audit('mark_receded', 'flood_point', point_id::text,
    n || ' · ' || to_char(t at time zone public.tz_of(a), 'HH24.MI') || ' ' || private.tz_label(a));
end $$;

create or replace function public.reopen_point(point_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.flood_events;
  n text;
begin
  if not private.is_staff() then raise exception 'Hanya verifikator' using errcode = '42501'; end if;
  if not private.can_review((select p.adm4 from public.flood_points p where p.id = point_id)) then
    raise exception 'Lokasi di luar wilayah tugasmu' using errcode = '42501';
  end if;
  -- Kejadian yang ditutup oleh tanda surut ini (trigger menulis jam surut yang sama ke titik dan kejadian).
  select e2.* into e from public.flood_events e2 join public.flood_points p on p.id = e2.flood_point_id
  where e2.flood_point_id = point_id and e2.receded_at = p.receded_at order by e2.started_at desc limit 1;
  update public.flood_events set receded_at = null where id = e.id;
  update public.flood_points set status = 'active', depth = coalesce(e.max_depth, 'ankle'), updated_at = now()
  where id = point_id and status = 'receded' returning name into n;
  if n is null then raise exception 'Lokasi belum surut atau tidak ditemukan' using errcode = 'P0002'; end if;
  perform private.audit('reopen', 'flood_point', point_id::text, n);
end $$;

-- district diisi trigger dari kode desa; parameternya dipertahankan agar panel lama tetap jalan.
create or replace function public.publish_official(
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

  if not private.can_review(private.village_near(g)) then
    raise exception 'Lokasi di luar wilayah tugasmu' using errcode = '42501';
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

drop function public.flood_points_all();
create function public.flood_points_all(region text default null)
returns table (
  id bigint, name text, district text, lat double precision, lng double precision,
  depth public.depth_category, status public.point_status, verification public.verification,
  source text, source_note text, report_count int, updated_at timestamptz, receded_at timestamptz, adm4 text
)
language sql stable set search_path = '' as $$
  select p.id, p.name, p.district,
    extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
    p.depth, p.status, p.verification, p.source, p.source_note, p.report_count, p.updated_at, p.receded_at, p.adm4
  from public.flood_points p
  where (region is null or p.adm4 like region || '.%') and private.can_review(p.adm4)
  order by p.updated_at desc
$$;

drop function public.admin_users();
create function public.admin_users()
returns table (id uuid, name text, email text, role public.user_role, is_blocked boolean, created_at timestamptz,
  report_count bigint, regions text[])
language sql stable security definer set search_path = '' as $$
  select p.id, p.name, u.email::text, p.role, p.is_blocked, p.created_at,
    (select count(*) from public.reports r where r.user_id = p.id),
    (select array_agg(s.region order by s.region) from public.staff_regions s where s.user_id = p.id)
  from public.profiles p join auth.users u on u.id = p.id
  where (select private.is_admin())
  order by p.role desc, p.created_at desc
  -- ponytail: tanpa paginasi; tambahkan range() + pencarian di server kalau pengguna > beberapa ribu.
$$;

drop function public.shelters_list();
create function public.shelters_list()
returns table (id bigint, type public.shelter_type, name text, address text, lat double precision, lng double precision,
  phone text, status public.shelter_status, note text, adm4 text)
language sql stable set search_path = '' as $$
  select id, type, name, address, extensions.st_y(location::extensions.geometry), extensions.st_x(location::extensions.geometry), phone, status, note, adm4
  from public.shelters order by type, name
$$;


revoke execute on function public.review_queue, public.review_report, public.mark_receded, public.reopen_point,
  public.publish_official, public.admin_users from public, anon;
grant execute on function public.review_queue, public.review_report, public.mark_receded, public.reopen_point,
  public.publish_official, public.admin_users, public.flood_points_all to authenticated;
grant execute on function public.shelters_list to anon, authenticated;

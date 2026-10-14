-- Wilayah administrasi se-Indonesia (Kepmendagri 2025, data cahyadsn/wilayah & wilayah_boundaries, MIT).
-- Kode bertitik sama dengan BMKG adm4: 35 (prov) · 35.78 (kab/kota) · 35.78.22 (kec) · 35.78.22.1001 (desa/kel).
-- Isi tabel dimuat migrasi berikutnya (dihasilkan supabase/data/build_regions.py).

create extension if not exists pg_trgm with schema extensions;

create table public.regions (
  code text collate "C" primary key check (code ~ '^\d{2}(\.\d{2}(\.\d{2}(\.\d{4})?)?)?$'),
  name text not null,
  level smallint generated always as (
    case length(code) when 2 then 1 when 5 then 2 when 8 then 3 else 4 end) stored,
  parent text collate "C" generated always as (
    case length(code) when 13 then left(code, 8) when 8 then left(code, 5) when 5 then left(code, 2) end) stored,
  label text not null default '', -- "Ketintang, Gayungan, Kota Surabaya, Jawa Timur" (diisi saat impor)
  location extensions.geography(point, 4326) -- titik tengah; ±0,3% desa belum punya
);

create index regions_parent_idx on public.regions (parent);
create index regions_village_location_idx on public.regions using gist (location) where level = 4;
create index regions_label_trgm_idx on public.regions using gin (lower(label) extensions.gin_trgm_ops);

alter table public.regions enable row level security;
grant select on public.regions to anon, authenticated;
create policy "semua bisa lihat" on public.regions for select to anon, authenticated using (true);

-- Zona waktu dari kode provinsi: WITA = Bali, Nusa Tenggara, Kalsel/Kaltim/Kaltara, Sulawesi; WIT = Maluku & Papua.
create function public.tz_of(code text) returns text
language sql immutable set search_path = '' as $$
  select case
    when left(code, 2) in ('51', '52', '53', '63', '64', '65') or left(code, 1) = '7' then 'Asia/Makassar'
    when left(code, 1) in ('8', '9') then 'Asia/Jayapura'
    else 'Asia/Jakarta' end
$$;

-- Desa/kelurahan terdekat dari sebuah titik (titik tengah terdekat, maks. 50 km; di luar itu null).
create function private.village_near(g extensions.geography) returns text
language sql stable set search_path = '' as $$
  select v.code from public.regions v
  where v.level = 4 and v.location is not null and extensions.st_dwithin(v.location, g, 50000)
  order by v.location operator(extensions.<->) g
  limit 1
$$;

-- GPS → desa/kelurahan terdekat. Aplikasi menampilkan hasilnya dan pengguna bisa mengoreksi.
create function public.village_at(lat double precision, lng double precision)
returns table (code text, name text, label text, lat double precision, lng double precision, distance_m int)
language sql stable set search_path = '' as $$
  with here as (select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography g)
  select v.code, v.name, v.label,
    extensions.st_y(v.location::extensions.geometry), extensions.st_x(v.location::extensions.geometry),
    round(extensions.st_distance(v.location, here.g))::int
  from here join public.regions v on v.code = private.village_near(here.g)
$$;

-- Cari wilayah ("gubeng", "ketintang surabaya", "kota bandung"): semua kata harus ada di label.
-- Untuk kab/kota/kecamatan ikut dikembalikan desa wakilnya (terdekat ke titik tengah) sebagai kode prakiraan.
create function public.search_regions(q text)
returns table (code text, name text, level smallint, label text, lat double precision, lng double precision, adm4 text)
language sql stable set search_path = '' as $$
  with words as (
    select array_agg('%' || w || '%') pats
    from regexp_split_to_table(lower(trim(q)), '\s+') w where w <> ''
  ), hits as (
    select r.* from public.regions r, words
    -- Kata pertama lewat indeks trigram, sisanya disaring.
    where char_length(trim(q)) >= 3 and lower(r.label) like words.pats[1] and lower(r.label) like all (words.pats)
    order by r.level, extensions.similarity(lower(r.name), lower(trim(q))) desc, r.label
    limit 20
  )
  select h.code, h.name, h.level, h.label,
    extensions.st_y(h.location::extensions.geometry), extensions.st_x(h.location::extensions.geometry),
    case when h.level = 4 then h.code else (
      select v.code from public.regions v
      where v.level = 4 and v.location is not null and v.code like h.code || '.%'
      order by v.location operator(extensions.<->) h.location
      limit 1) end
  from hits h
  order by h.level, extensions.similarity(lower(h.name), lower(trim(q))) desc, h.label
$$;

grant execute on function public.tz_of, public.village_at, public.search_regions to anon, authenticated;
revoke execute on function private.village_near from public;
grant execute on function private.village_near to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Kode desa di data berlokasi: dasar prakiraan, kontak daerah, dan wilayah tugas verifikator.
-- ---------------------------------------------------------------------------
alter table public.flood_points add column adm4 text collate "C" references public.regions on update cascade;
alter table public.reports add column adm4 text collate "C" references public.regions on update cascade;
alter table public.shelters add column adm4 text collate "C" references public.regions on update cascade;
alter table public.watch_locations add column adm4 text collate "C" references public.regions on update cascade;

create index flood_points_adm4_idx on public.flood_points (adm4);
create index reports_pending_adm4_idx on public.reports (adm4) where status = 'pending';
create index shelters_adm4_idx on public.shelters (adm4);

-- Diisi dari lokasi. Titik genangan: kolom district (dibaca semua UI) ikut jadi nama kecamatan.
create function private.set_adm4() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.adm4 := private.village_near(new.location);
  if tg_table_name = 'flood_points' and new.adm4 is not null then
    new.district := (select name from public.regions where code = left(new.adm4, 8));
  end if;
  return new;
end $$;

create trigger set_adm4 before insert or update of location on public.flood_points
for each row execute function private.set_adm4();
create trigger set_adm4 before insert or update of location on public.reports
for each row execute function private.set_adm4();
create trigger set_adm4 before insert or update of location on public.shelters
for each row execute function private.set_adm4();
create trigger set_adm4 before insert or update of location on public.watch_locations
for each row execute function private.set_adm4();

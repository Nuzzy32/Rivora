-- Prakiraan & peringatan dini BMKG se-Indonesia (tahap 2).
-- Prakiraan tidak lagi diambil terjadwal untuk 6 kecamatan Surabaya, tetapi per desa (adm4) saat dibutuhkan
-- lewat Edge Function bmkg-forecast, lalu disimpan 1 jam untuk semua pengguna.

-- Cache lama berkunci nama kecamatan; isinya hanya cache, aman dibuat ulang.
drop table public.forecast_cache;
create table public.forecast_cache (
  adm4 text collate "C" primary key references public.regions on update cascade on delete cascade,
  forecast_json jsonb not null, -- {slots: [{time (UTC), kind, desc, temp, feels, rain_mm, wind, hum}]}
  rain_end_at timestamptz,
  fetched_at timestamptz not null default now()
);
alter table public.forecast_cache enable row level security;
grant select on public.forecast_cache to anon, authenticated;
create policy "semua bisa lihat" on public.forecast_cache for select to anon, authenticated using (true);

-- Peringatan dini (CAP) dengan poligon area; dicocokkan ke titik desa pengguna.
create table public.weather_warnings (
  id text primary key, -- URL CAP BMKG
  event text not null,
  headline text,
  description text,
  severity text,
  effective timestamptz,
  expires timestamptz not null,
  area extensions.geography(multipolygon, 4326) not null,
  fetched_at timestamptz not null default now()
);
create index weather_warnings_area_idx on public.weather_warnings using gist (area);
alter table public.weather_warnings enable row level security;
grant select on public.weather_warnings to anon, authenticated;
create policy "semua bisa lihat" on public.weather_warnings for select to anon, authenticated using (true);

-- Kuota ke BMKG (60 permintaan/menit/IP): maks. 50/menit dari Edge Function untuk semua pengguna.
create table private.bmkg_quota (
  id boolean primary key default true check (id),
  win timestamptz not null default date_trunc('minute', now()),
  n int not null default 0
);
insert into private.bmkg_quota default values;

create function public.bmkg_take_slot() returns boolean
language sql security definer set search_path = '' as $$
  update private.bmkg_quota set
    n = case when win < date_trunc('minute', now()) then 1 else n + 1 end,
    win = date_trunc('minute', now())
  where id
  returning n <= 50
$$;
revoke execute on function public.bmkg_take_slot from public, anon, authenticated;
grant execute on function public.bmkg_take_slot to service_role;

-- Prakiraan + peringatan aktif untuk satu desa. forecast_json null = belum ada di cache:
-- aplikasi lalu memanggil Edge Function untuk mengambilnya dari BMKG.
create function public.forecast_for(adm4 text)
returns table (adm4 text, label text, tz text, forecast_json jsonb, fetched_at timestamptz, warnings jsonb)
language sql stable set search_path = '' as $$
  select r.code, r.label, public.tz_of(r.code), f.forecast_json, f.fetched_at,
    (select coalesce(jsonb_agg(jsonb_build_object(
        'event', w.event, 'headline', w.headline, 'severity', w.severity, 'expires', w.expires)
        order by w.expires desc), '[]'::jsonb)
     from public.weather_warnings w
     where w.expires > now() and r.location is not null and extensions.st_intersects(w.area, r.location))
  from public.regions r
  left join public.forecast_cache f on f.adm4 = r.code
  where r.code = forecast_for.adm4 and r.level = 4
$$;
grant execute on function public.forecast_for to anon, authenticated;

-- Jadwal: tidak ada lagi pengambilan prakiraan tiap jam; peringatan dini tiap 10 menit.
select cron.unschedule('bmkg-forecast');
select cron.schedule('bmkg-nowcast', '*/10 * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/bmkg-forecast',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'functions_secret_key')
    ),
    body := '{"mode": "nowcast"}'::jsonb,
    timeout_milliseconds := 60000
  )
$$);
select cron.schedule('cleanup-weather-warnings', '20 * * * *', $$
  delete from public.weather_warnings where expires < now() - interval '1 day'
$$);

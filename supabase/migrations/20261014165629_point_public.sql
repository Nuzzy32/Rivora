-- Halaman bagikan titik genangan (web/titik.html) & deep link aplikasi: satu titik + label wilayah.
-- Hanya data yang memang publik di peta (tanpa pelapor, koordinat pelapor, atau foto: PRD US-15).
create function public.flood_point(point_id bigint)
returns table (id bigint, name text, district text, area text, lat double precision, lng double precision,
  depth public.depth_category, status public.point_status, verification public.verification, source text,
  report_count int, updated_at timestamptz, receded_at timestamptz, tz text)
language sql stable set search_path = '' as $$
  select p.id, p.name, p.district,
    (select r.label from public.regions r where r.code = left(p.adm4, 5)),
    extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
    p.depth, p.status, p.verification, p.source, p.report_count, p.updated_at, p.receded_at,
    public.tz_of(p.adm4)
  from public.flood_points p
  where p.id = point_id
$$;
grant execute on function public.flood_point to anon, authenticated;

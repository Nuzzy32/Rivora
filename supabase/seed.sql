-- Data awal (PRD §12: seed supaya peta tidak sepi saat rilis). Nomor & lokasi adalah contoh; cek sebelum rilis.

insert into public.flood_points (name, district, location, segment, depth, status, verification, source, updated_at, receded_at) values
  ('Jl. Ketintang Baru', 'Gayungan', 'SRID=4326;POINT(112.7276 -7.3132)', 'SRID=4326;LINESTRING(112.7251 -7.3129,112.7276 -7.3132,112.7298 -7.3137)', 'knee', 'active', 'verified', 'Laporan warga', now() - interval '12 minutes', null),
  ('Jl. Raya Darmo', 'Tegalsari', 'SRID=4326;POINT(112.7381 -7.2873)', 'SRID=4326;LINESTRING(112.7384 -7.2860,112.7381 -7.2873,112.7377 -7.2887)', 'ankle', 'active', 'official', 'BPBD Kota Surabaya', now() - interval '25 minutes', null),
  ('Jl. Ahmad Yani (depan Royal Plaza)', 'Wonokromo', 'SRID=4326;POINT(112.7350 -7.3083)', 'SRID=4326;LINESTRING(112.7356 -7.3062,112.7350 -7.3083,112.7345 -7.3105)', 'waist', 'active', 'official', 'Command Center 112', now() - interval '8 minutes', null),
  ('Jl. Kertajaya Indah', 'Mulyorejo', 'SRID=4326;POINT(112.7790 -7.2795)', 'SRID=4326;LINESTRING(112.7780 -7.2793,112.7790 -7.2795,112.7799 -7.2797)', 'ankle', 'active', 'unverified', 'Laporan warga', now() - interval '5 minutes', null),
  ('Jl. Stasiun Wonokromo', 'Wonokromo', 'SRID=4326;POINT(112.7372 -7.3020)', 'SRID=4326;LINESTRING(112.7363 -7.3012,112.7372 -7.3020,112.7380 -7.3027)', 'knee', 'needs_confirmation', 'unverified', 'Laporan warga', now() - interval '200 minutes', null),
  ('Jl. Rungkut Industri', 'Rungkut', 'SRID=4326;POINT(112.7560 -7.3335)', 'SRID=4326;LINESTRING(112.7547 -7.3333,112.7560 -7.3335,112.7572 -7.3336)', 'none', 'receded', 'official', 'BPBD Kota Surabaya', now() - interval '92 minutes', now() - interval '92 minutes'),
  ('Candi Lempung', 'Benowo', 'SRID=4326;POINT(112.6380 -7.2430)', null, 'chest', 'active', 'verified', 'Laporan warga', now() - interval '18 minutes', null);

-- Riwayat kejadian yang sudah surut (estimasi surut butuh ≥ 5).
insert into public.flood_events (flood_point_id, started_at, receded_at, max_depth)
select p.id, now() - (d || ' days')::interval, now() - (d || ' days')::interval + (h || ' hours')::interval, v.depth::public.depth_category
from (values
  ('Jl. Ketintang Baru', 3, 2, 'knee'), ('Jl. Ketintang Baru', 20, 3, 'knee'), ('Jl. Ketintang Baru', 48, 1, 'ankle'),
  ('Jl. Ketintang Baru', 290, 2, 'knee'), ('Jl. Ketintang Baru', 300, 2, 'ankle'), ('Jl. Ketintang Baru', 330, 2, 'knee'),
  ('Jl. Ahmad Yani (depan Royal Plaza)', 9, 3, 'waist'), ('Jl. Ahmad Yani (depan Royal Plaza)', 35, 4, 'waist'),
  ('Jl. Ahmad Yani (depan Royal Plaza)', 300, 3, 'knee'), ('Jl. Ahmad Yani (depan Royal Plaza)', 310, 2, 'knee'),
  ('Jl. Ahmad Yani (depan Royal Plaza)', 335, 3, 'waist'),
  ('Candi Lempung', 15, 5, 'chest'), ('Candi Lempung', 40, 6, 'waist'), ('Candi Lempung', 280, 5, 'chest'),
  ('Candi Lempung', 300, 4, 'waist'), ('Candi Lempung', 320, 5, 'chest'), ('Candi Lempung', 330, 7, 'chest'),
  ('Candi Lempung', 345, 5, 'waist'),
  ('Jl. Raya Darmo', 40, 1, 'ankle'), ('Jl. Raya Darmo', 310, 1, 'ankle'),
  ('Jl. Stasiun Wonokromo', 60, 2, 'knee'), ('Jl. Stasiun Wonokromo', 300, 2, 'ankle'), ('Jl. Stasiun Wonokromo', 330, 3, 'knee'),
  ('Jl. Rungkut Industri', 330, 2, 'knee')
) v(name, d, h, depth)
join public.flood_points p on p.name = v.name;

insert into public.shelters (type, name, address, location, status, note) values
  ('posko', 'Posko Balai RW 05 Ketintang', 'Jl. Ketintang Madya No. 5, Gayungan', 'SRID=4326;POINT(112.7240 -7.3165)', 'open', 'Kapasitas 60 orang'),
  ('posko', 'Posko Kelurahan Gayungan', 'Jl. Gayungan VII No. 2, Gayungan', 'SRID=4326;POINT(112.7300 -7.3300)', 'open', 'Dapur umum'),
  ('posko', 'Gedung Serbaguna Wonokromo', 'Jl. Jagir Wonokromo No. 100', 'SRID=4326;POINT(112.7445 -7.3020)', 'full', 'Kapasitas 120 orang'),
  ('faskes', 'Puskesmas Ketintang', 'Jl. Ketintang Baru I, Gayungan', 'SRID=4326;POINT(112.7285 -7.3145)', 'open', 'Buka 24 jam saat siaga'),
  ('faskes', 'RS Islam Jemursari', 'Jl. Jemursari No. 51–57, Wonocolo', 'SRID=4326;POINT(112.7452 -7.3237)', 'open', 'IGD 24 jam'),
  ('faskes', 'RSUD Dr. Soetomo', 'Jl. Mayjen Prof. Dr. Moestopo No. 6–8', 'SRID=4326;POINT(112.7581 -7.2681)', 'open', 'IGD 24 jam');

insert into public.emergency_contacts (name, phone, category, sort_order) values
  ('BPBD Kota Surabaya', '(031) 5312 144', 'bpbd', 1),
  ('Damkar & Penyelamatan', '113', 'damkar', 2),
  ('Ambulans (SPGDT)', '119', 'ambulans', 3),
  ('Polisi', '110', 'polisi', 4);

select private.refresh_risk_areas();

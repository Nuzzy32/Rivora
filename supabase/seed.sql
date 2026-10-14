-- Data awal yang nyata: faskes & kontak darurat. Cek alamat, catatan, dan nomor ke sumber resmi sebelum rilis.
-- Titik genangan dan posko tidak di-seed: genangan datang dari laporan warga/status Resmi, posko diisi Admin
-- dari data BPBD lewat panel, supaya warga tidak pernah melihat data karangan.

insert into public.shelters (type, name, address, location, status, note) values
  ('faskes', 'Puskesmas Ketintang', 'Jl. Ketintang Baru I, Gayungan', 'SRID=4326;POINT(112.7285 -7.3145)', 'open', null),
  ('faskes', 'RS Islam Jemursari', 'Jl. Jemursari No. 51–57, Wonocolo', 'SRID=4326;POINT(112.7452 -7.3237)', 'open', 'IGD 24 jam'),
  ('faskes', 'RSUD Dr. Soetomo', 'Jl. Mayjen Prof. Dr. Moestopo No. 6–8', 'SRID=4326;POINT(112.7581 -7.2681)', 'open', 'IGD 24 jam');

insert into public.emergency_contacts (name, phone, category, sort_order, region) values
  ('BPBD Kota Surabaya', '(031) 99860466', 'bpbd', 1, '35.78'),
  ('Damkar & Penyelamatan', '113', 'damkar', 2, null),
  ('Ambulans (SPGDT)', '119', 'ambulans', 3, null),
  ('Polisi', '110', 'polisi', 4, null);


-- Hapus data contoh dari seed supaya warga tidak melihat genangan atau posko palsu.
-- Hanya baris seed asli: nama sama, dibuat sebelum rilis panel, dan (posko) belum pernah diubah Admin.
-- Faskes nyata dan kontak darurat dibiarkan; dicek & diperbarui lewat panel web.

-- Riwayat kejadian ikut terhapus (flood_events on delete cascade).
delete from public.flood_points
where created_at < '2026-10-14'
  and name in (
    'Jl. Ketintang Baru', 'Jl. Raya Darmo', 'Jl. Ahmad Yani (depan Royal Plaza)', 'Jl. Kertajaya Indah',
    'Jl. Stasiun Wonokromo', 'Jl. Rungkut Industri', 'Candi Lempung'
  );

delete from public.shelters
where type = 'posko' and updated_by is null
  and name in ('Posko Balai RW 05 Ketintang', 'Posko Kelurahan Gayungan', 'Gedung Serbaguna Wonokromo');

select private.refresh_risk_areas();

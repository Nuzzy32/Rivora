-- Realtime: peta & notifikasi di aplikasi diperbarui tanpa muat ulang. RLS tetap berlaku untuk
-- postgres_changes: titik genangan publik, notifikasi hanya untuk pemiliknya.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime; -- sudah ada di proyek Supabase; untuk lingkungan uji
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'flood_points') then
    alter publication supabase_realtime add table public.flood_points;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

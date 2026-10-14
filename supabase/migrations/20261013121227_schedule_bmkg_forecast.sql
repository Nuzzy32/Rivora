-- Panggil Edge Function bmkg-forecast tiap jam (menit ke-5, setelah BMKG memperbarui cache-nya).
-- Butuh dua secret di Vault (dibuat sekali per proyek, bukan di migrasi):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<SECRET_KEY>', 'functions_secret_key');
create extension if not exists pg_net with schema extensions;

select cron.schedule('bmkg-forecast', '5 * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/bmkg-forecast',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'functions_secret_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  )
$$);

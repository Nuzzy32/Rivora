# SIGAP Banjir (mobile)

Aplikasi Flutter untuk warga se-Indonesia: status genangan per lokasi, prakiraan BMKG, laporan warga, posko/faskes, dan panduan siaga. Desain dari Claude Design (`SIGAP Banjir.dc.html`), kebutuhan dari PRD. Backend: Supabase (`../supabase`).

```bash
cp env.example.json env.json   # isi URL + publishable key proyek Supabase
flutter run --dart-define-from-file=env.json
```

`env.json` tidak masuk git. Hanya publishable key yang boleh ada di aplikasi; secret key hanya di Vault/Edge Function.

## Struktur

- `lib/theme.dart`: warna, skala ketinggian air, label verifikasi, komponen dasar
- `lib/art.dart`: ilustrasi cuaca (Wx) dan figur ketinggian air (DepthFig)
- `lib/data.dart`: model + `Api` (Supabase: RPC, tabel, storage, auth)
- `lib/state.dart`: state aplikasi dan navigasi
- `lib/screens/`: layar M01–M14
- `assets/guide.json`: isi Panduan Siaga (offline)

## Backend (Supabase)

- `supabase/migrations/`: skema, RLS, trigger laporan, RPC, storage, pg_cron
- `supabase/seed.sql`: data awal (contoh; cek nomor & lokasi sebelum rilis)
- `supabase/functions/bmkg-forecast/`: prakiraan BMKG tiap jam ke `forecast_cache`
- Vault butuh `project_url` dan `functions_secret_key` (lihat migrasi `schedule_bmkg_forecast`)
- Mengangkat verifikator/admin: `update public.profiles set role = 'verifikator' where id = '<uuid>';` dari SQL editor

## Belum ada

- Notifikasi push (FCM): baris `notifications` sudah dibuat server; tinggal Firebase + Edge Function pengirim
- Panel web Verifikator & Admin (RPC `review_report` sudah siap)
- Cache peta offline setelah aplikasi ditutup
- Kunci akun 5x gagal/15 menit: hook-nya hanya di paket Team; sementara pakai rate limit Auth per IP

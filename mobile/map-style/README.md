# Gaya peta SIGAP Banjir Light

Turunan Mapbox Streets v12 yang lebih kalem agar penanda genangan menonjol: latar abu kebiruan,
air biru muda, taman hijau pudar, label nama lokal (Indonesia), POI disaring ke yang relevan saat
bencana (RS, klinik, sekolah, kampus, polisi, damkar, kantor pemerintahan; lainnya baru tampil di zoom 17+).

Pakai:
1. Mapbox Studio → New style → Upload → pilih `sigap-light.json`, lalu Publish.
2. Salin "Style URL" (`mapbox://styles/<username>/<style_id>`), lalu di `mobile/env.json` tambahkan
   `"MAPBOX_STYLE": "<username>/<style_id>"`.
3. Jalankan ulang aplikasi (nilai env.json dibaca saat build).

Membuat ulang dari Streets terbaru: `python3 build_style.py` (token dibaca dari `../env.json`).

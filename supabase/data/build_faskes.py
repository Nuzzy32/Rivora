"""Bangun migrasi faskes se-Indonesia (rumah sakit & puskesmas) dari OpenStreetMap ke public.shelters.

Sumber: OpenStreetMap lewat Overpass API, lisensi ODbL — wajib atribusi "© OpenStreetMap contributors".

Pakai (dari supabase/data):
  python3 -I build_faskes.py ../migrations/<ts>_faskes_osm.sql

Unduhan disimpan di .cache/overpass_*.json (diabaikan git); hapus folder itu untuk mengambil data terbaru.
Python dari python.org di macOS belum punya sertifikat CA: jalankan dengan SSL_CERT_FILE=/etc/ssl/cert.pem.
Yang diambil: semua amenity=hospital bernama (kecuali yang namanya jelas klinik/praktik/posyandu, lihat NOT_HOSPITAL), plus amenity=clinic / healthcare=centre / healthcare=clinic
yang namanya mengandung "puskesmas". Apotek, praktik dokter/gigi, dan klinik swasta umum tidak diambil.
Duplikat dibuang: objek OSM yang sama, dan nama sama (dinormalkan) dalam radius 100 m.
"""

import json
from datetime import datetime, timedelta, timezone
import math
import re
import sys
import time
import urllib.request
from pathlib import Path

# mail.ru: cermin yang terbukti mutakhir. kumi.systems sempat tertinggal berbulan-bulan (data RS tak lengkap),
# jadi jawaban yang lebih tua dari MAX_AGE_DAYS ditolak.
ENDPOINTS = ["https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
             "https://overpass.kumi.systems/api/interpreter"]
MAX_AGE_DAYS = 14
CACHE = Path(__file__).resolve().parent / ".cache"
# Dipecah per filter: satu kueri gabungan melewati batas waktu gateway Overpass (±120 dtk).
# Filter healthcare=* opsional: sebagian besar puskesmas di OSM bertanda amenity=clinic, jadi kalau server
# sibuk cukup dilewati dengan peringatan setelah satu putaran.
OPTIONAL = {"centre_puskesmas", "hc_clinic_puskesmas"}
FILTERS = {
    "hospital": '["amenity"="hospital"]["name"]',
    "clinic_puskesmas": '["amenity"="clinic"]["name"~"puskesmas",i]',
    "centre_puskesmas": '["healthcare"="centre"]["name"~"puskesmas",i]',
    "hc_clinic_puskesmas": '["healthcare"="clinic"]["name"~"puskesmas",i]',
}
QUERY = '[out:json][timeout:600];area["ISO3166-1"="ID"][admin_level=2]->.id;nwr{}(area.id);out center tags;'
PUSKESMAS = re.compile(r"puskesmas", re.I)
# amenity=hospital yang salah tanda di OSM: klinik, praktik dokter/bidan/gigi, apotek, lab, posyandu.
NOT_HOSPITAL = re.compile(r"^\s*(klinik|clinic|apotek|apotik|praktek|praktik|dokter|drg\b|dr\.|bidan|posyandu|optik"
                          r"|lab(oratorium)?\b|toko|balai pengobatan|bp\b)", re.I)
CHUNK = 1000


def in_indonesia(lat, lng):
    return -11.5 <= lat <= 6.5 and 94.0 <= lng <= 141.5


def fetch(key, f):
    cache = CACHE / f"overpass_{key}.json"
    if cache.exists():
        return json.loads(cache.read_text())
    body = ("data=" + urllib.request.quote(QUERY.format(f))).encode()
    rounds = 1 if key in OPTIONAL else 4
    for attempt in range(rounds):  # server Overpass sering sibuk; ulangi dengan jeda
        for url in ENDPOINTS:
            try:
                req = urllib.request.Request(url, data=body, headers={
                    "User-Agent": "SIGAP-Banjir build_faskes.py (impor faskes sekali jalan; urllib)"})
                with urllib.request.urlopen(req, timeout=660) as r:
                    raw = r.read()
                data = json.loads(raw)  # halaman galat Overpass berupa HTML -> gagal di sini
                if data.get("remark"):
                    raise ValueError(data["remark"][:200])
                base = datetime.fromisoformat(data["osm3s"]["timestamp_osm_base"].replace("Z", "+00:00"))
                if datetime.now(timezone.utc) - base > timedelta(days=MAX_AGE_DAYS):
                    raise ValueError(f"data basi ({base:%Y-%m-%d})")
                CACHE.mkdir(exist_ok=True)
                cache.write_bytes(raw)
                return data
            except Exception as e:
                print(f"gagal {key} @ {url}: {e}", file=sys.stderr)
        if attempt + 1 < rounds:
            time.sleep(60 * (attempt + 1))
    if key in OPTIONAL:
        print(f"PERINGATAN: {key} dilewati (Overpass gagal); jalankan ulang nanti untuk melengkapi", file=sys.stderr)
        return None
    sys.exit("semua endpoint Overpass gagal")


def download():
    got = {k: fetch(k, f) for k, f in FILTERS.items()}
    parts = [p for p in got.values() if p]
    return {"osm3s": parts[0].get("osm3s", {}), "elements": [e for p in parts for e in p["elements"]],
            "skipped": [k for k, p in got.items() if not p]}


def address(t):
    if t.get("addr:full", "").strip():
        return t["addr:full"].strip()
    street = " ".join(x for x in (t.get("addr:street", "").strip(), t.get("addr:housenumber", "").strip()) if x)
    parts = []
    for p in (street, t.get("addr:village"), t.get("addr:suburb"), t.get("addr:subdistrict"),
              t.get("addr:district"), t.get("addr:city")):
        p = (p or "").strip()
        if p and p not in parts:
            parts.append(p)
    return ", ".join(parts)


def phone(t):
    v = t.get("phone") or t.get("contact:phone") or ""
    return v.split(";")[0].strip()


def norm(name):
    return " ".join(re.sub(r"[^\w\s]", " ", name.lower()).split())


def meters(a, b):
    # Jarak equirectangular; cukup akurat untuk 100 m.
    x = math.radians(b[1] - a[1]) * math.cos(math.radians((a[0] + b[0]) / 2))
    return 6371000 * math.hypot(x, math.radians(b[0] - a[0]))


def sql(s):
    return "'" + s.replace("'", "''") + "'"


def main(out):
    data = download()
    rows, skipped, mistag = {}, 0, 0  # dict per osm_ref = dedup objek OSM yang sama
    for e in data["elements"]:
        ref = f"{e['type']}/{e['id']}"
        t = e.get("tags", {})
        name = " ".join(t.get("name", "").split())
        c = e if "lat" in e else e.get("center", {})
        if not name or "lat" not in c or not in_indonesia(c["lat"], c["lon"]):
            skipped += 1
            continue
        if not PUSKESMAS.search(name) and NOT_HOSPITAL.search(name):
            mistag += 1
            continue
        rows[ref] = dict(ref=ref, name=name, address=address(t), phone=phone(t), lat=c["lat"], lng=c["lon"],
                         kind="puskesmas" if PUSKESMAS.search(name) else "rs")

    # Nama sama dalam 100 m = satu tempat; simpan yang datanya paling lengkap.
    kept, by_name, dupes = [], {}, 0
    for r in sorted(rows.values(), key=lambda r: (not r["phone"], not r["address"], r["ref"])):
        near = by_name.setdefault(norm(r["name"]), [])
        if any(meters(p, (r["lat"], r["lng"])) < 100 for p in near):
            dupes += 1
            continue
        near.append((r["lat"], r["lng"]))
        kept.append(r)
    kept.sort(key=lambda r: r["ref"])

    n_rs = sum(r["kind"] == "rs" for r in kept)
    n_pkm = len(kept) - n_rs
    n_phone = sum(bool(r["phone"]) for r in kept)
    n_addr = sum(bool(r["address"]) for r in kept)
    stamp = data.get("osm3s", {}).get("timestamp_osm_base", "?")
    values = [f"({sql(r['ref'])},{sql(r['name'])},{sql(r['address'])},"
              f"{sql(r['phone']) if r['phone'] else 'null'},'SRID=4326;POINT({r['lng']:.7f} {r['lat']:.7f})')"
              for r in kept]

    with open(out, "w") as w:
        w.write(f"""-- Faskes se-Indonesia dari OpenStreetMap: DIHASILKAN supabase/data/build_faskes.py, jangan diedit manual.
-- © OpenStreetMap contributors, lisensi ODbL (openstreetmap.org/copyright). Data OSM per {stamp}.
-- Filter dilewati karena Overpass gagal: {", ".join(data["skipped"]) or "tidak ada"}.
-- {len(kept)} faskes: {n_rs} rumah sakit, {n_pkm} puskesmas; {n_phone} bertelepon, {n_addr} beralamat di OSM.

-- Baris dari OSM wajib dicantumkan atribusinya di aplikasi ("© OpenStreetMap contributors") dan bisa
-- diperbarui dengan menjalankan ulang skrip lalu menerapkan migrasi baru (upsert lewat osm_ref).
-- Faskes yang diinput Admin (osm_ref null) tidak disentuh.
alter table public.shelters
  add column if not exists osm_ref text unique, -- 'node/123', 'way/456', 'relation/789'
  add column if not exists source text;         -- 'OpenStreetMap'; null = diinput Admin

-- Puluhan ribu baris impor tidak dicatat satu per satu di log aktivitas; cukup satu ringkasan di akhir.
alter table public.shelters disable trigger audit_data;

create temp table faskes_osm (
  osm_ref text primary key,
  name text not null,
  address text not null,
  phone text,
  location extensions.geography(point, 4326) not null
);

""")
        for i in range(0, len(values), CHUNK):
            w.write("insert into faskes_osm (osm_ref, name, address, phone, location) values\n")
            w.write(",\n".join(values[i:i + CHUNK]))
            w.write(";\n\n")
        w.write("""-- Data input Admin menang: titik OSM dalam 150 m dari faskes non-OSM dilewati.
insert into public.shelters (type, name, address, location, phone, source, osm_ref)
select 'faskes', o.name, o.address, o.location, o.phone, 'OpenStreetMap', o.osm_ref
from faskes_osm o
where not exists (
  select 1 from public.shelters s
  where s.type = 'faskes' and s.osm_ref is null and extensions.st_dwithin(s.location, o.location, 150))
on conflict (osm_ref) do update
  set name = excluded.name, address = excluded.address, location = excluded.location, phone = excluded.phone;

drop table faskes_osm;

-- Alamat kosong diisi label desa/kelurahan (adm4 diisi trigger set_adm4 saat insert).
update public.shelters set address = r.label
from public.regions r
where shelters.address = '' and r.code = shelters.adm4;

-- Tanpa desa dalam 50 km (mis. sekitar Fakfak): pakai kab/kota terdekat.
update public.shelters s set address = 'Sekitar ' || (
  select r.label from public.regions r where r.level = 2 and r.location is not null
  order by r.location <-> s.location limit 1)
where s.address = '';

-- Untuk pencarian faskes terdekat.
create index if not exists shelters_location_idx on public.shelters using gist (location);

alter table public.shelters enable trigger audit_data;
select private.audit('import', 'shelters', 'osm',
  (select count(*) || ' faskes OpenStreetMap' from public.shelters where source = 'OpenStreetMap'));
""")
    print(f"{len(kept)} faskes ({n_rs} RS, {n_pkm} puskesmas), telepon {n_phone}, alamat {n_addr}, "
          f"dibuang {skipped} tanpa nama/titik, {mistag} bukan RS, {dupes} duplikat dekat -> {out}")


if __name__ == "__main__":
    main(sys.argv[1])

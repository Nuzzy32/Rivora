"""Bangun migrasi data wilayah se-Indonesia untuk tabel public.regions.

Sumber (MIT, (c) cahya dsn):
  - github.com/cahyadsn/wilayah            db/wilayah.sql      kode & nama (Kepmendagri 2025)
  - github.com/cahyadsn/wilayah_boundaries db/kel, db/kec      titik tengah desa/kel & kecamatan

Pakai:
  git clone --depth 1 https://github.com/cahyadsn/wilayah.git
  git clone --depth 1 --filter=blob:none --sparse https://github.com/cahyadsn/wilayah_boundaries.git
  (cd wilayah_boundaries && git sparse-checkout set db/kel db/kec)
  python3 -I build_regions.py wilayah wilayah_boundaries ../migrations/<ts>_regions_data.sql

Hanya kode, nama, dan titik tengah yang diambil (poligon batas tidak). Kab/kota & provinsi memakai
rata-rata titik tengah kecamatannya. Titik di luar kotak Indonesia dibuang (data rusak / lat-lng tertukar).
"""

import re
import subprocess
import sys
from pathlib import Path

NAME = re.compile(r"\('(\d{2}(?:\.\d{2}(?:\.\d{2}(?:\.\d{4})?)?)?)','((?:[^']|'')*)'\)")
POINT = re.compile(r"\('(\d{2}\.\d{2}\.\d{2}(?:\.\d{4})?)','(?:[^']|'')*',(-?[\d.]+),(-?[\d.]+)")
CHUNK = 2000


def in_indonesia(lat, lng):
    return -11.5 <= lat <= 6.5 and 94.0 <= lng <= 141.5


def commit(repo):
    return subprocess.run(["git", "-C", repo, "rev-parse", "--short=12", "HEAD"],
                          capture_output=True, text=True).stdout.strip() or "?"


def sql(s):
    return "'" + s.replace("'", "''") + "'"


def main(wilayah, boundaries, out):
    names = {c: n.replace("''", "'").strip() for c, n in NAME.findall(Path(wilayah, "db/wilayah.sql").read_text())}

    points, bad = {}, 0
    for f in sorted(Path(boundaries, "db").glob("ke[lc]/**/*.sql")):
        for code, lat, lng in POINT.findall(f.read_text(errors="replace")):
            lat, lng = float(lat), float(lng)
            if code not in names:
                continue
            if in_indonesia(lat, lng):
                points[code] = (lat, lng)
            else:
                bad += 1

    # Kab/kota & provinsi: rata-rata titik tengah kecamatan di bawahnya.
    for size in (5, 2):
        groups = {}
        for code, p in points.items():
            if len(code) == 8:
                groups.setdefault(code[:size], []).append(p)
        for code, ps in groups.items():
            points[code] = (sum(p[0] for p in ps) / len(ps), sum(p[1] for p in ps) / len(ps))

    rows = []
    for code in sorted(names):
        p = points.get(code)
        loc = f"'SRID=4326;POINT({p[1]:.6f} {p[0]:.6f})'" if p else "null"
        rows.append(f"({sql(code)},{sql(names[code])},{loc})")

    levels = {n: sum(1 for c in names if len(c) == n) for n in (2, 5, 8, 13)}
    missing = sum(1 for c in names if len(c) == 13 and c not in points)
    with open(out, "w") as w:
        w.write(f"""-- Data wilayah se-Indonesia: DIHASILKAN supabase/data/build_regions.py, jangan diedit manual.
-- Sumber (MIT, (c) cahya dsn): cahyadsn/wilayah@{commit(wilayah)}, cahyadsn/wilayah_boundaries@{commit(boundaries)}
-- {levels[2]} provinsi, {levels[5]} kab/kota, {levels[8]} kecamatan, {levels[13]} desa/kel ({missing} desa tanpa titik tengah).

""")
        for i in range(0, len(rows), CHUNK):
            w.write("insert into public.regions (code, name, location) values\n")
            w.write(",\n".join(rows[i:i + CHUNK]))
            w.write("\non conflict (code) do update set name = excluded.name, location = excluded.location;\n\n")
        w.write("""-- Label pencarian: nama + induknya ("Ketintang, Gayungan, Kota Surabaya, Jawa Timur").
update public.regions r set label = concat_ws(', ', r.name,
  (select k.name from public.regions k where r.level = 4 and k.code = left(r.code, 8)),
  (select b.name from public.regions b where r.level >= 3 and b.code = left(r.code, 5)),
  (select p.name from public.regions p where r.level >= 2 and p.code = left(r.code, 2)));

-- Isi kode desa untuk data yang sudah ada (trigger set_adm4 berjalan karena kolom location disentuh).
update public.flood_points set location = location;
update public.reports set location = location;
update public.shelters set location = location;
update public.watch_locations set location = location;
""")
    print(f"{len(rows)} wilayah {levels}, desa tanpa titik {missing}, titik dibuang {bad} -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:4])

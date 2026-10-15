// Prakiraan & peringatan dini BMKG se-Indonesia (PRD §10, US-09/US-10).
// - POST {adm4}: aplikasi (publishable key) saat cache desa itu kosong/basi. BMKG diambil sekali,
//   disimpan di forecast_cache 1 jam, dibagi ke semua pengguna. Kuota global 50/menit (BMKG: 60/menit/IP).
// - POST {mode:"nowcast"}: pg_cron tiap 10 menit (secret key). Peringatan dini CAP + poligon area
//   disimpan di weather_warnings; aplikasi mencocokkan dengan titik desanya.
import "@supabase/functions-js/edge-runtime.d.ts";
import { type SupabaseContext, withSupabase } from "@supabase/server";

type BmkgSlot = {
  datetime: string; local_datetime: string; t: number; hu: number; ws: number; tp: number; weather_desc: string;
  wd_deg: number; tcc: number;
};
type Slot = {
  time: string; kind: string; desc: string; temp: number; feels: number; rain_mm: number; wind: number; hum: number;
  wind_dir: number; cloud: number;
};
// Pelengkap dari Open-Meteo (CC BY 4.0) untuk yang tidak disediakan BMKG; data inti tetap BMKG.
type Extra = {
  source: "Open-Meteo";
  days?: { date: string; tmin: number; tmax: number; code: number; uv: number; rain_mm: number }[];
  uv?: number; pressure?: number; visibility_m?: number; sunrise?: string; sunset?: string;
  avg_high?: number; // rata-rata suhu tertinggi 10 tahun untuk tanggal ini (±7 hari)
};

const FRESH_MS = 60 * 60_000;
const ADM4 = /^\d{2}\.\d{2}\.\d{2}\.\d{4}$/;

// Kode cuaca BMKG tidak didokumentasikan resmi, jadi baca dari deskripsinya (jam lokal untuk siang/malam).
function kind(desc: string, hour: number): string {
  const d = desc.toLowerCase(), night = hour >= 18 || hour < 6;
  if (d.includes("petir")) return "storm";
  if (d.includes("lebat")) return "heavy";
  if (d.includes("hujan")) return night ? "nightrain" : "rain";
  if (d.includes("cerah") && !d.includes("berawan")) return night ? "nightcloud" : "sun";
  if (d.includes("cerah")) return night ? "nightcloud" : "partly";
  return night ? "nightcloud" : "cloud";
}

// "Terasa" = indeks panas (NOAA Rothfusz); BMKG tidak menyediakan suhu terasa.
function feels(t: number, rh: number): number {
  if (t < 27) return t;
  const f = t * 9 / 5 + 32;
  const hi = -42.379 + 2.04901523 * f + 10.14333127 * rh - 0.22475541 * f * rh - 6.83783e-3 * f * f -
    5.481717e-2 * rh * rh + 1.22874e-3 * f * f * rh + 8.5282e-4 * f * rh * rh - 1.99e-6 * f * f * rh * rh;
  return Math.round((hi - 32) * 5 / 9);
}

const rainy = (k: string) => ["heavy", "storm", "rain", "nightrain"].includes(k);

// Waktu disimpan UTC; aplikasi menampilkan menurut zona waktu desa (WIB/WITA/WIT).
async function forecast(adm4: string): Promise<{ slots: Slot[]; lat: number; lon: number } | null> {
  const r = await fetch(`https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=${adm4}`, { signal: AbortSignal.timeout(8000) });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`BMKG ${adm4}: ${r.status}`);
  const j = await r.json();
  const slots = (j.data[0].cuaca as BmkgSlot[][]).flat().map((s) => ({
    time: s.datetime,
    kind: kind(s.weather_desc, Number(s.local_datetime.slice(11, 13))),
    desc: s.weather_desc,
    temp: s.t,
    feels: feels(s.t, s.hu),
    rain_mm: s.tp ?? 0,
    wind: Math.round(s.ws),
    hum: s.hu,
    wind_dir: s.wd_deg,
    cloud: s.tcc,
  }));
  return { slots, lat: j.lokasi.lat, lon: j.lokasi.lon };
}

const OM_FORECAST = "https://api.open-meteo.com/v1/forecast";
const OM_ARCHIVE = "https://archive-api.open-meteo.com/v1/archive";

// Gagal sebagian = kartu terkait tidak ditampilkan; prakiraan BMKG tetap jalan.
async function openMeteo(lat: number, lon: number): Promise<Extra> {
  const at = `latitude=${lat}&longitude=${lon}&timezone=auto`;
  const now = new Date(), y = now.getUTCFullYear();
  const [f, a] = await Promise.allSettled([
    fetch(`${OM_FORECAST}?${at}&forecast_days=10&current=pressure_msl,uv_index,visibility` +
      `&daily=temperature_2m_max,temperature_2m_min,weather_code,uv_index_max,sunrise,sunset,precipitation_sum`,
      { signal: AbortSignal.timeout(6000) }).then((r) => r.ok ? r.json() : Promise.reject(r.status)),
    fetch(`${OM_ARCHIVE}?${at}&start_date=${y - 10}-01-01&end_date=${y - 1}-12-31&daily=temperature_2m_max`,
      { signal: AbortSignal.timeout(6000) }).then((r) => r.ok ? r.json() : Promise.reject(r.status)),
  ]);
  const x: Extra = { source: "Open-Meteo" };
  if (f.status === "fulfilled") {
    const d = f.value.daily, c = f.value.current;
    x.days = d.time.map((date: string, i: number) => ({
      date, tmin: Math.round(d.temperature_2m_min[i]), tmax: Math.round(d.temperature_2m_max[i]),
      code: d.weather_code[i], uv: Math.round(d.uv_index_max[i] ?? 0), rain_mm: d.precipitation_sum[i] ?? 0,
    }));
    x.uv = Math.round(c.uv_index ?? 0);
    x.pressure = Math.round(c.pressure_msl);
    x.visibility_m = Math.round(c.visibility);
    x.sunrise = d.sunrise[0];
    x.sunset = d.sunset[0];
  } else console.error("open-meteo forecast", f.reason);
  if (a.status === "fulfilled") {
    // Hari-dalam-tahun ±7 hari dari hari ini, semua 10 tahun.
    const doy = (s: string) => Math.floor((Date.parse(s) - Date.parse(s.slice(0, 4) + "-01-01")) / 864e5);
    const today = doy(now.toISOString().slice(0, 10));
    const d = a.value.daily;
    const near = d.time.map((t: string, i: number) => [Math.abs(doy(t) - today), d.temperature_2m_max[i]])
      .filter(([dd, v]: number[]) => (dd <= 7 || dd >= 358) && v != null).map(([, v]: number[]) => v);
    if (near.length) x.avg_high = Math.round(near.reduce((s: number, v: number) => s + v, 0) / near.length);
  } else console.error("open-meteo archive", a.reason);
  return x;
}

// Peringatan dini: RSS daftar peringatan aktif → CAP 1.2 per peringatan (poligon "lat,lon lat,lon …").
async function nowcast(db: SupabaseContext["supabaseAdmin"]) {
  const rss = await (await fetch("https://www.bmkg.go.id/alerts/nowcast/id", { signal: AbortSignal.timeout(8000) })).text();
  const links = [...rss.matchAll(/<item>[\s\S]*?<link>([\s\S]*?)<\/link>/g)].map((m) => m[1].trim());
  const { data: known } = await db.from("weather_warnings").select("id").in("id", links);
  const fresh = links.filter((l) => !known?.some((k) => k.id === l));
  let added = 0;
  for (const link of fresh) {
    const { data: ok } = await db.rpc("bmkg_take_slot");
    if (!ok) break; // sisanya di putaran berikutnya
    const cap = await (await fetch(link, { signal: AbortSignal.timeout(8000) })).text();
    const tag = (n: string) => cap.match(new RegExp(`<${n}>([\\s\\S]*?)</${n}>`))?.[1]?.trim() ?? null;
    const rings = [...cap.matchAll(/<polygon>([\s\S]*?)<\/polygon>/g)].map((m) => {
      const pts = m[1].trim().split(/\s+/).map((p) => p.split(",").reverse().join(" ")); // lat,lon → lon lat
      if (pts[0] !== pts.at(-1)) pts.push(pts[0]);
      return `((${pts.join(",")}))`;
    }).filter((r) => r.split(",").length >= 4);
    if (!rings.length || !tag("expires")) continue;
    const { error } = await db.from("weather_warnings").upsert({
      id: link,
      event: tag("event") ?? "Peringatan dini cuaca",
      headline: tag("headline"),
      description: tag("description"),
      severity: tag("severity"),
      effective: tag("effective"),
      expires: tag("expires"),
      area: `SRID=4326;MULTIPOLYGON(${rings.join(",")})`,
    });
    if (error) console.error(link, error);
    else added++;
  }
  await db.from("weather_warnings").delete().lt("expires", new Date().toISOString());
  return { active: links.length, added };
}

export default {
  fetch: withSupabase({ auth: ["secret", "publishable"] }, async (req, ctx) => {
    const body = await req.json().catch(() => ({}));
    const db = ctx.supabaseAdmin;

    if (body.mode === "nowcast") {
      if (ctx.authMode !== "secret") return Response.json({ error: "forbidden" }, { status: 403 });
      return Response.json(await nowcast(db));
    }

    const adm4 = String(body.adm4 ?? "");
    if (!ADM4.test(adm4)) return Response.json({ error: "adm4 tidak valid" }, { status: 400 });
    const { data: region } = await db.from("regions").select("code").eq("code", adm4).eq("level", 4).maybeSingle();
    if (!region) return Response.json({ error: "desa tidak ditemukan" }, { status: 404 });

    // Pengguna lain mungkin baru saja memperbarui desa yang sama.
    const { data: cached } = await db.from("forecast_cache").select("forecast_json, fetched_at").eq("adm4", adm4).maybeSingle();
    if (cached && Date.now() - Date.parse(cached.fetched_at) < FRESH_MS) return Response.json(cached);

    const { data: ok } = await db.rpc("bmkg_take_slot");
    if (!ok) return Response.json(cached ?? { error: "kuota BMKG penuh, coba sebentar lagi" }, { status: 429 });

    try {
      const f = await forecast(adm4);
      if (!f) return Response.json({ error: "BMKG belum punya prakiraan desa ini" }, { status: 404 });
      const upcoming = f.slots.filter((s) => Date.parse(s.time) > Date.now() - 3 * 3600_000);
      const extra = await openMeteo(f.lat, f.lon);
      const row = {
        adm4,
        forecast_json: { slots: upcoming, extra },
        rain_end_at: upcoming[0] && rainy(upcoming[0].kind) ? upcoming.find((s) => !rainy(s.kind))?.time ?? null : null,
        fetched_at: new Date().toISOString(),
      };
      const { error } = await db.from("forecast_cache").upsert(row);
      if (error) throw error;
      return Response.json({ forecast_json: row.forecast_json, fetched_at: row.fetched_at });
    } catch (e) {
      console.error(adm4, e);
      // Cache lama tetap lebih baik daripada kosong (US-09).
      return Response.json(cached ?? { error: "BMKG tidak bisa dihubungi" }, { status: 502 });
    }
  }),
};

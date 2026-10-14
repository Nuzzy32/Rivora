// Prakiraan & peringatan dini BMKG se-Indonesia (PRD §10, US-09/US-10).
// - POST {adm4}: aplikasi (publishable key) saat cache desa itu kosong/basi. BMKG diambil sekali,
//   disimpan di forecast_cache 1 jam, dibagi ke semua pengguna. Kuota global 50/menit (BMKG: 60/menit/IP).
// - POST {mode:"nowcast"}: pg_cron tiap 10 menit (secret key). Peringatan dini CAP + poligon area
//   disimpan di weather_warnings; aplikasi mencocokkan dengan titik desanya.
import "@supabase/functions-js/edge-runtime.d.ts";
import { type SupabaseContext, withSupabase } from "@supabase/server";

type BmkgSlot = { datetime: string; local_datetime: string; t: number; hu: number; ws: number; tp: number; weather_desc: string };
type Slot = { time: string; kind: string; desc: string; temp: number; feels: number; rain_mm: number; wind: number; hum: number };

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
async function forecast(adm4: string): Promise<Slot[] | null> {
  const r = await fetch(`https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=${adm4}`, { signal: AbortSignal.timeout(8000) });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`BMKG ${adm4}: ${r.status}`);
  const j = await r.json();
  return (j.data[0].cuaca as BmkgSlot[][]).flat().map((s) => ({
    time: s.datetime,
    kind: kind(s.weather_desc, Number(s.local_datetime.slice(11, 13))),
    desc: s.weather_desc,
    temp: s.t,
    feels: feels(s.t, s.hu),
    rain_mm: s.tp ?? 0,
    wind: Math.round(s.ws),
    hum: s.hu,
  }));
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
      const slots = await forecast(adm4);
      if (!slots) return Response.json({ error: "BMKG belum punya prakiraan desa ini" }, { status: 404 });
      const upcoming = slots.filter((s) => Date.parse(s.time) > Date.now() - 3 * 3600_000);
      const row = {
        adm4,
        forecast_json: { slots: upcoming },
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

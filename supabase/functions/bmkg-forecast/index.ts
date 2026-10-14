// Ambil prakiraan BMKG per 3 jam untuk tiap kecamatan, simpan ke forecast_cache (PRD §10, US-09/US-10).
// Dipanggil pg_cron tiap jam dengan secret key; aplikasi hanya membaca cache, tidak pernah memanggil BMKG.
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

// Kode wilayah adm4 (Kemendagri) satu kelurahan per kecamatan, dicek ke API BMKG 2026-10-13.
const DISTRICTS: Record<string, string> = {
  Gayungan: "35.78.22.1001",
  Wonokromo: "35.78.04.1001",
  Gubeng: "35.78.08.1001",
  Tegalsari: "35.78.05.1001",
  Rungkut: "35.78.03.1001",
  Benowo: "35.78.19.1001",
};

type BmkgSlot = { local_datetime: string; t: number; hu: number; ws: number; tp: number; weather_desc: string };
type Slot = { time: string; kind: string; desc: string; temp: number; feels: number; rain_mm: number; wind: number; hum: number };

// Kode cuaca BMKG tidak didokumentasikan resmi, jadi baca dari deskripsinya.
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
const wib = (local: string) => `${local.replace(" ", "T")}+07:00`;

async function forecast(adm4: string): Promise<Slot[]> {
  const r = await fetch(`https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=${adm4}`);
  if (!r.ok) throw new Error(`BMKG ${adm4}: ${r.status}`);
  const j = await r.json();
  return (j.data[0].cuaca as BmkgSlot[][]).flat().map((s) => {
    const hour = Number(s.local_datetime.slice(11, 13));
    return {
      time: wib(s.local_datetime),
      kind: kind(s.weather_desc, hour),
      desc: s.weather_desc,
      temp: s.t,
      feels: feels(s.t, s.hu),
      rain_mm: s.tp ?? 0,
      wind: Math.round(s.ws),
      hum: s.hu,
    };
  });
}

// Peringatan dini (nowcast CAP). ponytail: cocokkan nama kecamatan di teks deskripsi;
// ganti ke uji titik-dalam-poligon CAP kalau sering meleset.
async function warnings(): Promise<{ text: string; expires: string }[]> {
  const rss = await (await fetch("https://www.bmkg.go.id/alerts/nowcast/id")).text();
  const links = [...rss.matchAll(/<item>[\s\S]*?<title>([\s\S]*?)<\/title>[\s\S]*?<link>([\s\S]*?)<\/link>/g)]
    .filter((m) => /jawa timur/i.test(m[1]))
    .map((m) => m[2].trim());
  const out = [];
  for (const link of links) {
    const cap = await (await fetch(link)).text();
    const tag = (n: string) => cap.match(new RegExp(`<${n}>([\\s\\S]*?)</${n}>`))?.[1]?.trim() ?? "";
    out.push({ text: `${tag("event")} ${tag("description")}`, expires: tag("expires") });
  }
  return out;
}

const hm = (iso: string) => iso.slice(11, 16).replace(":", ".");

export default {
  fetch: withSupabase({ auth: ["secret"] }, async (_req, ctx) => {
    const alerts = await warnings().catch(() => []);
    const done: string[] = [], failed: string[] = [];
    for (const [district, adm4] of Object.entries(DISTRICTS)) {
      try {
        const slots = await forecast(adm4);
        const now = Date.now();
        const upcoming = slots.filter((s) => Date.parse(s.time) > now - 3 * 3600_000);
        const alert = alerts.find((a) => a.text.toUpperCase().includes(district.toUpperCase()) && Date.parse(a.expires) > now);
        const warning = alert ? `Potensi cuaca ekstrem hingga pukul ${hm(alert.expires)} WIB di Kec. ${district}. ${alert.text.split(".")[0]}.` : null;
        const rainEnd = upcoming[0] && rainy(upcoming[0].kind) ? upcoming.find((s) => !rainy(s.kind))?.time ?? null : null;
        const { error } = await ctx.supabaseAdmin.from("forecast_cache").upsert({
          district,
          forecast_json: { slots: upcoming, warning },
          rain_end_at: rainEnd,
          fetched_at: new Date().toISOString(),
        });
        if (error) throw error;
        done.push(district);
      } catch (e) {
        console.error(district, e);
        failed.push(district); // cache lama tetap dipakai aplikasi (US-09)
      }
      await new Promise((r) => setTimeout(r, 1100)); // batas BMKG 60 req/menit
    }
    return Response.json({ done, failed }, { status: failed.length && !done.length ? 502 : 200 });
  }),
};

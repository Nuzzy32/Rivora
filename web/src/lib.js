import { createClient } from '@supabase/supabase-js'
import { useEffect, useState } from 'react'

export const sb = createClient(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY)

// Skala ketinggian air PRD §8, sama dengan mobile/lib/theme.dart.
export const DEPTHS = [
  { key: 'none', label: 'Aman / Surut', short: 'Surut', mk: '0', color: '#1FA36A', tint: '#E2F5EB', ink: '#0B6640', fg: '#FFFFFF' },
  { key: 'ankle', label: 'Semata kaki', short: 'Semata kaki', mk: '10', color: '#F4B92F', tint: '#FFF3D3', ink: '#6E4E00', fg: '#3D2B00' },
  { key: 'knee', label: 'Selutut', short: 'Selutut', mk: '40', color: '#F27A2C', tint: '#FFE8D9', ink: '#8F3A05', fg: '#FFFFFF' },
  { key: 'waist', label: 'Sepinggang', short: 'Sepinggang', mk: '80', color: '#E5484D', tint: '#FDE3E4', ink: '#9C161C', fg: '#FFFFFF' },
  { key: 'chest', label: 'Sedada ke atas', short: 'Sedada', mk: '100+', color: '#9B1C50', tint: '#F6E0E9', ink: '#74103A', fg: '#FFFFFF' },
]
export const depthOf = k => DEPTHS.find(d => d.key === k) || DEPTHS[0]
export const depthIdx = k => DEPTHS.findIndex(d => d.key === k)

export const VER = {
  official: { label: 'Resmi', icon: 'shield', color: '#5B47E0', tint: '#EEEBFF' },
  verified: { label: 'Terverifikasi', icon: 'check_circle', color: '#2462D0', tint: '#E6EFFF' },
  unverified: { label: 'Belum Terverifikasi', icon: 'help', color: '#4A5068', tint: '#EEF0F4' },
}

export const REASONS = [
  { key: 'foto_tidak_relevan', label: 'Foto tidak relevan', icon: 'hide_image' },
  { key: 'lokasi_salah', label: 'Lokasi salah', icon: 'wrong_location' },
  { key: 'duplikat', label: 'Duplikat', icon: 'content_copy' },
  { key: 'lainnya', label: 'Lainnya', icon: 'edit_note' },
]

export const DISTRICTS = ['Asemrowo', 'Benowo', 'Bubutan', 'Bulak', 'Dukuh Pakis', 'Gayungan', 'Genteng', 'Gubeng',
  'Gunung Anyar', 'Jambangan', 'Karang Pilang', 'Kenjeran', 'Krembangan', 'Lakarsantri', 'Mulyorejo', 'Pabean Cantian',
  'Pakal', 'Rungkut', 'Sambikerep', 'Sawahan', 'Semampir', 'Simokerto', 'Sukolilo', 'Sukomanunggal', 'Tambaksari',
  'Tandes', 'Tegalsari', 'Tenggilis Mejoyo', 'Wiyung', 'Wonocolo', 'Wonokromo']

// Kunci kategori dibaca aplikasi mobile untuk memilih ikon (emergency.dart).
export const CONTACT_CATEGORIES = { bpbd: 'Bencana (BPBD)', damkar: 'Damkar & penyelamatan', ambulans: 'Medis / ambulans', polisi: 'Keamanan / polisi', umum: 'Darurat umum' }

export const ROLES = { warga: 'Warga', verifikator: 'Verifikator', admin: 'Admin' }

export const SBY = [-7.2756, 112.7426] // Balai Kota Surabaya

const TZ = 'Asia/Jakarta'
export const hm = t => new Date(t).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit', timeZone: TZ })
export const dayMon = t => new Date(t).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', timeZone: TZ })
export const minsSince = t => Math.max(0, Math.round((Date.now() - new Date(t)) / 60000))
export function ago(t) {
  const m = minsSince(t)
  if (m < 1) return 'baru saja'
  if (m < 60) return m + ' menit lalu'
  const h = Math.floor(m / 60)
  if (h >= 24) return Math.floor(h / 24) + ' hari lalu'
  return h + ' jam' + (m % 60 ? ' ' + (m % 60) + ' menit' : '') + ' lalu'
}
export const ini = n => (n || '').trim().split(/\s+/).slice(0, 2).map(x => x[0] || '').join('').toUpperCase()
export const reportCode = id => 'L-' + id

// Jam "HH:MM" hari ini di WIB → ISO.
export function todayAt(hhmm) {
  const day = new Date().toLocaleDateString('sv-SE', { timeZone: TZ })
  return `${day}T${hhmm}:00+07:00`
}
export const nowHHMM = () => new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: TZ })

export async function call(q) {
  const { data, error } = await q
  if (error) throw error
  return data
}

export function errMsg(e) {
  const m = e?.message || String(e)
  if (/fetch|network/i.test(m)) return 'Gagal terhubung. Periksa koneksi lalu coba lagi.'
  return m
}

// Muat data async; `poll` (ms) memuat ulang berkala, `reload()` memuat ulang manual.
export function useLoad(fn, deps = [], poll = 0) {
  const [s, set] = useState({ data: null, error: null })
  const [n, setN] = useState(0)
  useEffect(() => {
    let live = true
    const run = () => fn().then(data => live && set({ data, error: null }), error => live && set(p => ({ ...p, error })))
    run()
    const t = poll && setInterval(run, poll)
    return () => { live = false; clearInterval(t) }
  }, [...deps, n]) // eslint-disable-line react-hooks/exhaustive-deps
  return { ...s, reload: () => setN(x => x + 1) }
}

// Ringkasan prakiraan dari forecast_cache (desa yang pernah dibuka pengguna): slot hujan terdekat 12 jam.
const RAIN = { storm: 3, heavy: 2, rain: 1, nightrain: 1 }
export function rainSummary(rows) {
  if (!rows?.length) return null
  const until = Date.now() + 12 * 3600e3
  const hits = []
  for (const r of rows) for (const s of r.forecast_json?.slots || []) {
    const t = Date.parse(s.time)
    if (RAIN[s.kind] && t + 3 * 3600e3 > Date.now() && t < until) hits.push({ ...s, t, district: r.regions?.name ?? r.adm4 })
  }
  const fetched = rows.reduce((m, r) => (r.fetched_at > m ? r.fetched_at : m), rows[0].fetched_at)
  const warning = rows.map(r => r.forecast_json?.warning).find(Boolean) || null
  if (!hits.length) return { rain: false, fetched, warning }
  const worst = hits.reduce((a, b) => (RAIN[b.kind] > RAIN[a.kind] || (RAIN[b.kind] === RAIN[a.kind] && b.t < a.t) ? b : a))
  const districts = [...new Set(hits.filter(h => h.kind === worst.kind).map(h => h.district))]
  // Hujan berlanjut selama slot 3 jam berikutnya di kecamatan yang sama masih hujan.
  const slots = new Set(hits.filter(h => h.district === worst.district).map(h => h.t))
  let to = worst.t + 3 * 3600e3
  while (slots.has(to)) to += 3 * 3600e3
  return { rain: true, desc: worst.desc, kind: worst.kind, from: worst.t, to, districts, fetched, warning }
}

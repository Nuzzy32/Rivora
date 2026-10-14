// Halaman publik satu titik genangan (link dari tombol Bagikan di aplikasi). Tanpa login.
import { sb, depthOf, VER } from './lib'

const $ = id => document.getElementById(id)
const id = Number(new URLSearchParams(location.search).get('id'))
const TZ = { 'Asia/Jakarta': 'WIB', 'Asia/Makassar': 'WITA', 'Asia/Jayapura': 'WIT' }

const show = el => { $('load').hidden = true; $(el).hidden = false }

const { data, error } = id ? await sb.rpc('flood_point', { point_id: id }) : { data: [] }
const p = data?.[0]
if (error || !p) show('none')
else {
  const d = depthOf(p.status === 'receded' ? 'none' : p.depth)
  const when = t => new Intl.DateTimeFormat('id-ID', { timeZone: p.tz, day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
    .format(new Date(t)).replace(':', '.') + ' ' + (TZ[p.tz] || '')
  document.title = `${p.name} · SIGAP Banjir`
  $('name').textContent = p.name
  $('area').textContent = [p.district && 'Kec. ' + p.district, p.area].filter(Boolean).join(', ')
  $('depth').style.background = d.tint
  $('dot').style.background = d.color
  $('dlabel').textContent = p.status === 'receded' ? 'Sudah surut' : d.label
  $('dlabel').style.color = d.ink
  $('dcm').textContent = p.status === 'receded' ? `sejak ${when(p.receded_at)}` : `± ${d.mk} cm`
  const v = VER[p.verification]
  const pills = [v.label, p.status === 'needs_confirmation' && 'Perlu konfirmasi', p.report_count > 0 && `${p.report_count} laporan warga`].filter(Boolean)
  $('pills').replaceChildren(...pills.map((t, i) => Object.assign(document.createElement('span'), {
    className: 'pill', textContent: t, style: i === 0 ? `background:${v.tint};color:${v.color}` : '' })))
  $('time').textContent = when(p.updated_at)
  $('source').textContent = p.source
  const pad = 0.006
  $('map').src = `https://www.openstreetmap.org/export/embed.html?bbox=${p.lng - pad},${p.lat - pad},${p.lng + pad},${p.lat + pad}&layer=mapnik&marker=${p.lat},${p.lng}`
  $('dir').href = `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}`
  $('app').href = `com.rivora.sigapbanjir://titik/${p.id}`
  $('app').hidden = !/Android|iPhone|iPad/i.test(navigator.userAgent)
  show('ok')
}

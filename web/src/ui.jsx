import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { SBY, depthIdx } from './lib'

export const Icon = ({ n, fill, size = 20, style }) => (
  <span className="ms" aria-hidden="true" style={{ fontSize: size, fontVariationSettings: fill ? "'FILL' 1" : undefined, ...style }}>{n}</span>
)

// Tab bersegmen (latar abu, tab aktif putih).
export const Seg = ({ items, value, onChange, grow }) => (
  <div className={'seg' + (grow ? ' grow' : '')} role="tablist">
    {items.map(t => (
      <button key={t.key} role="tab" aria-selected={value === t.key} className={value === t.key ? 'on' : ''}
        onClick={() => onChange(t.key)}>
        {t.icon && <Icon n={t.icon} size={18} />}{t.label}
      </button>
    ))}
  </div>
)

export const Pill = ({ bg, fg, children, style }) => <span className="pill" style={{ background: bg, color: fg, ...style }}>{children}</span>

export const Empty = ({ icon = 'task_alt', title, sub }) => (
  <div className="empty"><Icon n={icon} size={36} style={{ color: '#AECDFF' }} /><b>{title}</b>{sub && <span>{sub}</span>}</div>
)

export const LoadError = ({ error, retry }) => (
  <div className="banner red"><Icon n="error" /><span style={{ flex: 1 }}>{error?.message || 'Gagal memuat data.'}</span>
    <button className="btn soft sm" onClick={retry}>Coba lagi</button></div>
)

export const Spinner = () => <div className="empty"><span className="spin" aria-label="Memuat" /></div>

// Ilustrasi orang + air (DepthFig di desain).
export function DepthFig({ level, size = 60 }) {
  const lv = Math.max(0, depthIdx(level))
  return (
    <div className="fig" style={{ zoom: size / 80 }} aria-hidden="true">
      <i style={{ left: 0, right: 0, bottom: 0, height: 8, background: '#CBD5E8' }} />
      <i style={{ left: 32, top: 8, width: 16, height: 16, borderRadius: '50%' }} />
      <i style={{ left: 27, top: 27, width: 26, height: 38, borderRadius: '12px 12px 7px 7px' }} />
      <i style={{ left: 22, top: 30, width: 7, height: 30, borderRadius: 4, background: '#5A6283', transform: 'rotate(8deg)' }} />
      <i style={{ left: 51, top: 30, width: 7, height: 30, borderRadius: 4, background: '#5A6283', transform: 'rotate(-8deg)' }} />
      <i style={{ left: 29, top: 62, width: 9, height: 40, borderRadius: 5 }} />
      <i style={{ left: 42, top: 62, width: 9, height: 40, borderRadius: 5 }} />
      <i className="water" style={{ height: [0, 20, 36, 52, 76][lv] }} />
      {lv === 0 && <i className="dry">✓</i>}
    </div>
  )
}

export function Modal({ cfg, onClose, onError }) {
  const [time, setTime] = useState(cfg.defaultTime || '')
  const [busy, setBusy] = useState(false)
  const ok = async () => {
    setBusy(true)
    try { await cfg.onOk(time); onClose() } catch (e) { onError(e) } finally { setBusy(false) }
  }
  useEsc(onClose)
  const tone = { danger: ['#FDE3E4', '#C4282E', '#D93439'], green: ['#E2F5EB', '#0B6640', '#1FA36A'] }[cfg.tone]
    || ['#EEEBFF', '#5B47E0', 'linear-gradient(135deg,#B0A4FF,#806EF8)']
  return (
    <>
      <div className="scrim" style={{ zIndex: 150 }} onClick={onClose} />
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="mtitle">
        <div className="mic" style={{ background: tone[0], color: tone[1] }}><Icon n={cfg.icon || 'help'} fill size={26} /></div>
        <div className="col" style={{ gap: 6 }}>
          <span id="mtitle" style={{ fontSize: 19, fontWeight: 700, lineHeight: 1.3 }}>{cfg.title}</span>
          <span className="muted" style={{ fontSize: 14, lineHeight: 1.55 }}>{cfg.body}</span>
        </div>
        {cfg.time && (
          <label className="row" style={{ gap: 10, fontSize: 13, fontWeight: 600 }}>Surut pukul
            <input className="input" type="time" value={time} onChange={e => setTime(e.target.value)} style={{ width: 120, height: 42 }} />WIB
          </label>
        )}
        <div className="row" style={{ gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
          <button className="btn soft" onClick={onClose}>Batal</button>
          <button className="btn" style={{ background: tone[2], color: '#fff' }} disabled={busy || (cfg.time && !time)} onClick={ok}>{busy ? 'Menyimpan…' : cfg.cta}</button>
        </div>
      </div>
    </>
  )
}

export function Drawer({ title, sub, onClose, footer, children, width = 480 }) {
  useEsc(onClose)
  return (
    <>
      <div className="scrim" onClick={onClose} />
      <div className="drawer" role="dialog" aria-modal="true" aria-label={title} style={{ width }}>
        <div className="row" style={{ padding: '22px 22px 0', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <div className="col" style={{ gap: 4 }}>
            <span style={{ fontSize: 20, fontWeight: 700 }}>{title}</span>
            {sub && <span className="muted" style={{ fontSize: 13, lineHeight: 1.5 }}>{sub}</span>}
          </div>
          <button className="ibtn soft" aria-label="Tutup" onClick={onClose}><Icon n="close" /></button>
        </div>
        <div className="col" style={{ flex: 1, overflowY: 'auto', padding: '20px 22px', gap: 16 }}>{children}</div>
        <div className="row" style={{ padding: '16px 22px 22px', gap: 10, borderTop: '1px solid #EDF1F9' }}>{footer}</div>
      </div>
    </>
  )
}

function useEsc(fn) {
  const r = useRef(fn); r.current = fn
  useEffect(() => {
    const h = e => e.key === 'Escape' && r.current()
    addEventListener('keydown', h)
    return () => removeEventListener('keydown', h)
  }, [])
}

export const Field = ({ label, error, children }) => (
  <label className="col" style={{ gap: 6 }}>
    <span className="lbl">{label}</span>{children}{error && <span className="err">{error}</span>}
  </label>
)

const pinHtml = m => `<div class="pin" style="background:${m.color};color:${m.fg};opacity:${m.opacity ?? 1};border:${m.dashed ? '2.5px dashed' : '3px solid'} #fff">${m.mk}</div>`
const pickIcon = L.divIcon({ className: '', html: '<span class="ms pick">location_on</span>', iconSize: [42, 42], iconAnchor: [21, 39] })

// Peta OSM. markers: [{lat,lng,color,fg,mk,dashed,opacity,title,onClick}], pick: titik terpilih,
// onPick(latlng): klik peta, circle: {lat,lng,r}, center: [lat,lng,zoom] (dipusatkan saat berubah), fit: muat semua marker.
export function MapView({ markers, pick, onPick, circle, center, fit, height = 380 }) {
  const el = useRef(), map = useRef(), layer = useRef(), fitted = useRef(false)
  const pickRef = useRef(onPick); pickRef.current = onPick
  useEffect(() => {
    const m = map.current = L.map(el.current, { scrollWheelZoom: false }).setView(center ? center.slice(0, 2) : SBY, center?.[2] || 12)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap contributors' }).addTo(m)
    layer.current = L.layerGroup().addTo(m)
    m.on('click', e => pickRef.current?.({ lat: +e.latlng.lat.toFixed(6), lng: +e.latlng.lng.toFixed(6) }))
    // Ukuran kontainer grid/drawer baru final setelah layout; tanpa ini tile tidak termuat.
    const ro = new ResizeObserver(() => m.invalidateSize())
    ro.observe(el.current)
    return () => { ro.disconnect(); m.remove() }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const g = layer.current
    g.clearLayers()
    for (const m of markers || []) {
      const mk = L.marker([m.lat, m.lng], { title: m.title, icon: L.divIcon({ className: '', html: pinHtml(m), iconSize: [34, 34] }) })
      if (m.onClick) mk.on('click', m.onClick)
      mk.addTo(g)
    }
    if (circle) L.circle([circle.lat, circle.lng], { radius: circle.r, color: '#806EF8', weight: 2, dashArray: '6 6', fillOpacity: 0.08 }).addTo(g)
    if (pick) L.marker([pick.lat, pick.lng], { icon: pickIcon, interactive: false, keyboard: false }).addTo(g)
    if (fit && !fitted.current && markers?.length) {
      fitted.current = true
      map.current.fitBounds(markers.map(m => [m.lat, m.lng]), { padding: [40, 40], maxZoom: 14 })
    }
  }, [markers, pick, circle, fit])
  const key = center?.join()
  useEffect(() => { if (center) map.current.setView(center.slice(0, 2), center[2] || map.current.getZoom()) }, [key]) // eslint-disable-line react-hooks/exhaustive-deps
  return <div ref={el} className={'map' + (onPick ? ' picking' : '')} style={{ height }} />
}

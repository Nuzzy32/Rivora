import { useMemo } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, ago, hm, depthOf, depthIdx, DEPTHS, minsSince, byRegion } from '../lib'
import { Icon, MapView, LoadError, Spinner, Empty } from '../ui'

export const pointPin = (p, onClick) => {
  const d = depthOf(p.depth)
  return { lat: p.lat, lng: p.lng, color: d.color, fg: d.fg, mk: d.mk, title: p.name, onClick,
    opacity: p.status === 'needs_confirmation' ? 0.45 : 1, dashed: p.verification === 'unverified' }
}

export default function Dashboard() {
  const { go, settings, forecast: fc, region, regionName } = useApp()
  const pts = useLoad(() => call(sb.rpc('flood_points_all', { region: region?.code ?? null })), [], 30000)
  const pend = useLoad(() => call(byRegion(sb.from('reports').select('created_at').eq('status', 'pending'), region?.code).order('created_at')), [], 30000)

  const active = (pts.data || []).filter(p => p.status !== 'receded' && p.depth !== 'none')
  const bar = DEPTHS.slice(1).map(d => ({ ...d, n: active.filter(p => p.depth === d.key).length })).filter(b => b.n)
  const staleH = settings?.stale_hours ?? 3
  const pending = pend.data || []
  const markers = useMemo(() => (pts.data || []).map(p => pointPin(p, () => go('status'))), [pts.data]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="col" style={{ gap: 20 }}>
      {(pts.error || pend.error) && <LoadError error={pts.error || pend.error} retry={() => { pts.reload(); pend.reload() }} />}
      <div className="grid3">
        <div className="card col stat">
          <div className="row between"><span className="lbl2">Menunggu verifikasi</span><div className="sic" style={{ background: '#EEEBFF', color: '#5B47E0' }}><Icon n="fact_check" size={21} /></div></div>
          <span className="big">{pend.data ? pending.length : '–'}</span>
          <span className="muted" style={{ fontSize: 13, lineHeight: 1.5 }}>
            {pending.length ? <>Tertua {ago(pending[0].created_at)}. <b style={{ fontWeight: 600, color: '#6E4E00' }}>{pending.filter(r => minsSince(r.created_at) > staleH * 60).length} menunggu lebih dari {staleH} jam</b>.</> : 'Tidak ada laporan yang menunggu.'}
          </span>
          <button className="btn violet sm" style={{ alignSelf: 'flex-start' }} onClick={() => go('queue')}>Buka antrean<Icon n="arrow_forward" size={18} /></button>
        </div>
        <div className="card col stat">
          <div className="row between"><span className="lbl2">Lokasi aktif tergenang</span><div className="sic" style={{ background: '#E6EFFF', color: '#2462D0' }}><Icon n="water" size={21} /></div></div>
          <span className="big">{pts.data ? active.length : '–'}</span>
          {bar.length > 0 && <div className="row" style={{ height: 12, borderRadius: 6, overflow: 'hidden', gap: 2 }}>{bar.map(b => <div key={b.key} style={{ flex: b.n, height: '100%', background: b.color }} />)}</div>}
          <div className="row" style={{ gap: 12, flexWrap: 'wrap' }}>{bar.map(b => <span key={b.key} className="row" style={{ gap: 6, fontSize: 12, color: '#3B4157' }}><span className="dot" style={{ background: b.color }} />{b.short} {b.n}</span>)}</div>
        </div>
        <div className="card col stat fc">
          <div className="row between"><span style={{ fontSize: 13, fontWeight: 600 }}>Prakiraan BMKG · {regionName}</span><Icon n={fc?.rain ? 'thunderstorm' : 'partly_cloudy_day'} fill size={24} /></div>
          {!fc ? <span style={{ fontSize: 13 }}>Prakiraan belum tersedia.</span> : fc.rain ? <>
            <span style={{ fontSize: 26, fontWeight: 700, lineHeight: 1.2 }}>{fc.desc}</span>
            <span style={{ fontSize: 13, lineHeight: 1.55 }}>{hm(fc.from)}–{hm(fc.to)} WIB di {fc.districts.join(', ')}.{fc.warning ? ' ' + fc.warning : ' Siapkan verifikator jaga.'}</span>
          </> : <>
            <span style={{ fontSize: 26, fontWeight: 700, lineHeight: 1.2 }}>Tidak ada hujan</span>
            <span style={{ fontSize: 13, lineHeight: 1.55 }}>dalam 12 jam ke depan di lokasi yang dibuka warga.</span>
          </>}
          {fc && <span style={{ fontSize: 11, fontWeight: 500 }}>Sumber: BMKG · diambil {hm(fc.fetched)} WIB</span>}
        </div>
      </div>
      <div className="grid-map">
        <div className="card col" style={{ gap: 14 }}>
          <div className="row between"><span className="h2">Peta ringkas</span><span className="sub">Klik penanda untuk kelola status</span></div>
          <MapView markers={markers} fit height={380} center={region?.lat ? [region.lat, region.lng, region.code.length === 2 ? 8 : 12] : undefined} />
        </div>
        <div className="card col" style={{ gap: 6 }}>
          <div className="row between" style={{ paddingBottom: 8 }}><span className="h2">Lokasi aktif</span>
            <button className="link" onClick={() => go('status')}>Kelola<Icon n="chevron_right" size={18} /></button></div>
          {!pts.data ? <Spinner /> : !active.length ? <Empty title="Tidak ada genangan aktif" /> :
            active.slice().sort((a, b) => depthIdx(b.depth) - depthIdx(a.depth)).slice(0, 8).map(p => {
              const d = depthOf(p.depth)
              return (
                <button key={p.id} className="li" onClick={() => go('status')}>
                  <span style={{ width: 10, height: 36, flex: 'none', borderRadius: 5, background: d.color, opacity: p.status === 'needs_confirmation' ? 0.45 : 1 }} />
                  <div className="col" style={{ flex: 1, minWidth: 0, gap: 2 }}>
                    <span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{p.name}</span>
                    <span className="sub">{p.district ? p.district + ' · ' : ''}{ago(p.updated_at)}</span>
                  </div>
                  <span className="pill" style={{ background: d.tint, color: d.ink }}>{d.short}</span>
                </button>
              )
            })}
        </div>
      </div>
    </div>
  )
}

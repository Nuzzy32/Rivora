import { useMemo, useState } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, ago, hm, depthOf, DEPTHS, VER, DISTRICTS, todayAt, nowHHMM } from '../lib'
import { Icon, Drawer, Field, MapView, LoadError, Spinner } from '../ui'
import { pointPin } from './Dashboard'

const FILTERS = [['all', 'Semua'], ['active', 'Aktif'], ['needs_confirmation', 'Perlu konfirmasi'], ['receded', 'Sudah surut']]
const S = { active: ['Aktif', '#E6EFFF', '#2462D0'], needs_confirmation: ['Perlu konfirmasi', '#FFF3D3', '#6E4E00'], receded: ['Sudah surut', '#E2F5EB', '#0B6640'] }

export default function Status() {
  const { ask, toast, fail } = useApp()
  const [filter, setFilter] = useState('all')
  const [official, setOfficial] = useState(false)
  const pts = useLoad(() => call(sb.rpc('flood_points_all')), [], 30000)
  const all = pts.data || []
  const rows = all.filter(p => filter === 'all' || p.status === filter)

  const recede = p => ask({
    title: `Tandai ${p.name} sudah surut?`, icon: 'water', tone: 'green', cta: 'Tandai surut', time: true, defaultTime: nowHHMM(),
    body: 'Penanda di aplikasi berubah hijau dengan label “Sudah Surut”. Warga yang memantau lokasi ini menerima notifikasi.',
    onOk: async t => {
      await call(sb.rpc('mark_receded', { point_id: p.id, at_time: todayAt(t) }))
      toast(`${p.name} ditandai surut · notifikasi “sudah surut” dikirim`); pts.reload()
    },
  })
  const reopen = p => ask({
    title: `Buka lagi status ${p.name}?`, icon: 'undo', cta: 'Buka lagi',
    body: 'Lokasi kembali Aktif dengan kategori terakhir sebelum surut. Pakai ini untuk mengoreksi tanda surut yang keliru.',
    onOk: async () => { await call(sb.rpc('reopen_point', { point_id: p.id })); toast(`${p.name} aktif lagi`); pts.reload() },
  })

  return (
    <div className="card col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 10, flexWrap: 'wrap' }}>
        {FILTERS.map(([k, l]) => (
          <button key={k} className={'filter' + (filter === k ? ' on' : '')} aria-pressed={filter === k} onClick={() => setFilter(k)}>
            {l} · {k === 'all' ? all.length : all.filter(p => p.status === k).length}
          </button>
        ))}
        <div style={{ flex: 1 }} />
        <button className="btn violet" onClick={() => setOfficial(true)}><Icon n="shield" fill />Tambah status Resmi</button>
      </div>
      {pts.error && <LoadError error={pts.error} retry={pts.reload} />}
      <div className="thead st-grid"><span>LOKASI</span><span>KETINGGIAN</span><span>VERIFIKASI</span><span>STATUS</span><span>DIPERBARUI</span><span style={{ textAlign: 'right' }}>AKSI</span></div>
      {!pts.data ? <Spinner /> : rows.map(p => {
        const rec = p.status === 'receded', d = depthOf(rec ? 'none' : p.depth), v = VER[p.verification], s = S[p.status]
        return (
          <div key={p.id} className="tr st-grid">
            <div className="col" style={{ gap: 2, minWidth: 0 }}>
              <span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{p.name}</span>
              <span className="sub ell" title={p.source_note || undefined}>{p.district ? 'Kec. ' + p.district + ' · ' : ''}{p.source}</span>
            </div>
            <span className="pill" style={{ background: d.tint, color: d.ink }}><span className="dot" style={{ background: d.color, width: 8, height: 8 }} />{rec && p.receded_at ? 'Surut ' + hm(p.receded_at) : d.short}</span>
            <span className="row" style={{ gap: 6, fontSize: 12, fontWeight: 600, color: v.color }}><Icon n={v.icon} fill size={17} />{v.label}</span>
            <span className="pill" style={{ background: s[1], color: s[2] }}>{s[0]}</span>
            <span style={{ fontSize: 12, color: '#3B4157' }}>{ago(p.updated_at)}</span>
            <div className="row" style={{ justifyContent: 'flex-end' }}>
              {rec
                ? <button className="btn sm soft" onClick={() => reopen(p)}><Icon n="undo" size={17} />Buka lagi</button>
                : <button className="btn sm green" onClick={() => recede(p)}><Icon n="water_drop" size={17} />Tandai surut</button>}
            </div>
          </div>
        )
      })}
      {pts.data && !rows.length && <div className="sub" style={{ padding: 32, textAlign: 'center', fontSize: 13 }}>Tidak ada lokasi dengan status ini.</div>}
      {official && <Official points={all} onClose={() => setOfficial(false)} onDone={(msg) => { setOfficial(false); setFilter('all'); toast(msg); pts.reload() }} fail={fail} />}
    </div>
  )
}

const CHANNELS = ['BPBD Kota Surabaya', 'Command Center 112', 'Pemkot Surabaya']

function Official({ points, onClose, onDone, fail }) {
  const [f, setF] = useState({ name: '', district: 'Gayungan', depth: null, channel: CHANNELS[0], note: '', at: null })
  const [err, setErr] = useState({})
  const [busy, setBusy] = useState(false)
  const set = x => { setF(p => ({ ...p, ...x })); clear(x) }
  const clear = x => setErr(e => Object.fromEntries(Object.entries(e).filter(([k]) => !(k in x))))
  const markers = useMemo(() => points.filter(p => p.status !== 'receded').map(p => pointPin(p)), [points])

  const save = async () => {
    const e = {}
    if (f.name.trim().length < 2) e.name = 'Isi nama lokasi.'
    if (!f.depth) e.depth = 'Pilih ketinggian air.'
    if (!f.at) e.at = 'Klik peta untuk menaruh titik lokasi.'
    setErr(e)
    if (Object.keys(e).length) return
    setBusy(true)
    try {
      const id = await call(sb.rpc('publish_official', { name: f.name.trim(), district: f.district, lat: f.at.lat, lng: f.at.lng, depth: f.depth, source: f.channel, note: f.note.trim() || null }))
      const near = points.find(p => p.id === id)
      onDone(near ? `${near.name} sudah ada di dekat titik ini, dinaikkan jadi Resmi` : `Status Resmi diterbitkan untuk ${f.name.trim()}`)
    } catch (x) { fail(x) } finally { setBusy(false) }
  }

  return (
    <Drawer title="Tambah status Resmi" sub="Dari kanal Pemkot / BPBD. Langsung tampil dengan label Resmi dan memicu notifikasi." width={460} onClose={onClose}
      footer={<><button className="btn soft big" style={{ flex: 1 }} onClick={onClose}>Batal</button>
        <button className="btn violet big" style={{ flex: 1.6 }} disabled={busy} onClick={save}>{busy ? 'Menerbitkan…' : 'Terbitkan status Resmi'}</button></>}>
      <Field label="Nama jalan / lokasi" error={err.name}>
        <input className={'input' + (err.name ? ' bad' : '')} maxLength={120} value={f.name} onChange={e => set({ name: e.target.value })} placeholder="Contoh: Jl. Jagir Wonokromo" />
      </Field>
      <Field label="Kecamatan">
        <select className="input" value={f.district} onChange={e => set({ district: e.target.value })}>{DISTRICTS.map(d => <option key={d}>{d}</option>)}</select>
      </Field>
      <div className="col" style={{ gap: 8 }}>
        <span className="lbl">Titik di peta <span className="sub" style={{ fontWeight: 400 }}>(klik untuk menaruh; titik aktif dalam radius gabung akan dinaikkan jadi Resmi)</span></span>
        <MapView height={220} markers={markers} pick={f.at} onPick={at => set({ at })} />
        {f.at ? <span className="mono sub">lat {f.at.lat.toFixed(5)}, lng {f.at.lng.toFixed(5)}</span> : err.at && <span className="err">{err.at}</span>}
      </div>
      <div className="col" style={{ gap: 8 }}>
        <span className="lbl">Ketinggian air</span>
        <div className="grid2" style={{ gap: 8 }}>
          {DEPTHS.slice(1).map(o => (
            <button key={o.key} className="opt" aria-pressed={f.depth === o.key} style={f.depth === o.key ? { background: o.tint, borderColor: o.color } : undefined} onClick={() => set({ depth: o.key })}>
              <span className="dot" style={{ background: o.color }} />{o.label}
            </button>
          ))}
        </div>
        {err.depth && <span className="err">{err.depth}</span>}
      </div>
      <div className="col" style={{ gap: 8 }}>
        <span className="lbl">Kanal sumber</span>
        <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
          {CHANNELS.map(c => <button key={c} className={'filter v' + (f.channel === c ? ' on' : '')} aria-pressed={f.channel === c} onClick={() => set({ channel: c })}>{c}</button>)}
        </div>
      </div>
      <Field label="Tautan atau catatan sumber">
        <textarea className="input area" maxLength={300} value={f.note} onChange={e => set({ note: e.target.value })} placeholder="Contoh: unggahan Instagram @bpbdsurabaya pukul 15.30" />
      </Field>
    </Drawer>
  )
}

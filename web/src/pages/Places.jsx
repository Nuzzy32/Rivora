import { useState } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, CONTACT_CATEGORIES } from '../lib'
import { Icon, Seg, Drawer, Field, MapView, LoadError, Spinner, Empty } from '../ui'

const SS = { open: ['Buka', '#E2F5EB', '#0B6640'], full: ['Penuh', '#FDE3E4', '#9C161C'], closed: ['Tutup', '#EEF0F4', '#3B4157'] }
const TYPE = { posko: ['Posko', 'night_shelter', '#5B47E0', '#EEEBFF'], faskes: ['Faskes', 'local_hospital', '#2462D0', '#E6EFFF'] }
const PHONE = /^[0-9+()\s-]{3,20}$/

export default function Places() {
  const { ask, toast, fail } = useApp()
  const [tab, setTab] = useState('posko')
  const [drawer, setDrawer] = useState(null)
  const places = useLoad(() => call(sb.rpc('shelters_list')))
  const contacts = useLoad(() => call(sb.from('emergency_contacts').select('*').order('sort_order').order('id')))
  const isPlaces = tab !== 'kontak'
  const cur = isPlaces ? places : contacts

  const del = (table, x) => ask({
    title: `Hapus ${x.name}?`, icon: 'delete', tone: 'danger', cta: 'Hapus',
    body: 'Data ini langsung hilang dari aplikasi warga. Tindakan tercatat di log aktivitas.',
    onOk: async () => { await call(sb.from(table).delete().eq('id', x.id)); toast(x.name + ' dihapus'); cur.reload() },
  })
  // Tukar urutan dua kontak: urutan = indeks baru, supaya sort_order yang sama pun tetap rapi.
  const move = async (i, j) => {
    const c = contacts.data
    if (j < 0 || j >= c.length) return
    try {
      await Promise.all([call(sb.from('emergency_contacts').update({ sort_order: j + 1 }).eq('id', c[i].id)),
        call(sb.from('emergency_contacts').update({ sort_order: i + 1 }).eq('id', c[j].id))])
    } catch (e) { fail(e) }
    contacts.reload()
  }

  return (
    <div className="card col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 10 }}>
        <Seg value={tab} onChange={setTab} items={[{ key: 'posko', label: 'Posko', icon: 'night_shelter' }, { key: 'faskes', label: 'Faskes', icon: 'local_hospital' }, { key: 'kontak', label: 'Kontak darurat', icon: 'call' }]} />
        <div style={{ flex: 1 }} />
        <button className="btn blue" onClick={() => setDrawer(isPlaces ? { type: tab, name: '', address: '', phone: '', status: 'open', note: '', at: null } : { name: '', phone: '', category: 'bpbd' })}>
          <Icon n="add" />{tab === 'posko' ? 'Tambah posko' : tab === 'faskes' ? 'Tambah faskes' : 'Tambah kontak'}
        </button>
      </div>
      {cur.error && <LoadError error={cur.error} retry={cur.reload} />}
      {!cur.data ? <Spinner /> : isPlaces ? <>
        <div className="thead pl-grid"><span>NAMA</span><span>ALAMAT</span><span>KONTAK</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AKSI</span></div>
        {places.data.filter(x => x.type === tab).map(x => {
          const t = TYPE[x.type], s = SS[x.status]
          return (
            <div key={x.id} className="tr pl-grid">
              <div className="row" style={{ gap: 10, minWidth: 0 }}>
                <div className="sic sm" style={{ background: t[3], color: t[2] }}><Icon n={t[1]} fill size={19} /></div>
                <div className="col" style={{ minWidth: 0 }}><span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{x.name}</span>{x.note && <span className="sub ell">{x.note}</span>}</div>
              </div>
              <span className="ell" style={{ fontSize: 12, color: '#3B4157' }}>{x.address}</span>
              <span style={{ fontSize: 12, color: '#3B4157' }}>{x.phone || '–'}</span>
              <span className="pill" style={{ background: s[1], color: s[2] }}>{s[0]}</span>
              <div className="row" style={{ gap: 6, justifyContent: 'flex-end' }}>
                <button className="ibtn white" aria-label={'Ubah ' + x.name} onClick={() => setDrawer({ ...x, phone: x.phone || '', note: x.note || '', at: { lat: x.lat, lng: x.lng } })}><Icon n="edit" size={18} style={{ color: '#2462D0' }} /></button>
                <button className="ibtn white" aria-label={'Hapus ' + x.name} onClick={() => del('shelters', x)}><Icon n="delete" size={18} style={{ color: '#C4282E' }} /></button>
              </div>
            </div>
          )
        })}
        {!places.data.some(x => x.type === tab) && <Empty icon="add_location_alt" title={`Belum ada ${TYPE[tab][0].toLowerCase()}`} />}
      </> : <>
        <span className="sub" style={{ fontSize: 12, padding: '0 4px' }}>Urutan di bawah = urutan di halaman Darurat aplikasi. Satu ketukan membuka dialer.</span>
        {contacts.data.map((c, i) => (
          <div key={c.id} className="tr ct-grid">
            <span className="num">{i + 1}</span>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{c.name}</span>
            <span style={{ fontSize: 13, color: '#3B4157', fontWeight: 500 }}>{c.phone}</span>
            <span className="sub" style={{ fontSize: 12 }}>{CONTACT_CATEGORIES[c.category] || c.category}</span>
            <div className="row" style={{ gap: 6, justifyContent: 'flex-end' }}>
              <button className="ibtn white" aria-label="Naikkan" disabled={i === 0} onClick={() => move(i, i - 1)}><Icon n="arrow_upward" size={18} /></button>
              <button className="ibtn white" aria-label="Turunkan" disabled={i === contacts.data.length - 1} onClick={() => move(i, i + 1)}><Icon n="arrow_downward" size={18} /></button>
              <button className="ibtn white" aria-label={'Ubah ' + c.name} onClick={() => setDrawer({ ...c })}><Icon n="edit" size={18} style={{ color: '#2462D0' }} /></button>
              <button className="ibtn white" aria-label={'Hapus ' + c.name} onClick={() => del('emergency_contacts', c)}><Icon n="delete" size={18} style={{ color: '#C4282E' }} /></button>
            </div>
          </div>
        ))}
        {!contacts.data.length && <Empty icon="call" title="Belum ada kontak darurat" />}
      </>}
      {drawer && <Editor d={drawer} contacts={contacts.data || []} onClose={() => setDrawer(null)}
        onSaved={name => { setDrawer(null); toast(name + ' disimpan'); cur.reload() }} fail={fail} />}
    </div>
  )
}

function Editor({ d: init, contacts, onClose, onSaved, fail }) {
  const [d, setD] = useState(init)
  const [err, setErr] = useState({})
  const [busy, setBusy] = useState(false)
  const set = x => { setD(p => ({ ...p, ...x })); clear(x) }
  const clear = x => setErr(e => Object.fromEntries(Object.entries(e).filter(([k]) => !(k in x))))
  const isPlace = 'type' in init
  const title = (init.id ? 'Ubah ' : 'Tambah ') + (isPlace ? TYPE[d.type][0].toLowerCase() : 'kontak darurat')

  const save = async () => {
    const e = {}
    if (d.name.trim().length < 2) e.name = 'Nama wajib diisi.'
    if (isPlace ? d.phone.trim() && !PHONE.test(d.phone.trim()) : !PHONE.test(d.phone.trim())) e.phone = 'Nomor hanya berisi angka, spasi, tanda kurung, atau +.'
    if (isPlace && !d.address.trim()) e.address = 'Alamat wajib diisi.'
    if (isPlace && !d.at) e.at = 'Klik peta untuk menaruh titik.'
    setErr(e)
    if (Object.keys(e).length) return
    const row = isPlace
      ? { type: d.type, name: d.name.trim(), address: d.address.trim(), phone: d.phone.trim() || null, status: d.status, note: d.note.trim() || null, location: `SRID=4326;POINT(${d.at.lng} ${d.at.lat})` }
      : { name: d.name.trim(), phone: d.phone.trim(), category: d.category, ...(init.id ? {} : { sort_order: Math.max(0, ...contacts.map(c => c.sort_order)) + 1 }) }
    const t = sb.from(isPlace ? 'shelters' : 'emergency_contacts')
    setBusy(true)
    try {
      await call(init.id ? t.update(row).eq('id', init.id) : t.insert(row))
      onSaved(row.name)
    } catch (x) { fail(x) } finally { setBusy(false) }
  }

  return (
    <Drawer title={title} onClose={onClose}
      footer={<><button className="btn soft big" style={{ flex: 1 }} onClick={onClose}>Batal</button>
        <button className="btn blue big" style={{ flex: 1.6 }} disabled={busy} onClick={save}>{busy ? 'Menyimpan…' : 'Simpan'}</button></>}>
      <Field label="Nama" error={err.name}><input className={'input' + (err.name ? ' bad' : '')} maxLength={120} value={d.name} onChange={e => set({ name: e.target.value })} /></Field>
      <Field label={isPlace ? 'Nomor telepon (opsional)' : 'Nomor telepon'} error={err.phone}>
        <input className={'input' + (err.phone ? ' bad' : '')} type="tel" value={d.phone} onChange={e => set({ phone: e.target.value })} placeholder="Contoh: (031) 1234 567" />
      </Field>
      {!isPlace && (
        <Field label="Kategori (menentukan ikon di aplikasi)">
          <select className="input" value={d.category} onChange={e => set({ category: e.target.value })}>
            {Object.entries(CONTACT_CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
      )}
      {isPlace && <>
        <Field label="Alamat" error={err.address}><input className={'input' + (err.address ? ' bad' : '')} value={d.address} onChange={e => set({ address: e.target.value })} /></Field>
        <div className="col" style={{ gap: 8 }}>
          <span className="lbl">Status</span>
          <div className="row" style={{ gap: 8 }}>
            {Object.entries(SS).map(([k, s]) => (
              <button key={k} className="opt c" aria-pressed={d.status === k} style={{ flex: 1, ...(d.status === k ? { background: s[1], color: s[2], borderColor: s[2] } : {}) }} onClick={() => set({ status: k })}>{s[0]}</button>
            ))}
          </div>
        </div>
        <Field label="Catatan (opsional)"><input className="input" maxLength={120} value={d.note} onChange={e => set({ note: e.target.value })} placeholder="Contoh: Kapasitas 60 orang" /></Field>
        <div className="col" style={{ gap: 8 }}>
          <span className="lbl">Titik di peta <span className="sub" style={{ fontWeight: 400 }}>(klik untuk memindah)</span></span>
          <MapView height={220} pick={d.at} onPick={at => set({ at })} center={init.at ? [init.at.lat, init.at.lng, 16] : undefined} />
          {d.at ? <span className="mono sub">lat {d.at.lat.toFixed(5)}, lng {d.at.lng.toFixed(5)}</span> : err.at && <span className="err">{err.at}</span>}
        </div>
      </>}
    </Drawer>
  )
}

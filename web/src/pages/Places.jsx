import { useState } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, CONTACT_CATEGORIES, inRegion } from '../lib'
import { Icon, Seg, Drawer, Field, MapView, LoadError, Spinner, Empty, RegionPicker } from '../ui'

const SS = { open: ['Buka', '#E2F5EB', '#0B6640'], full: ['Penuh', '#FDE3E4', '#9C161C'], closed: ['Tutup', '#EEF0F4', '#3B4157'] }
const TYPE = { posko: ['Posko', 'night_shelter', '#5B47E0', '#EEEBFF'], faskes: ['Faskes', 'local_hospital', '#2462D0', '#E6EFFF'] }
const PHONE = /^[0-9+()\s-]{3,20}$/

export default function Places() {
  const { ask, toast, fail, region } = useApp()
  const rc = region?.code
  const [tab, setTab] = useState('posko')
  const [drawer, setDrawer] = useState(null)
  const [importing, setImporting] = useState(false)
  // Tanpa wilayah: posko + faskes input manual saja (faskes OpenStreetMap ribuan, dimuat per wilayah).
  const places = useLoad(() => call(sb.rpc('shelters_list', { region: rc ?? null })), [rc])
  const contacts = useLoad(() => call(sb.from('emergency_contacts').select('*, regions(name)').order('sort_order').order('id')))
  // Kontak nasional selalu tampil; kontak daerah hanya yang ada di wilayah terpilih.
  const shownContacts = (contacts.data || []).filter(c => !c.region || !rc || c.region.startsWith(rc) || rc.startsWith(c.region + '.'))
  const shownPlaces = (places.data || []).filter(x => x.type === tab && inRegion(x.adm4, rc))
  const isPlaces = tab !== 'kontak'
  const cur = isPlaces ? places : contacts

  const del = (table, x) => ask({
    title: `Hapus ${x.name}?`, icon: 'delete', tone: 'danger', cta: 'Hapus',
    body: 'Data ini langsung hilang dari aplikasi warga. Tindakan tercatat di log aktivitas.',
    onOk: async () => { await call(sb.from(table).delete().eq('id', x.id)); toast(x.name + ' dihapus'); cur.reload() },
  })
  // Tukar dua kontak yang tampil, lalu nomori ulang seluruh daftar (hanya baris yang berubah disimpan).
  const move = async (i, j) => {
    if (j < 0 || j >= shownContacts.length) return
    const all = [...contacts.data]
    const a = all.indexOf(shownContacts[i]), b = all.indexOf(shownContacts[j])
    ;[all[a], all[b]] = [all[b], all[a]]
    try {
      await Promise.all(all.map((c, k) => c.sort_order !== k + 1 && call(sb.from('emergency_contacts').update({ sort_order: k + 1 }).eq('id', c.id))))
    } catch (e) { fail(e) }
    contacts.reload()
  }

  return (
    <div className="card col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 10 }}>
        <Seg value={tab} onChange={setTab} items={[{ key: 'posko', label: 'Posko', icon: 'night_shelter' }, { key: 'faskes', label: 'Faskes', icon: 'local_hospital' }, { key: 'kontak', label: 'Kontak darurat', icon: 'call' }]} />
        <div style={{ flex: 1 }} />
        <button className="btn soft" onClick={() => setImporting(true)}><Icon n="upload_file" />Impor CSV</button>
        <button className="btn blue" onClick={() => setDrawer(isPlaces ? { type: tab, name: '', address: '', phone: '', status: 'open', note: '', at: null } : { name: '', phone: '', category: 'bpbd', area: rc?.length === 5 ? region : null })}>
          <Icon n="add" />{tab === 'posko' ? 'Tambah posko' : tab === 'faskes' ? 'Tambah faskes' : 'Tambah kontak'}
        </button>
      </div>
      {cur.error && <LoadError error={cur.error} retry={cur.reload} />}
      {!cur.data ? <Spinner /> : isPlaces ? <>
        <div className="thead pl-grid"><span>NAMA</span><span>ALAMAT</span><span>KONTAK</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AKSI</span></div>
        {shownPlaces.map(x => {
          const t = TYPE[x.type], s = SS[x.status]
          return (
            <div key={x.id} className="tr pl-grid">
              <div className="row" style={{ gap: 10, minWidth: 0 }}>
                <div className="sic sm" style={{ background: t[3], color: t[2] }}><Icon n={t[1]} fill size={19} /></div>
                <div className="col" style={{ minWidth: 0 }}><span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{x.name}</span>{(x.note || x.source) && <span className="sub ell">{[x.source === 'OpenStreetMap' && '© OpenStreetMap', x.note].filter(Boolean).join(' · ')}</span>}</div>
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
        {!shownPlaces.length && <Empty icon="add_location_alt" title={`Belum ada ${TYPE[tab][0].toLowerCase()}`} sub={tab === 'faskes' && !rc ? 'Faskes dari OpenStreetMap tampil setelah memilih wilayah di atas.' : undefined} />}
        {tab === 'faskes' && !rc && shownPlaces.length > 0 && <span className="sub" style={{ padding: '0 4px' }}>Menampilkan faskes input manual. Pilih wilayah untuk melihat juga faskes dari OpenStreetMap.</span>}
      </> : <>
        <span className="sub" style={{ fontSize: 12, padding: '0 4px' }}>Urutan di bawah = urutan di halaman Darurat aplikasi. Satu ketukan membuka dialer.</span>
        {shownContacts.map((c, i) => (
          <div key={c.id} className="tr ct-grid">
            <span className="num">{i + 1}</span>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{c.name}</span>
            <span style={{ fontSize: 13, color: '#3B4157', fontWeight: 500 }}>{c.phone}</span>
            <span className="sub" style={{ fontSize: 12 }}>{CONTACT_CATEGORIES[c.category] || c.category} · {c.regions?.name ?? 'Nasional'}</span>
            <div className="row" style={{ gap: 6, justifyContent: 'flex-end' }}>
              <button className="ibtn white" aria-label="Naikkan" disabled={i === 0} onClick={() => move(i, i - 1)}><Icon n="arrow_upward" size={18} /></button>
              <button className="ibtn white" aria-label="Turunkan" disabled={i === shownContacts.length - 1} onClick={() => move(i, i + 1)}><Icon n="arrow_downward" size={18} /></button>
              <button className="ibtn white" aria-label={'Ubah ' + c.name} onClick={() => setDrawer({ ...c, area: c.region ? { code: c.region, name: c.regions?.name } : null })}><Icon n="edit" size={18} style={{ color: '#2462D0' }} /></button>
              <button className="ibtn white" aria-label={'Hapus ' + c.name} onClick={() => del('emergency_contacts', c)}><Icon n="delete" size={18} style={{ color: '#C4282E' }} /></button>
            </div>
          </div>
        ))}
        {!shownContacts.length && <Empty icon="call" title="Belum ada kontak darurat" />}
      </>}
      {importing && <Importer kind={tab} contacts={contacts.data || []} onClose={() => setImporting(false)}
        onDone={n => { setImporting(false); toast(n + ' baris diimpor'); cur.reload() }} fail={fail} />}
      {drawer && <Editor d={drawer} contacts={contacts.data || []} onClose={() => setDrawer(null)}
        onSaved={name => { setDrawer(null); toast(name + ' disimpan'); cur.reload() }} fail={fail} />}
    </div>
  )
}

function Editor({ d: init, contacts, onClose, onSaved, fail }) {
  const { region } = useApp()
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
      : { name: d.name.trim(), phone: d.phone.trim(), category: d.category, region: d.area?.code?.length === 5 ? d.area.code : null, ...(init.id ? {} : { sort_order: Math.max(0, ...contacts.map(c => c.sort_order)) + 1 }) }
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
      {!isPlace && (
        <div className="col" style={{ gap: 8 }}>
          <span className="lbl">Berlaku di <span className="sub" style={{ fontWeight: 400 }}>(kosongkan = nasional, mis. 112, BNPB)</span></span>
          <RegionPicker kabOnly value={d.area} onChange={area => set({ area })} />
          <span className="sub">{d.area?.code?.length === 5 ? `Hanya untuk warga di ${d.area.name}` : 'Nasional: tampil untuk semua warga'}</span>
        </div>
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
          <MapView height={220} pick={d.at} onPick={at => set({ at })} center={init.at ? [init.at.lat, init.at.lng, 16] : region?.lat ? [region.lat, region.lng, 12] : undefined} />
          {d.at ? <span className="mono sub">lat {d.at.lat.toFixed(5)}, lng {d.at.lng.toFixed(5)}</span> : err.at && <span className="err">{err.at}</span>}
        </div>
      </>}
    </Drawer>
  )
}

// ---------------------------------------------------------------------------
// Impor CSV (mis. daftar BPBD dari sumber resmi, posko dari dinas setempat)
// ---------------------------------------------------------------------------
const COLS = {
  kontak: ['nama', 'telepon', 'kategori', 'kode_wilayah'],
  place: ['nama', 'alamat', 'lat', 'lng', 'telepon', 'status', 'catatan'],
}
const EXAMPLE = {
  kontak: ['BPBD Kota Contoh', '(021) 000 0000', 'bpbd', '31.71'],
  place: ['RSUD Contoh', 'Jl. Contoh No. 1', '-6.2000', '106.8166', '(021) 000 0000', 'open', ''],
}

// CSV sederhana: koma atau titik koma, tanda kutip ganda untuk sel berisi pemisah.
function parseCsv(text) {
  const sep = (text.split('\n')[0].match(/;/g) || []).length > (text.split('\n')[0].match(/,/g) || []).length ? ';' : ','
  const rows = [[]]
  let cell = '', q = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++ } else if (c === '"') q = false; else cell += c
    } else if (c === '"') q = true
    else if (c === sep) { rows.at(-1).push(cell); cell = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++
      rows.at(-1).push(cell); cell = ''; rows.push([])
    } else cell += c
  }
  rows.at(-1).push(cell)
  return rows.filter(r => r.some(x => x.trim()))
}

function Importer({ kind, contacts, onClose, onDone, fail }) {
  const isContact = kind === 'kontak'
  const cols = COLS[isContact ? 'kontak' : 'place']
  const [res, setRes] = useState(null) // { rows: [...], errors: [{line, msg}], skipped }
  const [busy, setBusy] = useState(false)
  const label = isContact ? 'kontak darurat' : TYPE[kind][0].toLowerCase()

  const template = () => {
    const csv = [cols, EXAMPLE[isContact ? 'kontak' : 'place']].map(r => r.map(x => /[",;]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x).join(',')).join('\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv' }))
    a.download = `templat-${isContact ? 'kontak' : kind}.csv`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const read = async file => {
    const raw = parseCsv((await file.text()).replace(/^\ufeff/, ''))
    const head = (raw.shift() || []).map(h => h.trim().toLowerCase())
    const miss = cols.filter(c => !head.includes(c) && !['kode_wilayah', 'telepon', 'status', 'catatan'].includes(c))
    if (miss.length) return setRes({ rows: [], errors: [{ line: 1, msg: 'Kolom wajib tidak ada: ' + miss.join(', ') }], skipped: 0 })
    const get = (r, k) => (r[head.indexOf(k)] ?? '').trim()
    const rows = [], errors = []
    let skipped = 0
    // Kode kab/kota dicek ke tabel wilayah sekaligus.
    const codes = isContact ? [...new Set(raw.map(r => get(r, 'kode_wilayah')).filter(Boolean))] : []
    let known = new Set()
    if (codes.length) {
      try { known = new Set((await call(sb.from('regions').select('code').in('code', codes).in('level', [1, 2]))).map(x => x.code)) } catch (e) { return fail(e) }
    }
    const seen = new Set(contacts.map(c => c.phone.replace(/\D/g, '') + '|' + (c.region || '')))
    raw.forEach((r, i) => {
      const line = i + 2, nama = get(r, 'nama'), tel = get(r, 'telepon')
      const bad = msg => errors.push({ line, msg })
      if (nama.length < 2) return bad('nama kosong')
      if (tel && !PHONE.test(tel)) return bad(`telepon "${tel}" tidak valid`)
      if (isContact) {
        const kat = get(r, 'kategori').toLowerCase(), kode = get(r, 'kode_wilayah')
        if (!tel) return bad('telepon wajib untuk kontak')
        if (!CONTACT_CATEGORIES[kat]) return bad(`kategori "${kat}" tidak dikenal (pakai: ${Object.keys(CONTACT_CATEGORIES).join(', ')})`)
        if (kode && !known.has(kode)) return bad(`kode_wilayah "${kode}" bukan provinsi/kab/kota (contoh: 35 atau 35.78)`)
        const key = tel.replace(/\D/g, '') + '|' + kode
        if (seen.has(key)) { skipped++; return }
        seen.add(key)
        rows.push({ name: nama, phone: tel, category: kat, region: kode || null })
      } else {
        const lat = Number(get(r, 'lat').replace(',', '.')), lng = Number(get(r, 'lng').replace(',', '.'))
        const st = (get(r, 'status') || 'open').toLowerCase()
        if (!get(r, 'alamat')) return bad('alamat kosong')
        if (!(lat >= -11.5 && lat <= 6.5 && lng >= 94 && lng <= 141.5)) return bad('lat/lng di luar Indonesia')
        if (!SS[st]) return bad(`status "${st}" harus open, full, atau closed`)
        rows.push({ type: kind, name: nama, address: get(r, 'alamat'), phone: tel || null, status: st, note: get(r, 'catatan') || null, location: `SRID=4326;POINT(${lng} ${lat})` })
      }
    })
    setRes({ rows, errors, skipped })
  }

  const run = async () => {
    setBusy(true)
    try {
      const base = Math.max(0, ...contacts.map(c => c.sort_order))
      const rows = isContact ? res.rows.map((r, i) => ({ ...r, sort_order: base + i + 1 })) : res.rows
      for (let i = 0; i < rows.length; i += 500) await call(sb.from(isContact ? 'emergency_contacts' : 'shelters').insert(rows.slice(i, i + 500)))
      onDone(rows.length)
    } catch (e) { fail(e) } finally { setBusy(false) }
  }

  return (
    <Drawer title={`Impor ${label} dari CSV`} sub="Gunakan data dari sumber resmi (BPBD, dinas kesehatan, pemda). Baris yang bermasalah dilewati." onClose={onClose}
      footer={<><button className="btn soft big" style={{ flex: 1 }} onClick={onClose}>Batal</button>
        <button className="btn blue big" style={{ flex: 1.6 }} disabled={busy || !res?.rows.length} onClick={run}>{busy ? 'Mengimpor…' : `Impor ${res?.rows.length || 0} baris`}</button></>}>
      <div className="panel col" style={{ gap: 6 }}>
        <span className="lbl">Kolom</span>
        <span className="mono" style={{ fontSize: 12 }}>{cols.join(', ')}</span>
        <span className="sub" style={{ lineHeight: 1.5 }}>{isContact
          ? 'kategori: ' + Object.keys(CONTACT_CATEGORIES).join(', ') + '. kode_wilayah = kode provinsi atau kab/kota Kemendagri (mis. 35 Jawa Timur, 35.78 Kota Surabaya); kosongkan untuk nomor nasional. Nomor yang sudah ada di wilayah yang sama dilewati.'
          : 'lat/lng desimal (mis. -7.2575, 112.7521). status: open, full, atau closed (kosong = open).'}</span>
        <button className="link" style={{ alignSelf: 'flex-start' }} onClick={template}><Icon n="download" size={18} />Unduh templat</button>
      </div>
      <Field label="File CSV"><input className="input" type="file" accept=".csv,text/csv" onChange={e => e.target.files[0] && read(e.target.files[0])} /></Field>
      {res && <div className="col" style={{ gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>{res.rows.length} baris siap diimpor{res.skipped ? ` · ${res.skipped} sudah ada, dilewati` : ''}{res.errors.length ? ` · ${res.errors.length} bermasalah` : ''}</span>
        {res.errors.slice(0, 20).map(e => <span key={e.line} className="err">Baris {e.line}: {e.msg}</span>)}
        {res.errors.length > 20 && <span className="sub">…dan {res.errors.length - 20} lainnya</span>}
      </div>}
    </Drawer>
  )
}

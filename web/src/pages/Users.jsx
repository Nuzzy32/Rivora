import { useState } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, ini, ROLES, DEPTHS, dayMon, hm, reportCode } from '../lib'
import { Icon, Seg, LoadError, Spinner, Empty, Drawer, RegionPicker } from '../ui'

export default function Users() {
  const [tab, setTab] = useState('users')
  const [q, setQ] = useState('')
  return (
    <div className="card col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 10 }}>
        <Seg value={tab} onChange={setTab} items={[{ key: 'users', label: 'Pengguna', icon: 'group' }, { key: 'settings', label: 'Ambang & batas', icon: 'tune' }, { key: 'log', label: 'Log aktivitas', icon: 'history' }]} />
        <div style={{ flex: 1 }} />
        {tab === 'users' && (
          <div className="search"><Icon n="search" style={{ color: '#6B7286' }} />
            <input value={q} onChange={e => setQ(e.target.value)} placeholder="Cari nama atau email" aria-label="Cari nama atau email" /></div>
        )}
      </div>
      {tab === 'users' ? <UserList q={q} /> : tab === 'settings' ? <Settings /> : <Log />}
    </div>
  )
}

function UserList({ q }) {
  const { me, ask, toast, fail } = useApp()
  const [areasOf, setAreasOf] = useState(null)
  // Nama wilayah tugas diambil sekali untuk semua pengguna.
  const users = useLoad(async () => {
    const us = await call(sb.rpc('admin_users'))
    const codes = [...new Set(us.flatMap(u => u.regions || []))]
    const names = codes.length ? Object.fromEntries((await call(sb.from('regions').select('code, name').in('code', codes))).map(r => [r.code, r.name])) : {}
    return us.map(u => ({ ...u, areas: (u.regions || []).map(code => ({ code, name: names[code] ?? code })) }))
  })
  const s = q.trim().toLowerCase()
  const rows = (users.data || []).filter(u => !s || (u.name + ' ' + u.email).toLowerCase().includes(s))
  const patch = async (u, x) => {
    const r = await call(sb.from('profiles').update(x).eq('id', u.id).select('id'))
    if (!r.length) throw new Error('Perubahan tidak tersimpan. Pastikan akunmu masih Admin.')
    users.reload()
  }

  if (users.error) return <LoadError error={users.error} retry={users.reload} />
  if (!users.data) return <Spinner />
  return <>
    <div className="thead us-grid"><span>PENGGUNA</span><span>PERAN</span><span>LAPORAN</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AKSI</span></div>
    {rows.map(u => {
      const isMe = u.id === me.id
      return (
        <div key={u.id} className="tr us-grid" style={{ opacity: u.is_blocked ? 0.7 : 1 }}>
          <div className="row" style={{ gap: 10, minWidth: 0 }}>
            <div className="av sm" style={{ background: u.role === 'admin' ? '#806EF8' : u.role === 'verifikator' ? '#5896FD' : '#9AA1B4' }}>{ini(u.name)}</div>
            <div className="col" style={{ minWidth: 0 }}>
              <span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{u.name}</span>
              <span className="sub ell">{u.email} · sejak {new Date(u.created_at).toLocaleDateString('id-ID', { month: 'short', year: 'numeric' })}</span>
              {u.role === 'verifikator' && (
                <span className="sub ell" style={{ color: u.areas.length ? '#2462D0' : '#6E4E00' }}>
                  {u.areas.length ? 'Wilayah: ' + u.areas.map(a => a.name).join(', ') : 'Belum ada wilayah tugas'}
                </span>
              )}
            </div>
          </div>
          <select className="input" style={{ height: 40, maxWidth: 160 }} value={u.role} disabled={isMe} aria-label={'Peran ' + u.name}
            onChange={e => {
              const r = e.target.value
              ask({
                title: `Ubah peran ${u.name} jadi ${ROLES[r]}?`, icon: 'manage_accounts', cta: 'Ubah peran',
                body: r === 'warga' ? 'Akses panel web dicabut saat akun ini memuat ulang panel.' : `Akun ini bisa masuk panel web dengan hak ${ROLES[r]}.`,
                onOk: async () => { await patch(u, { role: r }); toast(`Peran ${u.name} diubah jadi ${ROLES[r]}`) },
              })
            }}>
            {Object.entries(ROLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <span style={{ fontSize: 13, fontWeight: 600, color: '#3B4157' }}>{u.report_count}</span>
          <span className="pill" style={{ background: u.is_blocked ? '#FDE3E4' : '#E2F5EB', color: u.is_blocked ? '#9C161C' : '#0B6640' }}>{u.is_blocked ? 'Diblokir' : 'Aktif'}</span>
          <div className="row" style={{ justifyContent: 'flex-end', gap: 6 }}>
            {u.role === 'verifikator' && (
              <button className="btn sm white" style={{ color: '#2462D0' }} onClick={() => setAreasOf(u)}><Icon n="map" size={17} />Wilayah</button>
            )}
            {isMe ? <span className="sub">Akun kamu</span> : (
              <button className="btn sm white" style={{ color: u.is_blocked ? '#2462D0' : '#C4282E' }} onClick={() => ask(u.is_blocked
                ? { title: `Buka blokir ${u.name}?`, icon: 'lock_open', cta: 'Buka blokir', body: 'Akun bisa mengirim laporan lagi.',
                    onOk: async () => { await patch(u, { is_blocked: false }); toast(u.name + ' tidak diblokir lagi') } }
                : { title: `Blokir ${u.name}?`, icon: 'block', tone: 'danger', cta: 'Blokir akun',
                    body: 'Akun tidak bisa mengirim laporan atau masuk panel. Laporannya yang belum ditinjau otomatis ditolak dan hilang dari peta.',
                    onOk: async () => { await patch(u, { is_blocked: true }); toast(u.name + ' diblokir') } })}>
                <Icon n={u.is_blocked ? 'lock_open' : 'block'} size={17} />{u.is_blocked ? 'Buka blokir' : 'Blokir'}
              </button>
            )}
          </div>
        </div>
      )
    })}
    {!rows.length && <Empty icon="person_search" title="Tidak ada pengguna yang cocok" />}
    {areasOf && <AreasEditor u={areasOf} onClose={() => setAreasOf(null)} fail={fail}
      onSaved={() => { toast(`Wilayah tugas ${areasOf.name} disimpan`); setAreasOf(null); users.reload() }} />}
  </>
}

// Wilayah tugas verifikator (kab/kota). Verifikator hanya melihat & meninjau laporan di wilayah ini.
function AreasEditor({ u, onClose, onSaved, fail }) {
  const [areas, setAreas] = useState(u.areas)
  const [pick, setPick] = useState(null)
  const [busy, setBusy] = useState(false)
  const add = () => {
    if (pick?.code?.length === 5 && !areas.some(a => a.code === pick.code)) setAreas([...areas, pick])
    setPick(null)
  }
  const save = async () => {
    setBusy(true)
    try { await call(sb.rpc('set_staff_regions', { uid: u.id, regions: areas.map(a => a.code) })); onSaved() }
    catch (e) { fail(e) } finally { setBusy(false) }
  }
  return (
    <Drawer title={`Wilayah tugas · ${u.name}`} sub="Verifikator hanya melihat dan meninjau laporan di kab/kota ini. Tanpa wilayah = tidak ada laporan." onClose={onClose}
      footer={<><button className="btn soft big" style={{ flex: 1 }} onClick={onClose}>Batal</button>
        <button className="btn blue big" style={{ flex: 1.6 }} disabled={busy} onClick={save}>{busy ? 'Menyimpan…' : 'Simpan wilayah'}</button></>}>
      <div className="col" style={{ gap: 8 }}>
        {areas.map(a => (
          <div key={a.code} className="tr" style={{ gridTemplateColumns: '1fr auto' }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{a.name}</span>
            <button className="ibtn white" aria-label={'Hapus ' + a.name} onClick={() => setAreas(areas.filter(x => x.code !== a.code))}><Icon n="close" size={18} style={{ color: '#C4282E' }} /></button>
          </div>
        ))}
        {!areas.length && <span className="sub" style={{ fontSize: 12 }}>Belum ada wilayah tugas.</span>}
      </div>
      <div className="col" style={{ gap: 8 }}>
        <span className="lbl">Tambah kab/kota</span>
        <RegionPicker kabOnly value={pick} onChange={setPick} />
        <button className="btn soft" disabled={pick?.code?.length !== 5} onClick={add}><Icon n="add" />Tambahkan</button>
      </div>
    </Drawer>
  )
}

const NUMS = [
  ['stale_hours', 'Batas “Perlu Konfirmasi”', 'Titik tanpa pembaruan selama ini akan memudar di peta.', 'jam', 1, 1, 12],
  ['reports_per_hour', 'Batas laporan per akun', 'Jumlah maksimal laporan tiap jam untuk mencegah spam.', '/ jam', 1, 1, 20],
  ['merge_radius_m', 'Radius gabung & duplikat', 'Laporan baru dalam radius ini ditempelkan ke titik yang sama; kategori sama ditandai duplikat.', 'm', 50, 50, 500],
]

function Settings() {
  const { settings, reloadSettings, toast, fail } = useApp()
  const [draft, setDraft] = useState(null)
  const [busy, setBusy] = useState(false)
  if (!settings) return <Spinner />
  const d = draft || settings
  const set = x => setDraft({ ...d, ...x })
  const dirty = draft && NUMS.concat([['notify_min_depth'], ['notify_official'], ['notify_verified']]).some(([k]) => draft[k] !== settings[k])
  const save = async () => {
    setBusy(true)
    try {
      const { notify_min_depth, notify_official, notify_verified, stale_hours, reports_per_hour, merge_radius_m } = d
      await call(sb.from('app_settings').update({ notify_min_depth, notify_official, notify_verified, stale_hours, reports_per_hour, merge_radius_m }).eq('id', true))
      reloadSettings(); setDraft(null)
      toast('Pengaturan disimpan · berlaku untuk laporan berikutnya')
    } catch (e) { fail(e) } finally { setBusy(false) }
  }
  const toggle = ({ k, label, icon, color, locked }) => {
    const on = !locked && d[k]
    return (
      <div key={k} className="row" style={{ gap: 12, height: 44, opacity: locked ? 0.55 : 1 }}>
        <Icon n={icon} fill style={{ color }} /><span style={{ flex: 1, fontSize: 13, fontWeight: 500 }}>{label}</span>
        <button className={'switch' + (on ? ' on' : '')} role="switch" aria-checked={on} aria-label={label} disabled={locked} onClick={() => set({ [k]: !d[k] })}><span /></button>
      </div>
    )
  }
  return <>
    <div className="grid2" style={{ gap: 16 }}>
      <div className="panel col">
        <div className="col" style={{ gap: 2 }}><span className="h3">Ambang notifikasi</span><span className="sub" style={{ fontSize: 12, lineHeight: 1.5 }}>Kategori minimum yang memicu notifikasi ke pemantau di sekitar.</span></div>
        <div className="grid2" style={{ gap: 8 }}>
          {DEPTHS.slice(1).map(o => (
            <button key={o.key} className="opt" aria-pressed={d.notify_min_depth === o.key} style={d.notify_min_depth === o.key ? { background: o.tint, borderColor: o.color } : undefined} onClick={() => set({ notify_min_depth: o.key })}>
              <span className="dot" style={{ background: o.color }} />{o.label}{o.key !== 'chest' && ' ke atas'}
            </button>
          ))}
        </div>
      </div>
      <div className="panel col">
        <div className="col" style={{ gap: 2 }}><span className="h3">Sumber yang memicu notifikasi</span><span className="sub" style={{ fontSize: 12, lineHeight: 1.5 }}>Laporan Belum Terverifikasi tidak pernah memicu notifikasi, supaya tidak ada alarm palsu.</span></div>
        {toggle({ k: 'notify_official', label: 'Resmi', icon: 'shield', color: '#5B47E0' })}
        {toggle({ k: 'notify_verified', label: 'Terverifikasi', icon: 'check_circle', color: '#2462D0' })}
        {toggle({ k: 'x', label: 'Belum Terverifikasi (dikunci)', icon: 'help', color: '#4A5068', locked: true })}
      </div>
      {NUMS.map(([k, label, desc, unit, step, min, max]) => (
        <div key={k} className="panel row" style={{ gap: 14 }}>
          <div className="col" style={{ flex: 1, gap: 2 }}><span className="h3">{label}</span><span className="sub" style={{ fontSize: 12, lineHeight: 1.5 }}>{desc}</span></div>
          <div className="row" style={{ gap: 6 }}>
            <button className="ibtn white" aria-label={'Kurangi ' + label} disabled={d[k] <= min} onClick={() => set({ [k]: Math.max(min, d[k] - step) })}><Icon n="remove" size={18} /></button>
            <span style={{ minWidth: 76, textAlign: 'center', fontSize: 15, fontWeight: 700 }}>{d[k]} {unit}</span>
            <button className="ibtn white" aria-label={'Tambah ' + label} disabled={d[k] >= max} onClick={() => set({ [k]: Math.min(max, d[k] + step) })}><Icon n="add" size={18} /></button>
          </div>
        </div>
      ))}
    </div>
    <div className="row" style={{ justifyContent: 'flex-end', gap: 10 }}>
      {dirty && <span style={{ fontSize: 12, color: '#6E4E00' }}>Ada perubahan belum disimpan</span>}
      <button className="btn soft" disabled={!dirty} onClick={() => setDraft(null)}>Batalkan</button>
      <button className="btn blue" disabled={!dirty || busy} onClick={save}>{busy ? 'Menyimpan…' : 'Simpan pengaturan'}</button>
    </div>
  </>
}

const ACT = {
  approve: ['menyetujui laporan', 'check_circle'], reject: ['menolak laporan', 'cancel'],
  mark_receded: ['menandai sudah surut', 'water'], reopen: ['membuka lagi status', 'undo'], publish_official: ['menerbitkan status Resmi', 'shield'],
  insert: ['menambah', 'add_circle'], update: ['mengubah', 'edit'], delete: ['menghapus', 'delete'],
  set_role: ['mengubah peran', 'manage_accounts'], block: ['memblokir akun', 'block'], unblock: ['membuka blokir', 'lock_open'],
  update_settings: ['mengubah ambang & batas', 'tune'],
  set_regions: ['mengatur wilayah tugas', 'map'],
}
const KIND = { shelters: 'posko/faskes', emergency_contacts: 'kontak darurat' }

function Log() {
  const log = useLoad(async () => {
    const rows = await call(sb.from('audit_logs').select('*').order('created_at', { ascending: false }).limit(100))
    const ids = [...new Set(rows.map(r => r.actor_id).filter(Boolean))]
    const names = ids.length ? await call(sb.from('profiles').select('id, name').in('id', ids)) : []
    return rows.map(r => ({ ...r, who: names.find(n => n.id === r.actor_id)?.name || 'Sistem' }))
  })
  if (log.error) return <LoadError error={log.error} retry={log.reload} />
  if (!log.data) return <Spinner />
  if (!log.data.length) return <Empty icon="history" title="Belum ada aktivitas" />
  return log.data.map(l => {
    const [verb, icon] = ACT[l.action] || [l.action, 'history']
    const what = [verb, KIND[l.target_type], l.target_type === 'report' && reportCode(l.target_id)].filter(Boolean).join(' ')
    return (
      <div key={l.id} className="row logrow">
        <div className="sic sm" style={{ background: '#fff', color: '#5B47E0' }}><Icon n={icon} size={19} /></div>
        <span style={{ flex: 1, fontSize: 13, lineHeight: 1.5 }}><b style={{ fontWeight: 600 }}>{l.who}</b> {what}{l.detail && <span className="muted"> ({l.detail})</span>}</span>
        <span className="mono sub" style={{ fontSize: 12 }}>{dayMon(l.created_at)} · {hm(l.created_at)}</span>
      </div>
    )
  })
}

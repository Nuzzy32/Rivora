import { createContext, useContext, useEffect, useState } from 'react'
import { sb, call, useLoad, errMsg, ini, ROLES, rainSummary, hm } from './lib'
import { Icon, Modal } from './ui'
import Dashboard from './pages/Dashboard'
import Queue from './pages/Queue'
import Status from './pages/Status'
import Places from './pages/Places'
import Users from './pages/Users'

const PAGES = {
  dashboard: ['Dasbor', 'Ringkasan kondisi dan antrean saat ini', 'space_dashboard', false, Dashboard],
  queue: ['Antrean Verifikasi', 'Laporan warga terbaru di atas. Setujui atau tolak dengan alasan.', 'fact_check', false, Queue],
  status: ['Status Lokasi', 'Tandai surut atau tambah status Resmi dari kanal Pemkot / BPBD', 'water', false, Status],
  places: ['Posko, Faskes & Kontak', 'Data yang tampil di lapisan peta dan halaman Darurat', 'night_shelter', true, Places],
  users: ['Pengguna & Pengaturan', 'Peran, blokir akun, ambang notifikasi, dan log aktivitas', 'manage_accounts', true, Users],
}

const Ctx = createContext(null)
export const useApp = () => useContext(Ctx)

export default function App() {
  const [session, setSession] = useState(undefined)
  const [me, setMe] = useState(null)
  const [loginErr, setLoginErr] = useState(null)

  useEffect(() => {
    sb.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = sb.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  // Peran dibaca dari tabel profiles (sama seperti RLS), bukan dari metadata token.
  const uid = session?.user.id
  useEffect(() => {
    if (!uid) { setMe(null); return }
    sb.from('profiles').select('id, name, role, is_blocked').eq('id', uid).single().then(({ data, error }) => {
      const why = error ? errMsg(error)
        : data.is_blocked ? 'Akun ini diblokir. Hubungi Admin.'
        : data.role === 'warga' ? 'Akun ini tidak punya akses panel. Warga memakai aplikasi mobile.' : null
      if (why) { setLoginErr(why); sb.auth.signOut() } else setMe({ ...data, email: session.user.email })
    })
  }, [uid]) // eslint-disable-line react-hooks/exhaustive-deps

  if (session === undefined || (session && !me)) return <div className="boot"><span className="spin" /></div>
  if (!session) return <Login err={loginErr} setErr={setLoginErr} />
  return <Shell me={me} />
}

function Login({ err, setErr }) {
  const [email, setEmail] = useState('')
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async e => {
    e.preventDefault()
    if (!/^\S+@\S+\.\S+$/.test(email) || pw.length < 8) return setErr('Email atau kata sandi belum benar. Kata sandi minimal 8 karakter.')
    setBusy(true); setErr(null)
    const { error } = await sb.auth.signInWithPassword({ email: email.trim(), password: pw })
    setBusy(false)
    if (error) setErr(/invalid/i.test(error.message) ? 'Email atau kata sandi salah.'
      : /confirm/i.test(error.message) ? 'Email belum dikonfirmasi. Cek kotak masuk.' : errMsg(error))
  }
  return (
    <div className="login">
      <div className="hero">
        <div className="row" style={{ gap: 12 }}>
          <div className="logo big"><Icon n="water_drop" fill size={24} /></div>
          <span style={{ fontSize: 20, fontWeight: 700 }}>SIGAP Banjir</span>
          <span className="tag">Panel</span>
        </div>
        <div className="col" style={{ gap: 16, maxWidth: 480 }}>
          <span style={{ fontSize: 40, lineHeight: 1.15, fontWeight: 700, letterSpacing: -0.6 }}>Label “Terverifikasi” lahir di sini.</span>
          <span style={{ fontSize: 16, lineHeight: 1.6 }}>Tinjau laporan warga, tandai lokasi yang sudah surut, dan kelola data posko serta kontak darurat untuk warga Surabaya.</span>
        </div>
        <div className="row" style={{ gap: 12, flexWrap: 'wrap' }}>
          <div className="glass"><Icon n="fact_check" />Verifikator: tinjau laporan</div>
          <div className="glass"><Icon n="admin_panel_settings" />Admin: kelola data &amp; pengguna</div>
        </div>
      </div>
      <form className="col" onSubmit={submit} style={{ alignSelf: 'center', justifySelf: 'center', width: '100%', maxWidth: 400, gap: 20, padding: 40 }}>
        <div className="col" style={{ gap: 6 }}>
          <span style={{ fontSize: 28, fontWeight: 700 }}>Masuk ke panel</span>
          <span className="muted" style={{ fontSize: 14, lineHeight: 1.55 }}>Khusus akun Verifikator dan Admin. Warga memakai aplikasi mobile.</span>
        </div>
        {err && <div className="banner red" role="alert"><Icon n="error" />{err}</div>}
        <label className="col" style={{ gap: 6 }}><span className="lbl">Email</span>
          <input className="input tall" type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} placeholder="nama@surabaya.go.id" /></label>
        <label className="col" style={{ gap: 6 }}><span className="lbl">Kata sandi</span>
          <input className="input tall" type="password" autoComplete="current-password" value={pw} onChange={e => setPw(e.target.value)} placeholder="Minimal 8 karakter" /></label>
        <button className="btn blue big" disabled={busy}>{busy ? 'Memeriksa…' : 'Masuk'}</button>
      </form>
    </div>
  )
}

function Shell({ me }) {
  const admin = me.role === 'admin'
  const [page, setPage] = useState(() => (PAGES[location.hash.slice(2)] ? location.hash.slice(2) : 'dashboard'))
  const [toast, setToast] = useState(null)
  const [confirm, setConfirm] = useState(null)
  const [now, setNow] = useState(Date.now())

  useEffect(() => {
    const h = () => PAGES[location.hash.slice(2)] && setPage(location.hash.slice(2))
    addEventListener('hashchange', h)
    const t = setInterval(() => setNow(Date.now()), 30000)
    return () => { removeEventListener('hashchange', h); clearInterval(t) }
  }, [])
  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(null), 3200)
    return () => clearTimeout(t)
  }, [toast])

  const pending = useLoad(() => sb.from('reports').select('id', { count: 'exact', head: true }).eq('status', 'pending').then(r => r.count), [], 30000)
  const settings = useLoad(() => call(sb.from('app_settings').select('*').single()))
  const forecast = useLoad(() => call(sb.from('forecast_cache').select('district, forecast_json, fetched_at')).then(rainSummary), [], 15 * 60000)

  const app = {
    me, admin, settings: settings.data, reloadSettings: settings.reload, forecast: forecast.data,
    pending: pending.data, reloadPending: pending.reload,
    go: p => { location.hash = '/' + p },
    toast: (msg, tone) => setToast({ msg, tone }),
    fail: e => setToast({ msg: errMsg(e), tone: 'error' }),
    ask: setConfirm,
  }
  const [title, sub, , adminOnly, Page] = PAGES[page]
  const locked = adminOnly && !admin
  const fc = forecast.data

  return (
    <Ctx.Provider value={app}>
      <div className="shell">
        <aside>
          <nav className="side" aria-label="Menu">
            <div className="row" style={{ gap: 10, padding: '0 8px 18px' }}>
              <div className="logo"><Icon n="water_drop" fill size={21} /></div>
              <div className="col"><span style={{ fontSize: 16, fontWeight: 700, lineHeight: 1.2 }}>SIGAP Banjir</span><span className="sub">Panel web</span></div>
            </div>
            {Object.entries(PAGES).map(([k, p]) => {
              const on = k === page, lk = p[3] && !admin
              return (
                <a key={k} href={'#/' + k} className={'nav' + (on ? ' on' : '') + (lk ? ' lk' : '')} aria-current={on ? 'page' : undefined}>
                  <Icon n={p[2]} size={21} /><span style={{ flex: 1 }}>{p[0]}</span>
                  {k === 'queue' && pending.data > 0 && <span className="badge">{pending.data}</span>}
                  {lk && <Icon n="lock" size={17} style={{ color: '#9AA1B4' }} />}
                </a>
              )
            })}
            <div style={{ flex: 1 }} />
            <div className="row card-me">
              <div className="av">{ini(me.name)}</div>
              <div className="col" style={{ flex: 1, minWidth: 0 }}>
                <span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{me.name}</span>
                <span className="sub">{ROLES[me.role]}</span>
              </div>
              <button className="ibtn white" title="Keluar" aria-label="Keluar" onClick={() => sb.auth.signOut()}><Icon n="logout" size={18} /></button>
            </div>
          </nav>
        </aside>
        <main>
          <header className="row" style={{ gap: 16, minHeight: 60 }}>
            <div className="col" style={{ flex: 1, gap: 2 }}>
              <h1>{title}</h1>
              <span className="sub" style={{ fontSize: 13 }}>{locked ? 'Akses terbatas' : sub}</span>
            </div>
            {fc && (
              <div className="chip" title={fc.warning || undefined}>
                <Icon n={fc.rain ? 'thunderstorm' : 'partly_cloudy_day'} fill size={20} style={{ color: '#806EF8' }} />
                {fc.rain ? `BMKG: ${fc.desc.toLowerCase()} ${hm(fc.from)}–${hm(fc.to)}` : 'BMKG: tidak ada hujan 12 jam ke depan'}
              </div>
            )}
            <div className="chip" style={{ fontWeight: 500, color: '#3B4157' }}>
              <Icon n="schedule" size={18} style={{ color: '#6B7286' }} />
              {new Date(now).toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Jakarta' })} · {hm(now)} WIB
            </div>
          </header>
          {locked ? (
            <div className="card col locked">
              <div className="lockic"><Icon n="lock" size={34} /></div>
              <span style={{ fontSize: 20, fontWeight: 700 }}>Halaman ini khusus Admin</span>
              <span className="muted" style={{ fontSize: 14, lineHeight: 1.55, maxWidth: 420 }}>Akun Verifikator bisa meninjau laporan dan mengubah status lokasi. Minta Admin untuk mengubah data posko, kontak, atau pengguna.</span>
            </div>
          ) : <Page key={page} />}
        </main>
      </div>
      {confirm && <Modal cfg={confirm} onClose={() => setConfirm(null)} onError={app.fail} />}
      {toast && (
        <div className="toast" role="status">
          <Icon n={toast.tone === 'error' ? 'error' : 'check_circle'} style={{ color: toast.tone === 'error' ? '#F2777B' : '#AECDFF' }} />{toast.msg}
        </div>
      )}
    </Ctx.Provider>
  )
}

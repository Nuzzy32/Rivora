import { useState } from 'react'
import { useApp } from '../App'
import { sb, call, useLoad, ago, depthOf, depthIdx, DEPTHS, REASONS, VER, reportCode, minsSince } from '../lib'
import { Icon, Seg, MapView, DepthFig, Empty, LoadError, Spinner } from '../ui'

const TABS = [['pending', 'Menunggu'], ['approved', 'Disetujui'], ['rejected', 'Ditolak']]
const ST = { pending: ['Menunggu', 'schedule', '#EEF0F4', '#3B4157'], approved: ['Disetujui', 'check_circle', '#E6EFFF', '#2462D0'], rejected: ['Ditolak', 'cancel', '#FDE3E4', '#9C161C'] }

export default function Queue() {
  const { settings, toast, fail, reloadPending } = useApp()
  const [tab, setTab] = useState('pending')
  const [selId, setSelId] = useState(null)
  const list = useLoad(() => call(sb.rpc('review_queue', { st: tab })), [tab], tab === 'pending' ? 30000 : 0)
  const counts = useLoad(() => Promise.all(TABS.map(([s]) =>
    sb.from('reports').select('id', { count: 'exact', head: true }).eq('status', s).then(r => r.count ?? 0))), [tab], 30000)

  const rows = list.data || []
  const sel = rows.find(r => r.id === selId) || rows[0]
  const staleH = settings?.stale_hours ?? 3

  const done = async (fn, id, msg) => {
    try {
      await fn()
      toast(msg)
      setSelId(rows.find(r => r.id !== id)?.id ?? null) // lanjut ke laporan berikutnya
    } catch (e) { fail(e) }
    list.reload(); counts.reload(); reloadPending()
  }

  return (
    <div className="queue">
      <div className="card col qlist">
        <Seg grow value={tab} onChange={t => { setTab(t); setSelId(null) }}
          items={TABS.map(([k, l], i) => ({ key: k, label: counts.data ? `${l} · ${counts.data[i]}` : l }))} />
        <div className="col scroll" style={{ gap: 6 }}>
          {list.error && <LoadError error={list.error} retry={list.reload} />}
          {!list.data ? <Spinner /> : !rows.length ? <Empty title="Antrean kosong" sub={tab === 'pending' ? 'Semua laporan sudah ditinjau.' : 'Belum ada laporan di sini.'} /> :
            rows.map(r => {
              const d = depthOf(r.depth), on = sel?.id === r.id
              return (
                <button key={r.id} className={'qi' + (on ? ' on' : '')} onClick={() => setSelId(r.id)} aria-current={on || undefined}>
                  <div className="thumb"><span>{r.photo_paths.length} foto</span></div>
                  <div className="col" style={{ flex: 1, minWidth: 0, gap: 3 }}>
                    <div className="row between" style={{ gap: 6 }}><span className="ell" style={{ fontSize: 13, fontWeight: 600 }}>{placeOf(r)}</span><span className="sub" style={{ flex: 'none' }}>{ago(r.created_at)}</span></div>
                    <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
                      <span className="tagx" style={{ background: d.tint, color: d.ink }}>{d.short}</span>
                      {r.dup_id && <span className="tagx" style={{ background: '#EEEBFF', color: '#5B47E0' }}>Kemungkinan duplikat</span>}
                      {r.status === 'pending' && minsSince(r.created_at) > staleH * 60 && <span className="tagx" style={{ background: '#FFF3D3', color: '#6E4E00' }}>&gt; {staleH} jam</span>}
                    </div>
                    <span className="sub">{reportCode(r.id)} · {r.reporter} · {repShort(r)}</span>
                  </div>
                </button>
              )
            })}
        </div>
      </div>
      {sel && <Detail key={sel.id} r={sel} staleH={staleH} done={done} />}
    </div>
  )
}

const placeOf = r => r.place_name || r.point_name || 'Tanpa nama lokasi'
const repShort = r => (r.prior_total ? `${r.prior_approved}/${r.prior_total} disetujui` : 'Pelapor baru')

function Detail({ r, staleH, done }) {
  const { settings } = useApp()
  const [fix, setFix] = useState(r.depth)
  const [rejecting, setRejecting] = useState(false)
  const [reason, setReason] = useState(null)
  const [other, setOther] = useState('')
  const [busy, setBusy] = useState(false)
  const photos = useLoad(() => call(sb.storage.from('report-photos').createSignedUrls(r.photo_paths, 3600)), [r.id])

  const d = depthOf(fix), st = ST[r.status], pending = r.status === 'pending'
  const ratio = r.prior_total ? r.prior_approved / r.prior_total : null
  const reasonOk = reason && (reason !== 'lainnya' || other.trim().length > 2)
  const minDepth = settings?.notify_min_depth || 'knee'
  const act = async (fn, msg) => { setBusy(true); await done(fn, r.id, msg); setBusy(false) }

  const approve = () => act(() => call(sb.rpc('review_report', { report_id: r.id, approve: true, corrected_depth: fix !== r.depth ? fix : null })),
    reportCode(r.id) + ' disetujui' + (depthIdx(fix) >= depthIdx(minDepth) && settings?.notify_verified ? ' · pemantau sekitar dikabari' : ''))
  const reject = () => reasonOk && act(() => call(sb.rpc('review_report', { report_id: r.id, approve: false, reason, note: reason === 'lainnya' ? other.trim() : null })),
    reportCode(r.id) + ' ditolak')

  return (
    <div className="card col" style={{ padding: 24, gap: 18 }}>
      <div className="row between" style={{ alignItems: 'flex-start', gap: 16 }}>
        <div className="col" style={{ gap: 4 }}>
          <span className="mono sub" style={{ fontSize: 12 }}>{reportCode(r.id)} · masuk {ago(r.created_at)}</span>
          <span style={{ fontSize: 22, fontWeight: 700 }}>{placeOf(r)}</span>
          <span className="muted" style={{ fontSize: 13 }}>{r.district ? 'Kec. ' + r.district + ' · ' : ''}{r.lat.toFixed(4)}, {r.lng.toFixed(4)}</span>
        </div>
        <span className="pill lg" style={{ background: st[2], color: st[3] }}><Icon n={st[1]} size={16} />{st[0]}</span>
      </div>

      {r.dup_id && (
        <div className="banner violet"><Icon n="content_copy" size={22} />
          <span>Kemungkinan duplikat dari <b>{reportCode(r.dup_id)}</b>: berjarak {r.dup_distance_m} m, kategori sama. Laporan dalam radius ini sudah ditempelkan ke titik yang sama; tolak sebagai Duplikat kalau isinya sama.</span>
        </div>
      )}
      {pending && minsSince(r.created_at) > staleH * 60 && (
        <div className="banner amber"><Icon n="schedule" />Belum ditinjau lebih dari {staleH} jam. Di aplikasi, laporan ini masih berlabel “Belum Terverifikasi”.</div>
      )}

      <div className="grid3" style={{ gap: 10 }}>
        {[0, 1, 2].map(i => {
          const p = photos.data?.[i]
          return p?.signedUrl
            ? <a key={i} className="photo" href={p.signedUrl} target="_blank" rel="noreferrer" title="Buka foto ukuran penuh"><img src={p.signedUrl} alt={`Foto ${i + 1} laporan ${reportCode(r.id)}`} /></a>
            : <div key={i} className={'photo ph' + (i < r.photo_paths.length ? ' st' : '')}>{i < r.photo_paths.length ? (photos.error ? 'foto gagal dimuat' : 'memuat…') : 'tidak ada'}</div>
        })}
      </div>

      <div className="grid2">
        <div className="col" style={{ gap: 6 }}>
          <MapView height={240} center={[r.lat, r.lng, 16]} pick={r} circle={{ lat: r.lat, lng: r.lng, r: settings?.merge_radius_m || 100 }} />
          <span className="sub">Radius duplikat {settings?.merge_radius_m || 100} m</span>
        </div>
        <div className="col" style={{ gap: 14 }}>
          <div className="row" style={{ gap: 14, padding: 12, borderRadius: 20, background: d.tint }}>
            <DepthFig level={fix} size={60} />
            <div className="col" style={{ gap: 2 }}>
              <span style={{ fontSize: 11, fontWeight: 600, color: d.ink }}>Kategori dari pelapor</span>
              <span style={{ fontSize: 20, fontWeight: 700, color: d.ink }}>{d.label}</span>
              <span style={{ fontSize: 12, color: '#3B4157' }}>{fix !== r.depth ? 'Dikoreksi dari ' + depthOf(r.depth).label : pending ? 'Sesuai foto? Koreksi jika perlu.' : ''}</span>
            </div>
          </div>
          {pending && (
            <div className="col" style={{ gap: 6 }}>
              <span style={{ fontSize: 12, fontWeight: 600, color: '#3B4157' }}>Koreksi kategori (opsional)</span>
              <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
                {DEPTHS.slice(1).map(o => (
                  <button key={o.key} className="opt sm" aria-pressed={fix === o.key} style={fix === o.key ? { background: o.tint, borderColor: o.color } : undefined} onClick={() => setFix(o.key)}>
                    <span className="dot" style={{ background: o.color, width: 8, height: 8 }} />{o.short}
                  </button>
                ))}
              </div>
            </div>
          )}
          <div className="row" style={{ gap: 12 }}>
            <div className="sic" style={{ background: '#F4F7FD', color: '#565D73' }}><Icon n="person" size={21} /></div>
            <div className="col">
              <span style={{ fontSize: 13, fontWeight: 600 }}>{r.reporter} (nama disamarkan)</span>
              <span style={{ fontSize: 12, color: ratio === null ? '#6E4E00' : ratio >= 0.8 ? '#0B6640' : '#9C161C' }}>
                {ratio === null ? 'Pelapor baru, belum ada riwayat' : `${r.prior_approved} dari ${r.prior_total} laporan sebelumnya disetujui`}
              </span>
            </div>
          </div>
          {r.note && <div className="quote">“{r.note}”</div>}
        </div>
      </div>

      {pending && !rejecting && (
        <div className="row" style={{ gap: 12, borderTop: '1px solid #EDF1F9', paddingTop: 18 }}>
          <button className="btn blue big" style={{ flex: 1 }} disabled={busy} onClick={approve}><Icon n="check_circle" size={22} />Setujui · jadi {VER.verified.label}</button>
          <button className="btn redline big" style={{ width: 200 }} disabled={busy} onClick={() => setRejecting(true)}><Icon n="cancel" size={22} />Tolak</button>
        </div>
      )}
      {pending && rejecting && (
        <div className="col rejectbox">
          <span style={{ fontSize: 14, fontWeight: 600 }}>Alasan penolakan <span style={{ color: '#C4282E' }}>*</span></span>
          <div className="grid2" style={{ gap: 8 }} role="radiogroup">
            {REASONS.map(o => (
              <button key={o.key} role="radio" aria-checked={reason === o.key} className="opt" style={reason === o.key ? { borderColor: '#E5484D' } : undefined} onClick={() => setReason(o.key)}>
                <Icon n={reason === o.key ? 'radio_button_checked' : o.icon} style={{ color: reason === o.key ? '#C4282E' : '#6B7286' }} />{o.label}
              </button>
            ))}
          </div>
          {reason === 'lainnya' && <input className="input" autoFocus maxLength={120} value={other} onChange={e => setOther(e.target.value)} placeholder="Tulis alasan singkat" />}
          <span className="sub" style={{ fontSize: 12 }}>Laporan yang ditolak tidak lagi menghidupkan titik di peta. Pelapor melihat alasan ini di Riwayat Laporanku.</span>
          <div className="row" style={{ gap: 10, justifyContent: 'flex-end' }}>
            <button className="btn soft" onClick={() => setRejecting(false)}>Batal</button>
            <button className="btn red" disabled={!reasonOk || busy} onClick={reject}>Tolak laporan</button>
          </div>
        </div>
      )}
      {!pending && (
        <div className="banner" style={{ background: st[2], color: st[3] }}><Icon n={st[1]} />
          {r.status === 'approved'
            ? `Disetujui oleh ${r.reviewer || 'staf'} · ${ago(r.reviewed_at)}. Label di aplikasi: Terverifikasi.`
            : `Ditolak oleh ${r.reviewer || 'staf'} · ${ago(r.reviewed_at)} · Alasan: ${r.reject_note || REASONS.find(x => x.key === r.reject_reason)?.label}`}
        </div>
      )}
    </div>
  )
}

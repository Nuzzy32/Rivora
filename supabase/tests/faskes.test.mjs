// Uji migrasi *_faskes_osm.sql di PGlite: semua migrasi diterapkan berurutan, seed (faskes input Admin)
// dimuat SEBELUM migrasi faskes supaya aturan "data Admin menang dalam 150 m" ikut teruji.
// Pakai: node faskes_test.mjs [/path/to/supabase]
import { PGlite } from '@electric-sql/pglite'
import { postgis } from '@electric-sql/pglite-postgis'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm'
import fs from 'node:fs'
import path from 'node:path'

const ROOT = process.argv[2] ?? path.resolve(import.meta.dirname, '..')
const db = await PGlite.create({ extensions: { postgis, pgcrypto, pg_trgm } })

const stubs = fs.readFileSync(new URL('./regions.test.mjs', import.meta.url), 'utf8')
await db.exec(stubs.slice(stubs.indexOf('await db.exec(`') + 15, stubs.indexOf('`)', stubs.indexOf('await db.exec(`'))))
await db.exec(`set search_path = "$user", public, extensions`)

// Seperti supabase db push: schema extensions tidak ada di search_path saat migrasi dijalankan.
const strict = sql => 'set search_path = "$user", public;\n' + sql + '\n;set search_path = "$user", public, extensions;'
const STRIP = /^\s*create extension if not exists (pg_cron|pg_net)\b[^;]*;/gim
const migs = fs.readdirSync(path.join(ROOT, 'migrations')).filter(f => f.endsWith('.sql')).sort()
const faskesFile = migs.find(f => f.endsWith('_faskes_osm.sql'))
const apply = async f => {
  const t0 = Date.now()
  try { await db.exec(strict(fs.readFileSync(f, 'utf8').replace(STRIP, '-- stripped'))) }
  catch (e) { console.log('FAILED', path.basename(f), e.message, e.where || ''); process.exit(1) }
  console.log('APPLIED', path.basename(f), (Date.now() - t0) + ' ms')
}
for (const f of migs) {
  if (f === faskesFile) await apply(path.join(ROOT, 'seed.sql')) // data Admin sudah ada saat impor
  await apply(path.join(ROOT, 'migrations', f))
}

let pass = 0, fail = 0
const check = (name, ok, got) => { ok ? pass++ : fail++; console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok ? '' : '  -> ' + JSON.stringify(got)}`) }
const all = async (s, p) => (await db.query(s, p)).rows
const one = async (s, p) => (await all(s, p))[0]

const sql = fs.readFileSync(path.join(ROOT, 'migrations', faskesFile), 'utf8')
const expected = (sql.match(/^\('(node|way|relation)\//gm) || []).length
const st = await one(`select count(*)::int n, count(adm4)::int adm4, count(*) filter (where address = '')::int no_addr,
  count(phone)::int phone, count(*) filter (where name ~* 'puskesmas')::int pkm
  from public.shelters where source = 'OpenStreetMap'`)
const manual = await one(`select count(*)::int n from public.shelters where osm_ref is null`)
console.log({ expected_in_file: expected, ...st, manual: manual.n })
check('ada faskes OSM terimpor', st.n > 1000, st)
check('selisih file vs tabel = yang dilewati karena dekat data Admin (< 20)', expected - st.n >= 0 && expected - st.n < 20, { expected, n: st.n })
check('data Admin (seed) tetap utuh', manual.n === 3, manual)
const near = await all(`select o.name, o.osm_ref, m.name manual, round(extensions.st_distance(o.location, m.location)) m
  from public.shelters o join public.shelters m on m.osm_ref is null and extensions.st_dwithin(o.location, m.location, 150)
  where o.osm_ref is not null`)
check('tidak ada OSM dalam 150 m dari data Admin', near.length === 0, near)
check('hampir semua punya adm4 (>99%)', st.adm4 / st.n > 0.99, st)
const noAdm4 = await all(`select name, osm_ref, extensions.st_astext(location::extensions.geometry) p from public.shelters where adm4 is null limit 5`)
if (noAdm4.length) console.log('  tanpa adm4:', noAdm4)
check('alamat kosong hanya bila tanpa adm4', (await one(`select count(*)::int n from public.shelters where address = '' and adm4 is not null`)).n === 0)
check('osm_ref unik & terisi untuk semua baris OSM', (await one(`select count(distinct osm_ref)::int n from public.shelters where source = 'OpenStreetMap'`)).n === st.n)
const au = await all(`select a.action, a.target_id, a.detail from public.audit_logs a
  where a.target_type = 'shelters' and (a.action = 'import' or a.target_id in (select id::text from public.shelters where osm_ref is not null))`)
check('log aktivitas: satu ringkasan impor, bukan per baris', au.length === 1 && au[0].action === 'import', au.slice(0, 3))
check('trigger audit_data aktif lagi', (await one(`select tgenabled from pg_trigger where tgname = 'audit_data' and tgrelid = 'public.shelters'::regclass`)).tgenabled === 'O')
check('indeks GiST shelters.location ada', !!(await one(`select 1 x from pg_indexes where tablename = 'shelters' and indexdef ilike '%gist (location)%'`)))

// Idempoten: migrasi hasil skrip yang sama (mis. data OSM diperbarui) bisa diterapkan ulang -> jumlah sama.
await db.exec(sql)
check('upsert ulang tidak menambah baris', (await one(`select count(*)::int n from public.shelters where source = 'OpenStreetMap'`)).n === st.n)
check('setelah upsert ulang alamat tetap terisi', (await one(`select count(*)::int n from public.shelters where address = '' and adm4 is not null`)).n === 0)
check('tidak ada klinik/posyandu bertanda RS', (await one(`select count(*)::int n from public.shelters where osm_ref is not null and name ~* '^(klinik|posyandu|apotek|praktek|bidan)' and name !~* 'puskesmas'`)).n === 0)

for (const [city, lat, lng] of [['Surabaya', -7.29, 112.73], ['Jakarta', -6.2, 106.82], ['Jayapura', -2.5337, 140.7181]]) {
  const rows = await all(`select name, address, phone, adm4, osm_ref,
      round(extensions.st_distance(location, extensions.st_setsrid(extensions.st_makepoint($2, $1), 4326)::extensions.geography)) m
    from public.shelters
    order by location operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint($2, $1), 4326)::extensions.geography
    limit 5`, [lat, lng])
  console.log(`\n${city}:`); for (const r of rows) console.log(' ', r)
  check(`${city}: 5 terdekat punya adm4 & alamat`, rows.length === 5 && rows.every(r => r.adm4 && r.address), rows)
}
const t0 = performance.now()
const sl = await all(`select * from public.shelters_list(null, -7.29, 112.73)`).catch(e => (console.log('  shelters_list:', e.message), []))
console.log(`  shelters_list(null,-7.29,112.73): ${sl.length} baris, ${Math.round(performance.now() - t0)} ms`)
const emp = await one(`select count(*)::int n from public.shelters where address = ''`)
check('tidak ada alamat kosong (termasuk sekitar Fakfak)', emp.n === 0, emp)
console.log(`\n${pass} PASS, ${fail} FAIL`)

// Apply Rivora Supabase migrations + seed on PGlite (PG18 + PostGIS 3.6) and test moderation.
// Jalankan: cd supabase/tests && npm install && node moderation.test.mjs
import { PGlite } from '@electric-sql/pglite'
import { postgis } from '@electric-sql/pglite-postgis'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm'
import fs from 'node:fs'
import path from 'node:path'
import { randomUUID } from 'node:crypto'

const ROOT = process.argv[2] ?? path.resolve(import.meta.dirname, '..')
const db = await PGlite.create({ extensions: { postgis, pgcrypto, pg_trgm } })

// ---------------------------------------------------------------- Supabase stubs
await db.exec(`
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
grant usage on schema public to anon, authenticated, service_role;
-- Supabase: default privileges give anon/authenticated ALL on new public tables/functions/sequences.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

create schema extensions;
create extension postgis with schema extensions;
create extension pgcrypto with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create schema auth;
create table auth.users(id uuid primary key, email text, encrypted_password text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated, service_role;

create schema storage;
create table storage.buckets(id text primary key, name text, public bool, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(), bucket_id text, name text);
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;

create schema cron;
create table cron.jobs(jobid bigserial, jobname text primary key, schedule text, command text);
create table cron.job_run_details(end_time timestamptz);
create function cron.unschedule(job_name text) returns boolean language sql as $$ delete from cron.jobs where jobname = job_name returning true $$;
create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
  insert into cron.jobs(jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $$;

create schema vault;
create table vault.decrypted_secrets(name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('project_url', 'https://example.supabase.co'), ('functions_secret_key', 'k');
create schema net;
create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int) returns bigint language sql as $$ select 1::bigint $$;
`)
await db.exec(`set search_path = "$user", public, extensions`)

// Seperti supabase db push: schema extensions tidak ada di search_path saat migrasi dijalankan.
const strict = sql => 'set search_path = "$user", public;\n' + sql + '\n;set search_path = "$user", public, extensions;'
const STRIP = /^\s*create extension if not exists (pg_cron|pg_net)\b[^;]*;/gim
const files = fs.readdirSync(path.join(ROOT, 'migrations')).filter(f => f.endsWith('.sql')).sort()
  .map(f => path.join(ROOT, 'migrations', f)).concat(path.join(ROOT, 'seed.sql'))
for (const f of files) {
  // Seperti supabase db push: schema extensions tidak ada di search_path saat migrasi.
  await db.exec(`set search_path = "$user", public`)
  try { await db.exec(strict(fs.readFileSync(f, 'utf8').replace(STRIP, '-- stripped'))) }
  catch (e) { console.log('FAILED', path.basename(f), e.message, e.where || ''); process.exit(1) }
}
console.log('semua migrasi + seed diterapkan')
let pass = 0, fail = 0
const check = (name, ok, got) => { ok ? pass++ : fail++; console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok ? '' : '  -> ' + JSON.stringify(got)}`) }
const all = async (s, p) => (await db.query(s, p)).rows
const one = async (s, p) => (await all(s, p))[0]
const errOf = async p => { try { await p; return null } catch (e) { return e.message } }
const as = (uid, fn) => db.transaction(async tx => {
  await tx.query('set local role authenticated')
  await tx.query(`select set_config('request.jwt.claim.sub', $1, true), set_config('request.jwt.claims', $2, true)`, [uid, JSON.stringify({ role: 'authenticated', sub: uid })])
  return fn(tx)
})
const q = async (uid, s, p) => (await as(uid, tx => tx.query(s, p))).rows
async function mk(name, role) {
  const id = randomUUID()
  await db.query(`insert into auth.users(id,email,raw_user_meta_data) values ($1,$2,$3)`, [id, name + '@x.id', { name }])
  if (role) await db.query(`update public.profiles set role=$2 where id=$1`, [id, role])
  return id
}
const admin = await mk('admin', 'admin'), va = await mk('verifa', 'verifikator')
const w = []; for (let i = 0; i < 5; i++) w.push(await mk('warga' + i))
await q(admin, `select public.set_staff_regions($1, array['35.78'])`, [va])
const report = async (uid, lng, lat, depth, file = 'a.jpg') => (await q(uid, `insert into public.reports (location, depth, photo_paths) values ($1, $2, array[$3]) returning id, adm4, flood_point_id`,
  [`SRID=4326;POINT(${lng} ${lat})`, depth, `${uid}/${file}`]))[0]
const pt = async id => one(`select verification, depth, source, status from public.flood_points where id=$1`, [id])

// --- Verifikasi otomatis: Makassar (tanpa verifikator)
await q(w[4], `insert into public.watch_locations (label, place, location, radius_m) values ('Rumah', 'Makassar', 'SRID=4326;POINT(119.4327 -5.1477)', 1000)`)
const m1 = await report(w[0], 119.4327, -5.1477, 'knee')
const m2 = await report(w[1], 119.4328, -5.1478, 'waist')
check('2 warga: titik masih belum terverifikasi', (await pt(m1.flood_point_id)).verification === 'unverified')
const m3 = await report(w[2], 119.4326, -5.1476, 'waist')
const p = await pt(m1.flood_point_id)
check('3 warga berbeda di wilayah tanpa verifikator: Terverifikasi otomatis', p.verification === 'verified' && p.source.includes('otomatis (3 warga)'), p)
check('kategori = median laporan (sepinggang)', p.depth === 'waist', p)
check('ketiga laporan disetujui tanpa reviewer', (await all(`select count(*)::int n from public.reports where flood_point_id=$1 and status='approved' and reviewed_by is null`, [m1.flood_point_id]))[0].n === 3)
check('notifikasi ke pemantau terkirim', (await all(`select 1 from public.notifications where flood_point_id=$1`, [m1.flood_point_id])).length === 1)
check('audit auto_verify tercatat', (await one(`select detail from public.audit_logs where action='auto_verify' order by id desc limit 1`))?.detail?.includes('3 warga'))

// Laporan ulang dari akun yang sama tidak dihitung dua kali
const d1 = await report(w[0], 119.50, -5.10, 'knee', 'b.jpg'); await report(w[0], 119.50, -5.10, 'knee', 'c.jpg'); await report(w[1], 119.50, -5.10, 'knee', 'b.jpg')
check('3 laporan dari 2 akun: belum otomatis', (await pt(d1.flood_point_id)).verification === 'unverified')

// Petugas menyetujui laporan berikutnya: label otomatis dilepas
const m4 = await report(w[3], 119.4327, -5.1477, 'waist')
await q(admin, `select public.review_report($1, true)`, [m4.id])
check('disetujui petugas: sumber kembali "Laporan warga"', (await pt(m1.flood_point_id)).source === 'Laporan warga')

// Surabaya punya verifikator: tidak otomatis
const s1 = await report(w[0], 112.7276, -7.3132, 'knee', 's.jpg'); await report(w[1], 112.7276, -7.3132, 'knee', 's.jpg'); await report(w[2], 112.7276, -7.3132, 'knee', 's.jpg')
check('wilayah dengan verifikator: tetap menunggu', (await pt(s1.flood_point_id)).verification === 'unverified')

// Nonaktif
await db.query(`update public.app_settings set crowd_min_reporters = 0`)
const n1 = await report(w[2], 119.60, -5.00, 'knee', 'n.jpg'); await report(w[3], 119.60, -5.00, 'knee', 'n.jpg'); await report(w[4], 119.60, -5.00, 'knee', 'n.jpg')
check('crowd_min_reporters=0: nonaktif', (await pt(n1.flood_point_id)).verification === 'unverified')
const eb = await errOf(db.query(`update public.app_settings set crowd_min_reporters = 1`))
check('ambang 1 warga ditolak constraint', eb !== null, eb)

// --- Wilayah tanpa verifikator
const un = await q(admin, `select region, name, pending::int from public.uncovered_regions()`)
check('uncovered_regions admin: Kota Makassar, bukan Surabaya', un.some(r => r.region === '73.71') && !un.some(r => r.region === '35.78'), un)
check('uncovered_regions verifikator: kosong', (await q(va, `select * from public.uncovered_regions()`)).length === 0)

// --- Laporkan foto
const photo = `${w[0]}/a.jpg`
check('foto disetujui tampil di point_photos', (await all(`select * from public.point_photos($1)`, [m1.flood_point_id])).some(r => r.point_photos === photo))
const ea = await errOf(db.transaction(async tx => { await tx.query('set local role anon'); await tx.query(`select public.flag_photo($1, 'tidak_pantas')`, [photo]) }))
check('tamu tidak bisa melaporkan foto', ea !== null, ea)
const ex = await errOf(q(w[1], `select public.flag_photo($1, 'lainnya')`, [`${w[0]}/tidak-ada.jpg`]))
check('foto tak dikenal ditolak', ex?.includes('tidak ditemukan'), ex)
await q(w[1], `select public.flag_photo($1, 'tidak_pantas')`, [photo])
await q(w[1], `select public.flag_photo($1, 'tidak_pantas')`, [photo]) // dobel dari akun sama
await q(w[2], `select public.flag_photo($1, 'data_pribadi')`, [photo])
check('2 akun melapor: foto masih tampil', (await all(`select * from public.point_photos($1)`, [m1.flood_point_id])).some(r => r.point_photos === photo))
await q(w[3], `select public.flag_photo($1, 'bukan_banjir')`, [photo])
check('3 akun melapor: foto disembunyikan', !(await all(`select * from public.point_photos($1)`, [m1.flood_point_id])).some(r => r.point_photos === photo))
check('foto tersembunyi tidak publik di storage', (await one(`select private.photo_is_public($1) ok`, [photo])).ok === false)
const fq = await q(admin, `select photo_path, flags::int, hidden, reasons from public.photo_flag_queue()`)
check('antrean foto admin: 3 laporan, tersembunyi', fq.length === 1 && fq[0].flags === 3 && fq[0].hidden, fq)
check('antrean foto verifikator Surabaya: tidak melihat Makassar', (await q(va, `select * from public.photo_flag_queue()`)).length === 0)
const er = await errOf(q(va, `select public.resolve_photo($1, false)`, [photo]))
check('verifikator luar wilayah tidak bisa memutuskan', er?.includes('wilayah'), er)
await q(admin, `select public.resolve_photo($1, false)`, [photo])
check('admin "tetap tampilkan": foto kembali & antrean bersih', (await all(`select * from public.point_photos($1)`, [m1.flood_point_id])).some(r => r.point_photos === photo)
  && (await q(admin, `select * from public.photo_flag_queue()`)).length === 0)
check('warga tidak bisa baca laporan foto orang lain', (await q(w[4], `select * from public.photo_flags`)).length === 0)

// --- Posko & faskes per area
await db.query(`insert into public.shelters (type, name, address, location, osm_ref, source) values
  ('faskes', 'RS OSM Makassar', 'x', 'SRID=4326;POINT(119.43 -5.14)', 'node/1', 'OpenStreetMap')`)
const noArg = await all(`select name from public.shelters_list()`)
check('tanpa filter: faskes OSM tidak ikut', !noArg.some(r => r.name === 'RS OSM Makassar'))
check('filter wilayah 73: faskes OSM ikut', (await all(`select name from public.shelters_list('73')`)).some(r => r.name === 'RS OSM Makassar'))
check('sekitar titik Makassar 30 km: ikut; Surabaya: tidak', (await all(`select name from public.shelters_list(null, -5.14, 119.43)`)).some(r => r.name === 'RS OSM Makassar')
  && !(await all(`select name from public.shelters_list(null, -7.29, 112.73)`)).some(r => r.name === 'RS OSM Makassar'))
console.log(`\n${pass} PASS, ${fail} FAIL`)

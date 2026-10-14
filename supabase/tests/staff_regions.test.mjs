// Apply Rivora Supabase migrations + seed on PGlite (PG18 + PostGIS 3.6) and test 20261014021010_panel_web.sql.
// Jalankan: cd supabase/tests && npm install && node staff_regions.test.mjs
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
const admin = await mk('admin', 'admin'), va = await mk('verifa', 'verifikator'), vb = await mk('verifb', 'verifikator'), warga = await mk('warga'), warga2 = await mk('warga2')
const report = async (uid, lng, lat, depth) => (await q(uid, `insert into public.reports (location, depth, photo_paths) values ($1, $2, array[$3]) returning id, adm4, flood_point_id`,
  [`SRID=4326;POINT(${lng} ${lat})`, depth, `${uid}/a.jpg`]))[0]

// Tugas wilayah
check('admin set_staff_regions(verifA, Kota Surabaya)', (await errOf(q(admin, `select public.set_staff_regions($1, array['35.78'])`, [va]))) === null)
const e1 = await errOf(q(va, `select public.set_staff_regions($1, array['35.78'])`, [vb]))
check('verifikator tidak boleh set wilayah', e1?.includes('Hanya admin'), e1)
const e2 = await errOf(q(admin, `select public.set_staff_regions($1, array['35.78.22'])`, [vb]))
check('kode kecamatan ditolak (harus kab/kota)', e2?.includes('bukan kab/kota'), e2)
check('audit set_regions tercatat', (await one(`select detail from public.audit_logs where action='set_regions' order by id desc limit 1`))?.detail?.includes('Kota Surabaya'))

const sby = await report(warga, 112.7276, -7.3132, 'knee')     // Surabaya
const mks = await report(warga2, 119.4327, -5.1477, 'waist')   // Makassar
check('laporan dapat adm4 (Surabaya 35.78.*, Makassar 73.71.*)', sby.adm4.startsWith('35.78.') && mks.adm4.startsWith('73.71.'), [sby.adm4, mks.adm4])

const qa = await q(va, `select id, adm4 from public.review_queue('pending')`)
check('review_queue verifA: hanya laporan Surabaya', qa.length === 1 && qa[0].id === sby.id, qa)
check('review_queue verifB tanpa tugas: kosong', (await q(vb, `select id from public.review_queue('pending')`)).length === 0)
check('review_queue admin: semua', (await q(admin, `select id from public.review_queue('pending')`)).length === 2)
check('tabel reports via RLS (verifA): hanya Surabaya', JSON.stringify((await q(va, `select id from public.reports`)).map(r => r.id)) === JSON.stringify([sby.id]))
check('hitung pending verifB = 0', (await q(vb, `select count(*)::int n from public.reports where status='pending'`))[0].n === 0)
const e3 = await errOf(q(va, `select public.review_report($1, true)`, [mks.id]))
check('verifA setujui laporan Makassar -> ditolak 42501', e3?.includes('di luar wilayah'), e3)
check('verifA setujui laporan Surabaya -> boleh', (await errOf(q(va, `select public.review_report($1, true)`, [sby.id]))) === null)

const pa = await q(va, `select name, adm4 from public.flood_points_all()`)
check('flood_points_all verifA: hanya titik Surabaya', pa.length === 1 && pa[0].adm4.startsWith('35.78.'), pa)
check('flood_points_all admin + filter 73: hanya Makassar', (await q(admin, `select adm4 from public.flood_points_all('73')`)).every(r => r.adm4.startsWith('73.')))
const e4 = await errOf(q(va, `select public.publish_official('Jl. Makassar', null, -5.15, 119.43, 'knee', 'BPBD Kota Makassar')`))
check('verifA status Resmi di Makassar -> ditolak', e4?.includes('di luar wilayah'), e4)
const pid = (await q(admin, `select public.publish_official('Jl. Penghibur', null, -5.1400, 119.4070, 'waist', 'BPBD Kota Makassar') id`))[0].id
const pd = await one(`select district, adm4 from public.flood_points where id=$1`, [pid])
check('status Resmi Makassar: district = nama kecamatan otomatis', pd.adm4.startsWith('73.71.') && pd.district?.length > 0, pd)

// Zona waktu: watcher di Makassar, surut ditandai admin
await q(warga2, `insert into public.watch_locations (label, place, location, radius_m) values ('Rumah', 'Makassar', 'SRID=4326;POINT(119.4070 -5.1400)', 2000)`)
await q(admin, `select public.mark_receded($1, now() - interval '5 minutes')`, [pid])
const nt = await one(`select body from public.notifications where flood_point_id=$1 order by id desc limit 1`, [pid])
check('notifikasi surut Makassar memakai WITA', nt?.body?.includes(' WITA.'), nt)
check('audit mark_receded memakai WITA', (await one(`select detail from public.audit_logs where action='mark_receded' order by id desc limit 1`)).detail.endsWith('WITA'))

const au = await q(admin, `select name, regions from public.admin_users() where name='verifa'`)
check('admin_users mengembalikan wilayah tugas', JSON.stringify(au[0]?.regions) === '["35.78"]', au)
const ct = await all(`select name, region, category from public.emergency_contacts order by sort_order`)
check('kontak: BPBD Surabaya region 35.78 + BNPB 117 + Basarnas 115', ct.find(c => c.name === 'BPBD Kota Surabaya')?.region === '35.78' && ct.some(c => c.category === 'bnpb') && ct.some(c => c.category === 'sar'), ct)
check('shelters_list mengembalikan adm4', (await all(`select adm4 from public.shelters_list()`)).every(r => r.adm4))
check('regions_in(null) = 38 provinsi; regions_in(35) = 38 kab/kota Jatim', (await all(`select * from public.regions_in()`)).length === 38 && (await all(`select * from public.regions_in('35')`)).length === 38)
const mr = await q(va, `select code, name, lat from public.my_regions()`)
check('my_regions verifA = Kota Surabaya + titik tengah', mr.length === 1 && mr[0].name === 'Kota Surabaya' && mr[0].lat < -7, mr)
check('my_regions verifB = kosong', (await q(vb, `select * from public.my_regions()`)).length === 0)
console.log(`\n${pass} PASS, ${fail} FAIL`)

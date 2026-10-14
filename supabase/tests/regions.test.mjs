// Apply Rivora Supabase migrations + seed on PGlite (PG18 + PostGIS 3.6) and test 20261014021010_panel_web.sql.
// Jalankan: cd supabase/tests && npm install && node regions.test.mjs
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

// ---------------------------------------------------------------- migrations + seed
// Seperti supabase db push: schema extensions tidak ada di search_path saat migrasi dijalankan.
const strict = sql => 'set search_path = "$user", public;\n' + sql + '\n;set search_path = "$user", public, extensions;'
const STRIP = /^\s*create extension if not exists (pg_cron|pg_net)\b[^;]*;/gim
const files = fs.readdirSync(path.join(ROOT, 'migrations')).filter(f => f.endsWith('.sql')).sort()
  .map(f => path.join(ROOT, 'migrations', f)).concat(path.join(ROOT, 'seed.sql'))
for (const f of files) {
  const t0 = Date.now()
  try { await db.exec(strict(fs.readFileSync(f, 'utf8').replace(STRIP, '-- stripped'))) }
  catch (e) { console.log('FAILED', path.basename(f), e.message, e.where || ''); process.exit(1) }
  console.log('APPLIED', path.basename(f), (Date.now() - t0) + ' ms')
}
let pass = 0, fail = 0
const check = (name, ok, got) => { ok ? pass++ : fail++; console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok ? '' : '  -> ' + JSON.stringify(got)}`) }
const all = async (s, p) => (await db.query(s, p)).rows
const one = async (s, p) => (await all(s, p))[0]

const lv = await all(`select level, count(*)::int n, count(location)::int with_pt from public.regions group by level order by level`)
console.log(lv)
check('jumlah per tingkat 38/514/7285/83762', JSON.stringify(lv.map(r => r.n)) === '[38,514,7285,83762]', lv)
check('label desa lengkap', (await one(`select label from public.regions where code='35.78.22.1001'`)).label === 'Gayungan, Gayungan, Kota Surabaya, Jawa Timur')
const v = await one(`select * from public.village_at(-7.3175, 112.7268)`)
check('GPS dekat Ketintang -> Kel. Ketintang (35.78.22.1004)', v?.code === '35.78.22.1004', v)
console.log('  village_at:', v)
const jp = await one(`select * from public.village_at(-2.5337, 140.7181)`)
check('GPS Jayapura -> desa di Papua (91.*)', jp?.code?.startsWith('91.'), jp)
check('GPS di tengah laut (>50 km) -> kosong', (await all(`select * from public.village_at(-5.0, 108.5)`)).length === 0)
for (const [c, tz] of [['35.78.22.1001', 'Asia/Jakarta'], ['73.71', 'Asia/Makassar'], ['51.71', 'Asia/Makassar'], ['91.71', 'Asia/Jayapura'], ['61.71', 'Asia/Jakarta'], ['64.72', 'Asia/Makassar'], ['81.71', 'Asia/Jayapura']])
  check(`tz_of(${c}) = ${tz}`, (await one(`select public.tz_of($1) tz`, [c])).tz === tz)
for (const q of ['gubeng', 'ketintang surabaya', 'kota bandung', 'makassar', 'jayapura']) {
  const t0 = performance.now()
  const r = await all(`select code, level, label, adm4 from public.search_regions($1)`, [q])
  const ms = Math.round(performance.now() - t0)
  console.log(`  search "${q}" ${ms} ms ->`, r.slice(0, 3).map(x => `${x.label} [L${x.level} adm4=${x.adm4}]`))
  check(`search "${q}" ada hasil & tiap hasil punya adm4`, r.length > 0 && r.every(x => x.adm4?.length === 13), r.slice(0, 2))
}
check('search < 3 huruf -> kosong', (await all(`select * from public.search_regions('ab')`)).length === 0)
console.log((await all(`explain analyze select * from public.regions r where lower(r.label) like '%gubeng%' and lower(r.label) like all (array['%gubeng%','%surabaya%'])`)).map(r => r['QUERY PLAN']).join('\n'))

// Kode desa otomatis untuk data berlokasi
const uid = randomUUID()
await db.query(`insert into auth.users(id,email) values ($1,'warga@x.id')`, [uid])
await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid])
await db.exec(`insert into public.reports (user_id, location, depth, photo_paths) values ('${uid}', 'SRID=4326;POINT(112.7276 -7.3132)', 'knee', array['${uid}/a.jpg'])`)
const rp = await one(`select r.adm4, p.adm4 p_adm4, p.district from public.reports r join public.flood_points p on p.id = r.flood_point_id`)
check('laporan & titik baru dapat adm4 + district = nama kecamatan', rp.adm4?.startsWith('35.78.22.') && rp.p_adm4 === rp.adm4 && rp.district === 'Gayungan', rp)
const sh = await one(`select count(*)::int n, count(adm4)::int a from public.shelters where source is distinct from 'OpenStreetMap'`)
check('faskes seed ter-backfill adm4', sh.n > 0 && sh.n === sh.a, sh)
console.log(`\n${pass} PASS, ${fail} FAIL`)

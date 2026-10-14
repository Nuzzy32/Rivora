// Apply Rivora Supabase migrations + seed on PGlite (PG18 + PostGIS 3.6) and test 20261014021010_panel_web.sql.
// Jalankan: cd supabase/tests && npm install && node forecast.test.mjs
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

const jobs = (await all(`select jobname from cron.jobs order by 1`)).map(r => r.jobname)
check('cron: bmkg-forecast dihapus, bmkg-nowcast & cleanup ada', !jobs.includes('bmkg-forecast') && jobs.includes('bmkg-nowcast') && jobs.includes('cleanup-weather-warnings'), jobs)

let f = await one(`select * from public.forecast_for('35.78.22.1004')`)
check('forecast_for tanpa cache: label & tz ada, forecast null, warnings []', f.label.startsWith('Ketintang') && f.tz === 'Asia/Jakarta' && f.forecast_json === null && JSON.stringify(f.warnings) === '[]', f)
check('forecast_for kode bukan desa -> kosong', (await all(`select * from public.forecast_for('35.78.22')`)).length === 0)
check('forecast_for Jayapura -> tz Asia/Jayapura', (await one(`select tz from public.forecast_for('91.71.03.2004')`)).tz === 'Asia/Jayapura')

await db.exec(`insert into public.forecast_cache (adm4, forecast_json) values ('35.78.22.1004', '{"slots":[{"time":"2026-10-14T11:00:00Z","kind":"rain"}]}')`)
// Peringatan yang menutupi Surabaya selatan, satu yang sudah kedaluwarsa, satu di Papua.
await db.exec(`insert into public.weather_warnings (id, event, headline, expires, area) values
 ('a', 'Hujan lebat', 'Waspada hujan lebat di Surabaya', now() + interval '2 hours', 'SRID=4326;MULTIPOLYGON(((112.6 -7.4,112.9 -7.4,112.9 -7.2,112.6 -7.2,112.6 -7.4)))'),
 ('b', 'Hujan lebat', 'Sudah lewat', now() - interval '1 hour', 'SRID=4326;MULTIPOLYGON(((112.6 -7.4,112.9 -7.4,112.9 -7.2,112.6 -7.2,112.6 -7.4)))'),
 ('c', 'Angin kencang', 'Papua', now() + interval '2 hours', 'SRID=4326;MULTIPOLYGON(((140 -3,141 -3,141 -2,140 -2,140 -3)))')`)
f = await one(`select * from public.forecast_for('35.78.22.1004')`)
check('forecast_for: cache terbaca + hanya peringatan aktif yang menutupi desa', f.forecast_json?.slots?.length === 1 && f.warnings.length === 1 && f.warnings[0].headline.includes('Surabaya'), f)

// Kuota: 50 per menit, ke-51 ditolak.
const takes = []
for (let i = 0; i < 51; i++) takes.push((await one(`select public.bmkg_take_slot() ok`)).ok)
check('kuota: 50 boleh, ke-51 ditolak', takes.slice(0, 50).every(Boolean) && takes[50] === false, takes.slice(48))
await db.exec(`update private.bmkg_quota set win = win - interval '1 minute'`)
check('kuota: menit baru dibuka lagi', (await one(`select public.bmkg_take_slot() ok`)).ok === true)
const e = await errOf(db.transaction(async tx => { await tx.query('set local role anon'); await tx.query('select public.bmkg_take_slot()') }))
check('anon tidak boleh memakai kuota', e?.includes('permission denied'), e)
const e2 = await errOf(db.transaction(async tx => { await tx.query('set local role authenticated'); await tx.query('select public.bmkg_take_slot()') }))
check('pengguna login juga tidak boleh', e2?.includes('permission denied'), e2)
const anonRead = await db.transaction(async tx => { await tx.query('set local role anon'); return (await tx.query(`select * from public.forecast_for('35.78.22.1004')`)).rows })
check('anon boleh baca forecast_for', anonRead.length === 1)
console.log(`\n${pass} PASS, ${fail} FAIL`)

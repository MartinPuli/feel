// Optional real PostgreSQL/WASM fixture. Never connects to Supabase or a network service.
// Install the pinned package into a temporary directory, then pass its absolute ESM entry path.
// Not named *.test.mjs: normal service tests have no external package dependency.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

if (!process.argv[2]) throw new Error('Pass the absolute path to @electric-sql/pglite/dist/index.js');
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = await PGlite.create();
const sql = await readFile(new URL('./admission-reference.sql', import.meta.url), 'utf8');
const users = ['a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002'];
let passed = 0;
async function check(name, run) { await run(); passed++; console.log(`PASS ${name}`); }
async function asRole(role, run) {
  assert.ok(['anon', 'authenticated', 'service_role'].includes(role));
  await db.exec(`set role ${role}`);
  try { return await run(); } finally { await db.exec('reset role'); }
}
async function reserve(user = users[0], operation = 'voice_session') {
  return asRole('service_role', async () => (await db.query(
    'select public.feel_reserve_admission($1::uuid, $2::text) as result', [user, operation])).rows[0].result);
}
async function configure({ userMinute = 10, userDay = 100, globalMinute = 100, globalDay = 1000, enabled = true } = {}) {
  await db.exec('truncate feel_admission.counters; delete from feel_admission.policies;');
  await db.query(`insert into feel_admission.policies
    (operation, enabled, per_user_minute, per_user_day, global_minute, global_day)
    values ('voice_session', $1, $2, $3, $4, $5)`, [enabled, userMinute, userDay, globalMinute, globalDay]);
}
function denied(result, maximum = 86400) {
  assert.equal(result.allowed, false); assert.equal(result.reason, 'quota_exceeded');
  assert.ok(Number.isInteger(result.retry_after_seconds) && result.retry_after_seconds > 0 && result.retry_after_seconds <= maximum);
}
async function snapshot() { return (await db.query('select * from feel_admission.counters order by subject')).rows; }
try {
  await db.exec('create role anon; create role authenticated; create role service_role bypassrls;');
  await check('unchanged reference SQL applies', () => db.exec(sql));
  for (const role of ['anon', 'authenticated']) {
    await check(`${role} cannot execute RPC or read private tables`, async () => {
      await asRole(role, async () => {
        await assert.rejects(db.query('select public.feel_reserve_admission($1::uuid,$2::text)', [users[0], 'voice_session']), { code: '42501' });
        await assert.rejects(db.query('select * from feel_admission.counters'), { code: '42501' });
        await assert.rejects(db.query('select * from feel_admission.policies'), { code: '42501' });
      });
    });
  }
  await check('explicit role guard survives accidental RPC grant', async () => {
    await db.exec('grant execute on function public.feel_reserve_admission(uuid,text) to authenticated');
    await asRole('authenticated', () => assert.rejects(db.query('select public.feel_reserve_admission($1::uuid,$2::text)', [users[0], 'voice_session']), { code: '42501' }));
    await db.exec('revoke execute on function public.feel_reserve_admission(uuid,text) from authenticated');
  });
  await check('missing and disabled policy fail closed', async () => {
    assert.deepEqual(await reserve(), { allowed: false, reason: 'not_enabled', retry_after_seconds: 0 });
    await configure({ enabled: false });
    assert.deepEqual(await reserve(), { allowed: false, reason: 'not_enabled', retry_after_seconds: 0 });
    assert.equal((await snapshot()).length, 0);
  });
  await check('service role cannot change operator policy', async () => {
    await asRole('service_role', () => assert.rejects(db.exec('update feel_admission.policies set enabled = true'), { code: '42501' }));
  });
  await check('invalid operation and reserved principal are rejected', async () => {
    await assert.rejects(reserve(users[0], 'caller_chosen_operation'), { code: '22023' });
    await assert.rejects(reserve('00000000-0000-0000-0000-000000000000'), { code: '22023' });
    await assert.rejects(reserve(null), { code: '22023' });
  });
  await check('per-user minute quota and denial do not increment usage', async () => {
    await configure({ userMinute: 1 }); assert.equal((await reserve()).allowed, true);
    const before = await snapshot(); denied(await reserve(), 60); assert.deepEqual(await snapshot(), before);
    assert.equal((await reserve(users[1])).allowed, true);
  });
  await check('global minute quota spans different users', async () => {
    await configure({ globalMinute: 1 }); assert.equal((await reserve()).allowed, true);
    denied(await reserve(users[1]), 60);
    const rows = await snapshot(); assert.equal(Number(rows[0].minute_count), 1);
    assert.equal(Number(rows.find(row => row.subject === users[1]).day_count), 0);
  });
  await check('per-user day quota survives minute rollover', async () => {
    await configure({ userDay: 1 }); assert.equal((await reserve()).allowed, true);
    await db.exec("update feel_admission.counters set minute_start = minute_start - interval '1 minute'");
    denied(await reserve()); assert.equal((await reserve(users[1])).allowed, true);
  });
  await check('global day quota survives minute rollover', async () => {
    await configure({ globalDay: 1 }); assert.equal((await reserve()).allowed, true);
    await db.exec("update feel_admission.counters set minute_start = minute_start - interval '1 minute'");
    denied(await reserve(users[1]));
  });
  await check('minute rollover resets minute counts and preserves day counts', async () => {
    await configure({ userMinute: 1 }); assert.equal((await reserve()).allowed, true);
    await db.exec("update feel_admission.counters set minute_start = minute_start - interval '1 minute'");
    assert.equal((await reserve()).allowed, true);
    for (const row of await snapshot()) { assert.equal(Number(row.minute_count), 1); assert.equal(Number(row.day_count), 2); }
  });
  await check('day rollover resets both windows in a non-UTC database timezone', async () => {
    await configure({ userMinute: 1, userDay: 1, globalMinute: 1, globalDay: 1 });
    await db.exec("set timezone = 'Pacific/Auckland'"); assert.equal((await reserve()).allowed, true);
    await db.exec("update feel_admission.counters set minute_start = minute_start - interval '1 day', day_start = day_start - interval '1 day'");
    assert.equal((await reserve()).allowed, true);
    for (const row of await snapshot()) { assert.equal(Number(row.minute_count), 1); assert.equal(Number(row.day_count), 1); }
  });
  await check('RLS still hides counters after an accidental SELECT grant', async () => {
    await db.exec('grant usage on schema feel_admission to authenticated; grant select on feel_admission.counters to authenticated');
    await asRole('authenticated', async () => assert.deepEqual((await db.query('select * from feel_admission.counters')).rows, []));
    await db.exec('revoke usage on schema feel_admission from authenticated; revoke select on feel_admission.counters from authenticated');
  });
  await check('reference SQL can be reapplied without resetting counters', async () => {
    const before = await snapshot(); await db.exec(sql); assert.deepEqual(await snapshot(), before);
  });
  console.log(`PASS ${passed} PostgreSQL/WASM cases. Single connection only; no concurrency, PostgREST, or live deployment proof.`);
} finally { await db.close(); }

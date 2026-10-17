import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createTokenServer, readConfig } from './server.mjs';

const config = {
  apiKey: 'test-server-key-never-returned',
  accessToken: 'test-device-token-at-least-32-characters',
  requireHTTPS: false,
};
const timestamp = 1800000000000;
const session = { value: 'test-ephemeral-secret', expires_at: timestamp / 1000 + 300 };

async function fixture(t, options = {}, overrides = {}) {
  const calls = [];
  const server = createTokenServer({ ...config, ...overrides }, {
    now: () => timestamp,
    fetchImpl: async (...args) => {
      calls.push(args);
      return Response.json({
        ...session,
        session: { type: 'realtime', model: 'gpt-realtime-2.1', instructions: 'Provider defaults' },
        ignored: 'must not return extra fields',
      });
    },
    ...options,
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}`;
  const request = (options = {}, path = '/session') => fetch(url + path, {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.accessToken}` },
    ...options,
  });
  return { calls, request };
}

test('configuration fails closed without exposing supplied values', () => {
  assert.throws(() => readConfig({}), /Set OPENAI_API_KEY/);
  assert.throws(() => readConfig({ OPENAI_API_KEY: config.apiKey }), /distinct FEEL/);
  assert.throws(() => readConfig({ OPENAI_API_KEY: config.accessToken,
    FEEL_VOICE_ACCESS_TOKEN: config.accessToken }), /distinct FEEL/);
  const env = { OPENAI_API_KEY: config.apiKey, FEEL_VOICE_ACCESS_TOKEN: config.accessToken };
  assert.equal(readConfig(env).port, 8081);
  assert.throws(() => readConfig({ ...env, PORT: 'bad' }), /PORT/);
  assert.throws(() => readConfig({ ...env, REQUIRE_HTTPS: 'typo' }), /REQUIRE_HTTPS/);
});

test('authenticated session uses fixed official contract and returns only ephemeral fields', async t => {
  const { request, calls } = await fixture(t);
  const response = await request();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  assert.deepEqual(await response.json(), session);
  assert.equal(calls.length, 1);
  const [url, options] = calls[0];
  assert.equal(url, 'https://api.openai.com/v1/realtime/client_secrets');
  assert.equal(options.headers.Authorization, `Bearer ${config.apiKey}`);
  assert.equal(options.method, 'POST');
  assert.equal(options.redirect, 'error');
  assert.deepEqual(JSON.parse(options.body), {
    expires_after: { anchor: 'created_at', seconds: 300 },
    session: {
      type: 'realtime', model: 'gpt-realtime-2.1', audio: { output: { voice: 'cedar' } },
    },
  });
});

test('missing and wrong credentials never reach provider or echo credentials', async t => {
  const { request, calls } = await fixture(t);
  for (const authorization of ['', 'Bearer wrong-token', `Bearer ${config.apiKey}`]) {
    const response = await request({ headers: { Authorization: authorization } });
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'unauthorized' });
  }
  assert.equal(calls.length, 0);
});

test('only exact empty POST /session can mint a token', async t => {
  const { request, calls } = await fixture(t);
  assert.equal((await request({ method: 'GET' })).status, 405);
  assert.equal((await request({}, '/session?url=https://example.com')).status, 404);
  assert.equal((await request({ body: '{"expires_after":{"seconds":99999}}' })).status, 400);
  assert.equal((await request({ method: 'GET', headers: {} }, '/health')).status, 200);
  assert.equal(calls.length, 0);
});

test('production rejects requests without the local proxy HTTPS marker', async t => {
  const { request, calls } = await fixture(t, {}, { requireHTTPS: true });
  assert.equal((await request()).status, 426);
  assert.equal(calls.length, 0);
  const response = await request({ headers: {
    Authorization: `Bearer ${config.accessToken}`, 'X-Forwarded-Proto': 'https',
  } });
  assert.equal(response.status, 200);
});

test('fixed global rate limit prevents extra provider requests and recovers next minute', async t => {
  let time = timestamp;
  const { request, calls } = await fixture(t, { now: () => time, requestsPerMinute: 2 });
  assert.equal((await request()).status, 200);
  assert.equal((await request()).status, 200);
  const limited = await request();
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('retry-after'), '60');
  assert.equal(calls.length, 2);
  time += 60000;
  assert.equal((await request()).status, 200);
  assert.equal(calls.length, 3);
});

test('provider failures and exceptions expose no secret or provider diagnostics', async t => {
  const secretText = `${config.apiKey} ${config.accessToken} ${session.value}`;
  for (const fetchImpl of [
    async () => new Response(secretText, { status: 401 }),
    async () => { throw new Error(secretText); },
    async () => new Response(secretText),
    async () => new Response('x'.repeat(17000)),
  ]) {
    const { request } = await fixture(t, { fetchImpl });
    const response = await request();
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: 'voice_provider_unavailable' });
  }
});

test('rejects malformed, expired, overlong and long-lived provider credentials', async t => {
  for (const invalid of [
    {}, null, { ...session, expires_at: timestamp / 1000 },
    { ...session, expires_at: timestamp / 1000 + 9999 },
    { ...session, expires_at: String(session.expires_at) },
    { ...session, value: '' }, { ...session, value: 'contains space' },
    { ...session, value: 'x'.repeat(4097) },
    { ...session, value: config.apiKey }, { ...session, value: config.accessToken },
  ]) {
    const { request } = await fixture(t, { fetchImpl: async () => Response.json(invalid) });
    const response = await request();
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: 'invalid_voice_session' });
  }
});

test('timeout aborts provider request and returns fixed error', async t => {
  let aborted = false;
  const { request } = await fixture(t, {
    upstreamTimeoutMs: 10,
    fetchImpl: (_, { signal }) => new Promise((_, reject) => {
      signal.addEventListener('abort', () => {
        aborted = true;
        reject(new Error(config.apiKey));
      }, { once: true });
    }),
  });
  const response = await request();
  assert.equal(response.status, 504);
  assert.deepEqual(await response.json(), { error: 'voice_provider_timeout' });
  assert.equal(aborted, true);
});

test('no more than two provider requests may run concurrently', async t => {
  const resolvers = [];
  const { request } = await fixture(t, {
    fetchImpl: () => new Promise(resolve => resolvers.push(resolve)),
  });
  const first = request();
  const second = request();
  while (resolvers.length < 2) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal((await request()).status, 429);
  for (const resolve of resolvers) resolve(Response.json(session));
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createVercelHandler } from './vercel-handler.mjs';

const config = {
  apiKey: 'mock-provider-key',
  accessToken: 'mock-device-token-longer-than-32-characters',
  requireHTTPS: false,
};
const timestamp = 1800000000000;
const session = { value: 'mock-ephemeral-token', expires_at: timestamp / 1000 + 300 };

function fixture(options = {}) {
  const calls = [];
  const handler = createVercelHandler({
    loadConfig: () => config,
    now: () => timestamp,
    fetchImpl: async (...args) => {
      calls.push(args);
      return Response.json(session);
    },
    ...options,
  });
  return { handler, calls };
}

async function invoke(handler, overrides = {}) {
  const req = {
    method: 'POST', url: '/api/session',
    headers: {
      authorization: `Bearer ${config.accessToken}`,
      'x-forwarded-proto': 'https',
    },
    ...overrides,
  };
  const res = new EventEmitter();
  res.writeHead = (status, headers) => { res.status = status; res.headers = headers; };
  res.end = body => { res.body = JSON.parse(body); res.writableEnded = true; };
  await handler(req, res);
  return res;
}

test('Vercel direct and rewritten paths use the same authenticated token contract', async () => {
  const { handler, calls } = fixture();
  for (const url of ['/api/session', '/session']) {
    const res = await invoke(handler, { url });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, session);
    assert.equal(res.headers['Cache-Control'], 'no-store');
  }
  assert.equal(calls.length, 2);
  assert.equal(calls[0][0], 'https://api.x.ai/v1/realtime/client_secrets');
  assert.deepEqual(JSON.parse(calls[0][1].body), { expires_after: { seconds: 300 } });
});

test('Vercel adapter cannot disable HTTPS through local environment settings', async () => {
  const { handler, calls } = fixture();
  for (const protocol of [undefined, 'http', 'https,http']) {
    const res = await invoke(handler, { headers: {
      authorization: `Bearer ${config.accessToken}`, 'x-forwarded-proto': protocol,
    } });
    assert.equal(res.status, 426);
  }
  assert.equal(calls.length, 0);
});

test('adapter preserves authentication, method and exact-path restrictions', async () => {
  const { handler, calls } = fixture();
  assert.equal((await invoke(handler, { headers: { 'x-forwarded-proto': 'https' } })).status, 401);
  assert.equal((await invoke(handler, { method: 'GET' })).status, 405);
  assert.equal((await invoke(handler, { url: '/api/session?url=https://example.com' })).status, 404);
  assert.equal((await invoke(handler, { url: '/other' })).status, 404);
  assert.equal(calls.length, 0);
});

test('parsed request bodies cannot bypass the empty body requirement', async () => {
  const { handler, calls } = fixture();
  for (const body of [{}, null, 'data', Buffer.from('data')]) {
    assert.equal((await invoke(handler, { body })).status, 400);
  }
  assert.equal(calls.length, 0);
});

test('configuration failure returns a fixed non-cacheable error without secrets', async () => {
  const { handler } = fixture({ loadConfig: () => { throw new Error(config.apiKey); } });
  const res = await invoke(handler);
  assert.equal(res.status, 503);
  assert.deepEqual(res.body, { error: 'voice_service_not_configured' });
  assert.equal(res.headers['Cache-Control'], 'no-store');
});

test('warm function requests retain rate limits and load configuration once', async () => {
  let loads = 0;
  const { handler, calls } = fixture({
    requestsPerMinute: 1,
    loadConfig: () => { loads += 1; return config; },
  });
  assert.equal((await invoke(handler)).status, 200);
  assert.equal((await invoke(handler, { url: '/session' })).status, 429);
  assert.equal(loads, 1);
  assert.equal(calls.length, 1);
});

test('separate function instances have independent limits, not a global quota', async () => {
  const first = fixture({ requestsPerMinute: 1 });
  const second = fixture({ requestsPerMinute: 1 });
  assert.equal((await invoke(first.handler)).status, 200);
  assert.equal((await invoke(first.handler)).status, 429);
  assert.equal((await invoke(second.handler)).status, 200);
});

test('function entry point imports without starting a server or loading configuration', async () => {
  const { default: handler } = await import('./api/session.mjs');
  assert.equal(typeof handler, 'function');
});

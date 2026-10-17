import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { handler, parseRange, resolvePath } from './server.mjs';

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'feel-web-'));
  const publicDir = join(root, 'public'), dataDir = join(root, 'data');
  mkdirSync(join(publicDir, 'replay'), { recursive: true });
  mkdirSync(join(dataDir, 'sessions', 'a'), { recursive: true });
  writeFileSync(join(publicDir, 'index.html'), 'home');
  writeFileSync(join(publicDir, 'replay', 'index.html'), 'replay');
  writeFileSync(join(dataDir, 'index.json'), '{"sessions":[]}');
  writeFileSync(join(dataDir, 'sessions', 'a', 'camera.mp4'), Buffer.from('0123456789'));
  writeFileSync(join(root, 'secret.txt'), 'nope');
  return { publicDir, dataDir };
}

test('paths resolve inside their roots only', () => {
  const roots = fixture();
  assert.equal(resolvePath('/replay/', roots).file.endsWith(join('replay', 'index.html')), true);
  assert.equal(resolvePath('/replay', roots).redirect, true);
  assert.ok(resolvePath('/replay/data/index.json', roots).file.endsWith('index.json'));
  for (const bad of ['/../secret.txt', '/replay/data/../../secret.txt', '/%2e%2e/secret.txt', '/replay/data/%2e%2e/%2e%2e/secret.txt', '/a%00b', '/%E0%A4%A']) {
    assert.equal(resolvePath(bad, roots), null, bad);
  }
});

test('byte ranges', () => {
  assert.deepEqual(parseRange('bytes=0-3', 10), { start: 0, end: 3 });
  assert.deepEqual(parseRange('bytes=4-', 10), { start: 4, end: 9 });
  assert.deepEqual(parseRange('bytes=-3', 10), { start: 7, end: 9 });
  assert.deepEqual(parseRange('bytes=5-99', 10), { start: 5, end: 9 });
  assert.equal(parseRange('bytes=10-12', 10), null);
  assert.equal(parseRange('bytes=1-2,4-5', 10), null);
  assert.equal(parseRange(undefined, 10), null);
});

test('serves video ranges and rejects other methods', async () => {
  const server = createServer(handler(fixture())).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const partial = await fetch(`${base}/replay/data/sessions/a/camera.mp4`, { headers: { Range: 'bytes=2-5' } });
    assert.equal(partial.status, 206);
    assert.equal(partial.headers.get('content-range'), 'bytes 2-5/10');
    assert.equal(partial.headers.get('content-type'), 'video/mp4');
    assert.equal(await partial.text(), '2345');
    assert.equal((await fetch(`${base}/replay/data/sessions/a/camera.mp4`, { headers: { Range: 'bytes=50-' } })).status, 416);
    assert.equal((await fetch(`${base}/replay/`)).status, 200);
    assert.equal((await fetch(`${base}/nope`)).status, 404);
    assert.equal((await fetch(`${base}/`, { method: 'POST' })).status, 405);
  } finally { server.close(); }
});

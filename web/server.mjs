// FEEL website, local development server. No dependencies.
// Serves web/public, and /replay/data/* from simulation/out/web (written by simulation/run.py),
// with HTTP Range support so recorded video can seek. Binds 127.0.0.1 only.
import { createServer } from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
export const PUBLIC = resolve(here, 'public');
export const DATA = resolve(here, '..', 'simulation', 'out', 'web');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.mp4': 'video/mp4',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8',
};

/** Map a URL path to a file under one of the two roots, or null. Never escapes a root. */
export function resolvePath(urlPath, { publicDir = PUBLIC, dataDir = DATA } = {}) {
  let path;
  try { path = decodeURIComponent(urlPath.split('?')[0]); } catch { return null; }
  if (path.includes('\0')) return null;
  let root = publicDir, rest = path;
  if (path === '/replay/data' || path.startsWith('/replay/data/')) { root = dataDir; rest = path.slice('/replay/data'.length); }
  const target = normalize(join(root, rest));
  if (target !== root && !target.startsWith(root + sep)) return null;
  let stat;
  try { stat = statSync(target); } catch { return null; }
  if (stat.isDirectory()) {
    const index = join(target, 'index.html');
    try { if (statSync(index).isFile()) return { file: index, size: statSync(index).size, redirect: !path.endsWith('/') }; } catch { return null; }
    return null;
  }
  return stat.isFile() ? { file: target, size: stat.size } : null;
}

/** Parse a single "bytes=a-b" range; null for none or unsatisfiable. */
export function parseRange(header, size) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(header ?? '');
  if (!match || (match[1] === '' && match[2] === '')) return null;
  let start, end;
  if (match[1] === '') { start = Math.max(0, size - Number(match[2])); end = size - 1; }
  else { start = Number(match[1]); end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1); }
  return start <= end && start < size ? { start, end } : null;
}

export function handler(options = {}) {
  return (req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD' }).end(); return; }
    const url = req.url ?? '/';
    const found = resolvePath(url, options);
    if (!found) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found'); return; }
    if (found.redirect) { res.writeHead(301, { Location: url.split('?')[0] + '/' }).end(); return; }
    const headers = {
      'Content-Type': TYPES[extname(found.file)] ?? 'application/octet-stream',
      'Accept-Ranges': 'bytes', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff',
    };
    let status = 200, start = 0, end = found.size - 1;
    if (req.headers.range) {
      const range = parseRange(req.headers.range, found.size);
      if (!range) { res.writeHead(416, { 'Content-Range': `bytes */${found.size}` }).end(); return; }
      ({ start, end } = range); status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${found.size}`;
    }
    headers['Content-Length'] = found.size === 0 ? 0 : end - start + 1;
    res.writeHead(status, headers);
    if (req.method === 'HEAD' || found.size === 0) { res.end(); return; }
    createReadStream(found.file, { start, end }).pipe(res);
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const port = Number(process.env.PORT ?? 3000);
  createServer(handler()).listen(port, '127.0.0.1', () => {
    console.log(`FEEL site on http://127.0.0.1:${port}  ·  replay: http://127.0.0.1:${port}/replay`);
    console.log(`Replay data from ${DATA} (run python3 simulation/run.py to refresh)`);
  });
}

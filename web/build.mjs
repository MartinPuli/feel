// Static build for deployment: web/public plus the replay sessions that may be published.
// Synthetic sessions are always included. Phone recordings (camera video of real places and people)
// are included only when their scenario sets "publish": true. Everything else stays on this machine.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const dist = resolve(here, 'dist');
const data = resolve(here, '..', 'simulation', 'out', 'web');

rmSync(dist, { recursive: true, force: true });
cpSync(resolve(here, 'public'), dist, { recursive: true });
const target = join(dist, 'replay', 'data');
mkdirSync(join(target, 'sessions'), { recursive: true });

const index = existsSync(join(data, 'index.json')) ? JSON.parse(readFileSync(join(data, 'index.json'), 'utf8')) : { sessions: [] };
const published = index.sessions.filter(s => s.publish === true);
for (const session of published) cpSync(join(data, 'sessions', session.name), join(target, 'sessions', session.name), { recursive: true });
writeFileSync(join(target, 'index.json'), JSON.stringify({ ...index, sessions: published }, null, 1) + '\n');
if (existsSync(join(data, 'unit-tests.json'))) cpSync(join(data, 'unit-tests.json'), join(target, 'unit-tests.json'));
if (existsSync(join(data, 'pin-diagnostics.json'))) cpSync(join(data, 'pin-diagnostics.json'), join(target, 'pin-diagnostics.json'));

const withheld = index.sessions.length - published.length;
console.log(`dist/ ready: ${published.length} replay session(s)` + (withheld ? `, ${withheld} phone recording(s) withheld (set "publish": true to include)` : ''));
if (!index.sessions.length) console.log('No replay data found. Run python3 simulation/run.py first.');

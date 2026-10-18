// Static deployment includes only explicitly publishable sessions and software reports.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const pick = (value, keys) => Object.fromEntries(keys.filter(k => value?.[k] !== undefined).map(k => [k, value[k]]));

// Raw test errors can contain local paths or test payloads. Never publish them.
export function publicReport(report, kind) {
  const output = pick(report, ['generatedAt', 'status', 'total', 'passed', 'failed', 'skipped']);
  if (kind === 'unit-tests') {
    output.suites = (report.suites || []).map(suite => ({
      ...pick(suite, ['name', 'total', 'passed', 'failed', 'skipped']),
      tests: (suite.tests || []).map(test => pick(test, ['name', 'status'])),
    }));
  } else {
    output.hardware = 'UNVERIFIED';
    output.cases = (report.cases || []).map(check => pick(check, [
      'label', 'slot', 'gpio', 'expectedBand', 'actualBands', 'actualAngleDeg',
      'actualPulseUs', 'status', 'firstFailure', 'packetHex',
    ]));
  }
  return output;
}

export function build({ dist = resolve(here, 'dist'), data = resolve(here, '..', 'simulation', 'out', 'web'), publicDir = resolve(here, 'public') } = {}) {
  rmSync(dist, { recursive: true, force: true });
  cpSync(publicDir, dist, { recursive: true });
  const target = join(dist, 'replay', 'data');
  mkdirSync(join(target, 'sessions'), { recursive: true });
  const index = existsSync(join(data, 'index.json')) ? JSON.parse(readFileSync(join(data, 'index.json'), 'utf8')) : { sessions: [] };
  const published = index.sessions.filter(s => s.publish === true);
  for (const session of published) {
    if (!/^[a-zA-Z0-9_-]+$/.test(session.name)) throw new Error('Invalid published session name');
    cpSync(join(data, 'sessions', session.name), join(target, 'sessions', session.name), { recursive: true });
  }
  writeFileSync(join(target, 'index.json'), JSON.stringify({ ...index, sessions: published }, null, 1) + '\n');
  for (const kind of ['unit-tests', 'pin-diagnostics']) {
    const source = join(data, `${kind}.json`);
    if (existsSync(source)) writeFileSync(join(target, `${kind}.json`), JSON.stringify(publicReport(JSON.parse(readFileSync(source, 'utf8')), kind), null, 1) + '\n');
  }
  const withheld = index.sessions.length - published.length;
  console.log(`dist/ ready: ${published.length} replay session(s)` + (withheld ? `, ${withheld} recording(s) withheld (set "publish": true to include)` : ''));
  if (!index.sessions.length) console.log('No replay data found. Run python3 simulation/run.py first.');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) build();

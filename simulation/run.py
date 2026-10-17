#!/usr/bin/env python3
"""Replay labelled depth recordings through the production Swift encoder and the production
C++ firmware controller, then score the commanded pin grid against the labels over time.

Inputs are scenarios in simulation/scenarios/: a synthetic scene (rendered deterministically)
or a .feelrec recorded on the iPhone, plus labelled expectations. Outputs go to
simulation/out/: one timeline per scenario, summary.json and report.html.

Not modelled: servo torque, lag or friction, tactile feel, BLE radio, the object detector
(recorded or synthetic detections are replayed), point-to-describe and direction arrows.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import random
import struct
import subprocess
import sys
import time
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIM = ROOT / 'simulation'
PACKAGE = ROOT / 'ios/Shared/FeelCore'
REPLAY = PACKAGE / '.build/release/feel-replay'
FIRMWARE = ROOT / 'firmware'
FEEL_SIM = FIRMWARE / 'build/feel-sim'
WATCHED = [PACKAGE / 'Sources', FIRMWARE / 'src', FIRMWARE / 'include', FIRMWARE / 'host', SIM / 'scenarios', SIM / 'recordings']
MS_OFFSET = 1000  # firmware clock = 1 s + scenario time, so CONNECT precedes every packet


# ---------------------------------------------------------------- build

def build(quiet=False):
    out = subprocess.DEVNULL if quiet else None
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'feel-replay', '--package-path', str(PACKAGE)],
                   check=True, stdout=out)
    FEEL_SIM.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['c++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-Wpedantic', '-O2',
                    '-I', str(FIRMWARE / 'include'), str(FIRMWARE / 'src/controller.cpp'),
                    str(FIRMWARE / 'src/commands.cpp'), str(FIRMWARE / 'host/simulator.cpp'),
                    '-o', str(FEEL_SIM)], check=True)


# ---------------------------------------------------------------- recording reader (for the report)

def read_recording(path: Path):
    """Yield (header, depths, confidence) per frame; depths is None without usable depth."""
    data = path.read_bytes()
    if data[:8] != b'FEELREC1':
        raise ValueError(f'{path}: not a .feelrec file')
    offset = 8

    def block():
        nonlocal offset
        (length,) = struct.unpack_from('<I', data, offset)
        start = offset + 4
        offset = start + length
        if offset > len(data):
            raise ValueError(f'{path}: truncated')
        return data[start:offset]

    info = json.loads(block()); block()
    frames = []
    while offset < len(data):
        header = json.loads(block())
        payload = block()
        depths = confidence = None
        if header.get('width'):
            n = header['width'] * header['height']
            depths = array('f'); depths.frombytes(payload[:4 * n])
            if sys.byteorder != 'little':
                depths.byteswap()
            confidence = payload[4 * n:]
        frames.append((header, depths, confidence))
    return info, frames


def thumbnails(frames, step=4, max_range=5.0):
    """Downsampled depth images for the report: 0 = no usable depth, 1–255 = near → far."""
    out = {}
    for header, depths, confidence in frames:
        if depths is None:
            continue
        w, h = header['width'], header['height']
        pixels = bytearray()
        for y in range(0, h, step):
            for x in range(0, w, step):
                i = y * w + x
                d = depths[i]
                pixels.append(0 if confidence[i] == 0 or not d > 0 else max(1, min(255, round(d / max_range * 255))))
        k = header['intrinsics']
        out[f"{header['t']:.3f}"] = {'w': (w + step - 1) // step, 'h': (h + step - 1) // step,
                                     'fx': k['fx'] / step, 'cx': k['cx'] / step, 'px': base64.b64encode(bytes(pixels)).decode()}
    return out


# ---------------------------------------------------------------- firmware peer

class Firmware:
    def __init__(self):
        self.process = subprocess.Popen([str(FEEL_SIM)], text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1)

    def ask(self, line):
        self.process.stdin.write(line + '\n'); self.process.stdin.flush()
        response = self.process.stdout.readline()
        if not response:
            raise RuntimeError('feel-sim exited')
        return json.loads(response)

    def close(self):
        self.process.stdin.close(); self.process.wait(timeout=5)


def dropped(t, faults, rng):
    for window in faults.get('packetLoss', []):
        if window['from'] <= t < window['to'] and rng.random() < window.get('rate', 1.0):
            return True
    return False


# ---------------------------------------------------------------- scoring

def columns_of(spec):
    return list(range(7)) if spec in (None, 'all') else list(spec)


def check_tick(expect, tick):
    """Return (checks, failures) for one expectation at one tick. A failure is (column|None, wanted, got)."""
    checks, failures = 0, []
    source = tick['firmware'] if expect.get('source', 'firmware') == 'firmware' else tick['phone']
    if 'band' in expect or 'bands' in expect:
        allowed = expect['bands'] if 'bands' in expect else [expect['band']]
        for c in columns_of(expect.get('columns')):
            checks += 1
            if source['bands'][c] not in allowed:
                failures.append((c, allowed, source['bands'][c]))
    if 'highlight' in expect:
        want = 255 if expect['highlight'] is None else expect['highlight']
        checks += 1
        if source['highlight'] != want:
            failures.append((None, f'highlight {expect["highlight"]}', None if source['highlight'] == 255 else source['highlight']))
    if 'state' in expect:
        checks += 1
        if tick['phone']['state'] != expect['state']:
            failures.append((None, f'state {expect["state"]}', tick['phone']['state']))
    return checks, failures


def score(scenario, ticks):
    expects = scenario.get('expect', [])
    rules = {'minAccuracy': 0.95, **scenario.get('pass', {})}
    total = passed = phantom = missed = 0
    per_expect = []
    for index, expect in enumerate(expects):
        lo, hi = expect['from'] + expect.get('grace', 0), expect['to']
        e_total = e_pass = 0
        first_ok = None
        for tick in ticks:
            if not lo <= tick['t'] <= hi:
                continue
            checks, failures = check_tick(expect, tick)
            e_total += checks; e_pass += checks - len(failures)
            if not failures and first_ok is None:
                first_ok = tick['t']
            for column, allowed, got in failures:
                tick.setdefault('mismatch', []).append({'expect': index, 'column': column, 'want': allowed, 'got': got})
                if column is not None:
                    if got and all(a == 0 for a in allowed):
                        phantom += 1
                    if got == 0 and all(a > 0 for a in allowed):
                        missed += 1
        total += e_total; passed += e_pass
        per_expect.append({'index': index, 'label': expect.get('label', ''), 'from': expect['from'], 'to': expect['to'],
                           'checks': e_total, 'passed': e_pass, 'accuracy': round(e_pass / e_total, 4) if e_total else None,
                           'firstMatch': None if first_ok is None else round(first_ok - expect['from'], 3)})
    # Flicker counts only changes between two live ticks, so going neutral on a fault is not flicker.
    live = [(a, b) for a, b in zip(ticks, ticks[1:]) if a['phone']['state'] == b['phone']['state'] == 'live' and not a['dropped'] and not b['dropped']]
    changes = sum(1 for a, b in live for c in range(7) if a['firmware']['bands'][c] != b['firmware']['bands'][c])
    live_seconds = sum(b['t'] - a['t'] for a, b in live) or 1e-9
    ages = [t['t'] - t['phone']['frame'] for t in ticks if t['phone']['frame'] is not None and t['phone']['state'] == 'live']
    accuracy = passed / total if total else None
    flicker = changes / 7 / live_seconds if live else 0.0
    reasons = []
    if total == 0:
        reasons.append('no labelled checks fell inside the timeline')
    # Every labelled window must agree on its own; a short tap dropout must not hide behind many wall checks.
    for e in per_expect:
        if e['accuracy'] is not None and e['accuracy'] < rules['minAccuracy']:
            reasons.append(f"window {e['from']}–{e['to']} s{' (' + e['label'] + ')' if e['label'] else ''}: {e['accuracy']:.3f} < {rules['minAccuracy']}")
    if 'maxFlicker' in rules and flicker > rules['maxFlicker']:
        reasons.append(f'flicker {flicker:.2f}/s > {rules["maxFlicker"]}')
    return {
        'accuracy': None if accuracy is None else round(accuracy, 4), 'checks': total, 'failedChecks': total - passed,
        'phantomChecks': phantom, 'missedChecks': missed,
        'bandChangesPerColumnSecond': round(flicker, 3),
        # Modelled: simulated tick phase plus delivery latency, not a phone measurement.
        'frameAgeMs': {'mean': round(1000 * sum(ages) / len(ages), 1), 'max': round(1000 * max(ages), 1)} if ages else None,
        'expectations': per_expect, 'passed': not reasons, 'reasons': reasons,
    }


# ---------------------------------------------------------------- one scenario

def run_scenario(path: Path, out_dir: Path):
    scenario = json.loads(path.read_text())
    name = path.stem
    work = out_dir / name
    work.mkdir(parents=True, exist_ok=True)
    if 'recording' in scenario:
        recording = (path.parent / scenario['recording']).resolve()
        if not recording.exists():
            return {'name': name, 'title': scenario.get('title', name), 'skipped': f'recording not found: {scenario["recording"]}'}
    else:
        recording = work / 'scene.feelrec'
        subprocess.run([str(REPLAY), 'synth', str(path), str(recording)], check=True)
    replay = scenario.get('replay', {})
    flags = []
    for key, flag in (('tickOffset', '--tick-offset'), ('latency', '--latency'), ('tail', '--tail')):
        if key in replay:
            flags += [flag, str(replay[key])]
    lines = subprocess.run([str(REPLAY), 'session', str(recording), *flags], check=True, capture_output=True, text=True).stdout.splitlines()
    phone_ticks = [json.loads(line) for line in lines]

    faults = scenario.get('faults', {})
    rng = random.Random(faults.get('seed', 1))
    firmware = Firmware()
    try:
        firmware.ask(f'RESET {MS_OFFSET - 1}')
        firmware.ask(f'CONNECT {MS_OFFSET - 1}')
        ticks = []
        for phone in phone_ticks:
            ms = MS_OFFSET + round(phone['t'] * 1000)
            lost = dropped(phone['t'], faults, rng)
            state = firmware.ask(f'TICK {ms}' if lost else 'PACKET ' + str(ms) + ' ' + ' '.join(str(b) for b in bytes.fromhex(phone['hex'])))
            if not lost and state['result'] != 'ok':
                raise AssertionError(f'{name}: firmware rejected a phone packet at t={phone["t"]}: {state["result"]}')
            ticks.append({'t': round(phone['t'], 3), 'phone': phone, 'dropped': lost,
                          'firmware': {k: state[k] for k in ('bands', 'highlight', 'tap_active', 'active', 'angles_deg')}})
    finally:
        firmware.close()

    result = score(scenario, ticks)
    digest = hashlib.sha256(json.dumps([[t['phone']['hex'], t['firmware']['bands'], t['firmware']['highlight']] for t in ticks]).encode()).hexdigest()[:16]
    with (work / 'timeline.jsonl').open('w') as f:
        for tick in ticks:
            f.write(json.dumps(tick, sort_keys=True) + '\n')
    info, frames = read_recording(recording)
    return {'name': name, 'title': scenario.get('title', name), 'description': scenario.get('description', ''),
            'source': info.get('source'), 'knownIssue': scenario.get('knownIssue'), 'digest': digest,
            'result': result, 'expect': scenario.get('expect', []), 'faults': faults,
            'ticks': [{'t': t['t'], 'fw': t['firmware']['bands'], 'hl': t['firmware']['highlight'], 'tap': t['firmware']['tap_active'],
                       'state': t['phone']['state'], 'frame': t['phone']['frame'], 'dist': t['phone']['distances'],
                       'target': t['phone'].get('target'), 'dropped': t['dropped'], 'mismatch': t.get('mismatch', [])} for t in ticks],
            'thumbs': thumbnails(frames)}


# ---------------------------------------------------------------- baselines, report, main

def compare_baseline(entry, baselines: Path, update: bool):
    path = baselines / f"{entry['name']}.json"
    current = {'digest': entry['digest'], 'fw': [t['fw'] for t in entry['ticks']], 'hl': [t['hl'] for t in entry['ticks']]}
    if update:
        path.write_text(json.dumps(current, separators=(',', ':')) + '\n')
        return 'updated'
    if not path.exists():
        return 'none'
    old = json.loads(path.read_text())
    if old['digest'] == current['digest']:
        return 'same'
    for i, (a, b) in enumerate(zip(old['fw'], current['fw'])):
        if a != b or old['hl'][i] != current['hl'][i]:
            return f"changed from t={entry['ticks'][i]['t']}"
    return 'changed (length)'


def status(entry):
    if 'skipped' in entry:
        return 'SKIP'
    if entry['result']['passed']:
        return 'PASS'
    return 'KNOWN' if entry.get('knownIssue') else 'FAIL'


def write_report(entries, out_dir: Path):
    template = (SIM / 'report.html').read_text()
    payload = json.dumps({'generated': time.strftime('%Y-%m-%d %H:%M:%S'), 'scenarios': entries}, separators=(',', ':'))
    (out_dir / 'report.html').write_text(template.replace('/*DATA*/null', payload.replace('</', '<\\/')))


def run_all(args):
    paths = [Path(p).resolve() for p in args.scenarios] if args.scenarios else sorted((SIM / 'scenarios').glob('*.json'))
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    baselines = SIM / 'baselines'
    baselines.mkdir(exist_ok=True)
    entries, failed = [], False
    for path in paths:
        digests = set()
        entry = None
        for _ in range(args.repeat):
            entry = run_scenario(path, out_dir)
            if 'skipped' in entry:
                break
            digests.add(entry['digest'])
        if 'skipped' not in entry:
            entry['deterministic'] = len(digests) == 1
            entry['baseline'] = compare_baseline(entry, baselines, args.update_baselines)
            if not entry['deterministic']:
                failed = True
        s = status(entry)
        failed |= s == 'FAIL'
        if 'skipped' in entry:
            print(f'SKIP   {entry["name"]}: {entry["skipped"]}')
        else:
            r = entry['result']
            lat = r['frameAgeMs']
            print(f"{s:<6} {entry['name']:<28} accuracy {r['accuracy'] if r['accuracy'] is not None else '-':<7} "
                  f"phantom {r['phantomChecks']:<4} missed {r['missedChecks']:<4} changes/col/s {r['bandChangesPerColumnSecond']:<6} "
                  f"frame age {lat['mean'] if lat else '-'} ms  baseline {entry['baseline']}"
                  + ('' if entry['deterministic'] else '  NONDETERMINISTIC'))
            for reason in r['reasons']:
                print(f'         {reason}' + (f"  (known issue: {entry['knownIssue']})" if s == 'KNOWN' else ''))
        entries.append(entry)
    summary = [{k: e.get(k) for k in ('name', 'title', 'source', 'knownIssue', 'digest', 'deterministic', 'baseline', 'skipped')}
               | ({'status': status(e)}) | ({'result': e['result']} if 'result' in e else {}) for e in entries]
    (out_dir / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    write_report(entries, out_dir)
    print(f'Report: {out_dir / "report.html"}')
    return not failed


def snapshot():
    return {p: p.stat().st_mtime for root in WATCHED if root.exists() for p in root.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('scenarios', nargs='*', help='scenario JSON files (default: simulation/scenarios/*.json)')
    parser.add_argument('--out', default=str(SIM / 'out'))
    parser.add_argument('--no-build', action='store_true', help='use existing feel-replay and feel-sim binaries')
    parser.add_argument('--repeat', type=int, default=1, help='run each scenario N times and require identical output')
    parser.add_argument('--update-baselines', action='store_true', help='store this run as the regression baseline')
    parser.add_argument('--watch', action='store_true', help='rebuild and rerun whenever sources, scenarios or recordings change')
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error('--repeat must be at least 1')
    if not args.watch:
        if not args.no_build:
            build()
        sys.exit(0 if run_all(args) else 1)
    seen = None
    while True:
        current = snapshot()
        if current != seen:
            seen = current
            print(time.strftime('\n[%H:%M:%S] change detected, rebuilding'))
            try:
                build(quiet=True)
                run_all(args)
            except (subprocess.CalledProcessError, AssertionError, ValueError) as error:
                print(f'Run failed: {error}')
            seen = snapshot()
        time.sleep(2)


if __name__ == '__main__':
    main()

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
import re
import shutil
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
ACTIVE_COLUMNS = tuple(range(1, 7))  # Six physical columns; wire slot b0 stays reserved.
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
                                     'fx': k['fx'] / step, 'cx': k['cx'] / step, 'fy': k['fy'] / step, 'cy': k['cy'] / step,
                                     'px': base64.b64encode(bytes(pixels)).decode()}
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
    columns = list(ACTIVE_COLUMNS) if spec in (None, 'all') else list(spec)
    if not columns or len(set(columns)) != len(columns) or any(type(c) is not int or c not in ACTIVE_COLUMNS for c in columns):
        raise ValueError('Label physical wire slots 1 through 6; b0 is checked by the reserved-slot invariant')
    return columns


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


def score(scenario, ticks, base=0.0):
    """Label times are seconds from the recording's first frame (`base`, 0 for synthetic scenes)."""
    expects = scenario.get('expect', [])
    rules = {'minAccuracy': 0.95, **scenario.get('pass', {})}
    total = passed = phantom = missed = 0
    per_expect = []
    for index, expect in enumerate(expects):
        lo, hi = base + expect['from'] + expect.get('grace', 0), base + expect['to']
        e_total = e_pass = 0
        first_ok = None
        for tick in ticks:
            if not lo <= tick['t'] <= hi:
                continue
            checks, failures = check_tick(expect, tick)
            e_total += checks; e_pass += checks - len(failures)
            if not failures and first_ok is None:
                first_ok = tick['t'] - base
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
    changes = sum(1 for a, b in live for c in ACTIVE_COLUMNS if a['firmware']['bands'][c] != b['firmware']['bands'][c])
    live_seconds = sum(b['t'] - a['t'] for a, b in live) or 1e-9
    ages = [t['t'] - t['phone']['frame'] for t in ticks if t['phone']['frame'] is not None and t['phone']['state'] == 'live']
    accuracy = passed / total if total else None
    flicker = changes / len(ACTIVE_COLUMNS) / live_seconds if live else 0.0
    reasons = []
    reserved_violations = 0
    for tick in ticks:
        for source in ('phone', 'firmware'):
            if tick[source]['bands'][0] != 0 or tick[source]['highlight'] == 0:
                reserved_violations += 1
                tick.setdefault('mismatch', []).append({'expect': 'reserved-slot', 'column': 0,
                    'want': 'b0=0 and no highlight', 'got': source})
    if reserved_violations:
        reasons.append(f'reserved wire slot b0 activated in {reserved_violations} phone/firmware states')
    if total == 0 and expects:
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
        'reservedSlotViolations': reserved_violations,
        # Modelled: simulated tick phase plus delivery latency, not a phone measurement.
        'frameAgeMs': {'mean': round(1000 * sum(ages) / len(ages), 1), 'max': round(1000 * max(ages), 1)} if ages else None,
        'expectations': per_expect, 'passed': not reasons, 'reasons': reasons,
    }


# ---------------------------------------------------------------- one scenario

def run_scenario(path: Path, out_dir: Path, camera: bool = False):
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
        extra = ['--camera', str(work / 'camera.cam')] if camera else []
        subprocess.run([str(REPLAY), 'synth', str(path), str(recording), *extra], check=True)
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

    info, frames = read_recording(recording)
    result = score(scenario, ticks, base=frames[0][0]['t'] if frames else 0.0)
    digest = hashlib.sha256(json.dumps([[t['phone']['hex'], t['firmware']['bands'], t['firmware']['highlight']] for t in ticks]).encode()).hexdigest()[:16]
    with (work / 'timeline.jsonl').open('w') as f:
        for tick in ticks:
            f.write(json.dumps(tick, sort_keys=True) + '\n')
    return {'name': name, 'title': scenario.get('title', name), 'description': scenario.get('description', ''),
            'source': info.get('source'), 'knownIssue': scenario.get('knownIssue'), 'digest': digest,
            'result': result, 'expect': scenario.get('expect', []), 'faults': faults,
            'ticks': [{'t': t['t'], 'fw': t['firmware']['bands'], 'hl': t['firmware']['highlight'], 'tap': t['firmware']['tap_active'],
                       'state': t['phone']['state'], 'frame': t['phone']['frame'], 'dist': t['phone']['distances'],
                       'target': t['phone'].get('target'), 'dropped': t['dropped'], 'mismatch': t.get('mismatch', [])} for t in ticks],
            'thumbs': thumbnails(frames),
            # Not serialised: inputs for the web export.
            '_assets': {'recording': recording, 'frames': frames, 'scenario': path, 'camera': work / 'camera.cam' if camera and 'recording' not in scenario else None,
                        'frameRate': scenario.get('scene', {}).get('frameRate', 10),
                        'publish': info.get('source') == 'synthetic' or scenario.get('publish') is True}}


# ---------------------------------------------------------------- web export (/replay viewer)

def encode_camera(cam: Path, mp4: Path, fps: float):
    """Synthetic camera frames (FEELCAM1) → H.264 MP4 at the scene frame rate; video time 0 = scene time 0."""
    data = cam.read_bytes()
    if data[:8] != b'FEELCAM1':
        raise ValueError(f'{cam}: not a camera file')
    w, h = struct.unpack_from('<II', data, 8)
    size = w * h * 3
    raw = b''.join(data[16 + i * (8 + size) + 8: 16 + (i + 1) * (8 + size)] for i in range((len(data) - 16) // (8 + size)))
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', str(fps), '-i', '-',
                    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(mp4)],
                   input=raw, check=True)
    cam.unlink()


def export_web(entry, out_dir: Path):
    """Write sessions/<name>/{session.json, meta.json, camera.mp4} for the /replay page."""
    assets = entry['_assets']
    session_dir = out_dir / 'web' / 'sessions' / entry['name']
    if session_dir.exists():
        shutil.rmtree(session_dir)
    # The run before this one becomes the "previous" snapshot, so /replay can compare without planning ahead.
    latest = out_dir / 'web' / 'snapshots' / '_latest' / f"{entry['name']}.json"
    if latest.exists():
        previous = out_dir / 'web' / 'snapshots' / 'previous' / latest.name
        previous.parent.mkdir(parents=True, exist_ok=True)
        latest.replace(previous)
    session_dir.mkdir(parents=True)
    media = None
    recording = assets['recording']
    sidecar = recording.with_suffix('.video.json')
    if assets['camera'] and assets['camera'].exists():
        if shutil.which('ffmpeg'):
            encode_camera(assets['camera'], session_dir / 'camera.mp4', assets['frameRate'])
            media = {'url': 'camera.mp4', 'start': 0.0, 'kind': 'rendered'}
        else:
            assets['camera'].unlink()
    elif sidecar.exists():
        timing = json.loads(sidecar.read_text())
        video = recording.parent / timing['video']
        if video.exists():
            shutil.copyfile(video, session_dir / 'camera.mp4')
            media = {'url': 'camera.mp4', 'start': timing['start'], 'kind': 'recorded'}
    events_file = recording.with_suffix('.events.json')
    events = json.loads(events_file.read_text()).get('events', []) if events_file.exists() else []
    frames = assets['frames']
    # 128 × 96 depth for short sessions; coarser for long phone walks to keep the page loadable.
    step = 2 if len(frames) <= 900 else 4
    thumbs = thumbnails(frames, step=step)
    first = next(iter(thumbs.values()), None)
    depth = {'w': first['w'], 'h': first['h'], 'fxn': first['fx'] / first['w'], 'cxn': first['cx'] / first['w'],
             'fx': first['fx'], 'fy': first['fy'], 'cx': first['cx'], 'cy': first['cy'], 'maxRange': 5.0,
             'frames': {t: v['px'] for t, v in thumbs.items()}} if first else None
    # Camera pose per frame for the top-down view: position, right, up, back (world, metres), floor height.
    def vec(v):
        return [round(v['x'], 4), round(v['y'], 4), round(v['z'], 4)]
    poses = {f"{h['t']:.3f}": vec(h['pose']['position']) + vec(h['pose']['right']) + vec(h['pose']['up']) + vec(h['pose']['back'])
             + [h.get('floorY')] for h, _, _ in frames}
    scenario = json.loads(entry['_assets']['scenario'].read_text())
    scene = {k: scenario['scene'][k] for k in ('objects', 'target') if k in scenario['scene']} if 'scene' in scenario else None
    ticks = entry['ticks']
    meta = {'name': entry['name'], 'title': entry['title'], 'source': entry['source'], 'status': status(entry),
            'knownIssue': entry.get('knownIssue'), 'publish': assets['publish'],
            'duration': round(ticks[-1]['t'] - ticks[0]['t'], 2) if ticks else 0,
            'accuracy': entry['result']['accuracy'], 'hasVideo': media is not None, 'start': frames[0][0]['t'] if frames else 0,
            'bumps': sum(1 for e in events if e.get('kind') == 'bump'),
            'outcome': next((e['kind'] for e in reversed(events) if e.get('kind') in ('arrived', 'ended', 'stopped')), None)}
    session = {**meta, 'description': entry['description'], 'result': entry['result'], 'expect': entry['expect'],
               'faults': entry['faults'], 'ticks': ticks, 'depth': depth, 'media': media, 'poses': poses, 'scene': scene, 'events': events}
    (session_dir / 'session.json').write_text(json.dumps(session, separators=(',', ':')))
    (session_dir / 'meta.json').write_text(json.dumps(meta, indent=1) + '\n')


def write_web_index(out_dir: Path):
    sessions = []
    for meta in sorted((out_dir / 'web' / 'sessions').glob('*/meta.json')):
        sessions.append(json.loads(meta.read_text()))
    sessions.sort(key=lambda m: (m['source'] != 'iphone', m['title'].lower()))
    (out_dir / 'web' / 'index.json').write_text(json.dumps({'generated': time.strftime('%Y-%m-%d %H:%M:%S'), 'sessions': sessions}, indent=1) + '\n')


# ---------------------------------------------------------------- snapshots (before/after compare on /replay)

SNAPSHOT_TICK_KEYS = ('t', 'fw', 'hl', 'tap', 'state', 'dropped')


def git_revision():
    """Short commit, with a trailing + when tracked files are modified. None outside git."""
    try:
        rev = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        return rev + ('+' if dirty else '')
    except (OSError, subprocess.CalledProcessError):
        return None


def write_snapshots(entries, out_dir: Path, label: str | None):
    """Save the commanded pins of this run under snapshots/<label>/ (and always under _latest/, which
    becomes previous/ on the next run). /replay lists every snapshot that has the open session."""
    generated, commit = time.strftime('%Y-%m-%d %H:%M:%S'), git_revision()
    labels = ['_latest'] + ([label] if label else [])
    for entry in entries:
        if 'skipped' in entry:
            continue
        ticks = [{k: t[k] for k in SNAPSHOT_TICK_KEYS if k in t} | {'dist': [None if d is None else round(d, 2) for d in t['dist']]}
                 for t in entry['ticks']]
        for name in labels:
            body = {'name': entry['name'], 'title': entry['title'], 'label': name, 'generated': generated, 'commit': commit,
                    'status': status(entry), 'accuracy': entry['result']['accuracy'],
                    'bandChangesPerColumnSecond': entry['result']['bandChangesPerColumnSecond'], 'ticks': ticks}
            path = out_dir / 'web' / 'snapshots' / name / f"{entry['name']}.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(body, separators=(',', ':')))
    index = []
    for folder in sorted((out_dir / 'web' / 'snapshots').glob('*/')):
        if folder.name.startswith('_'):
            continue
        files = sorted(folder.glob('*.json'))
        if not files:
            continue
        newest = max(files, key=lambda f: f.stat().st_mtime)
        head = json.loads(newest.read_text())
        index.append({'label': folder.name, 'generated': head.get('generated'), 'commit': head.get('commit'), 'sessions': [f.stem for f in files]})
    index.sort(key=lambda s: (s['label'] != 'previous', s['generated'] or ''), reverse=False)
    (out_dir / 'web' / 'snapshots' / 'index.json').write_text(json.dumps({'snapshots': index}, indent=1) + '\n')
    if label:
        print(f'Snapshot "{label}" saved: compare against it from the /replay page after your next run')


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
    if entry['result'].get('reservedSlotViolations', 0):
        return 'FAIL'  # A perception exception never waives the hardware-layout invariant.
    if not entry.get('expect'):
        return 'UNLABELLED'
    if entry['result']['passed']:
        return 'PASS'
    return 'KNOWN' if entry.get('knownIssue') else 'FAIL'


def write_report(entries, out_dir: Path):
    template = (SIM / 'report.html').read_text()
    public = [{k: v for k, v in e.items() if not k.startswith('_')} for e in entries]
    payload = json.dumps({'generated': time.strftime('%Y-%m-%d %H:%M:%S'), 'scenarios': public}, separators=(',', ':'))
    (out_dir / 'report.html').write_text(template.replace('/*DATA*/null', payload.replace('</', '<\\/')))


def auto_scenarios(out_dir: Path):
    """An unlabelled scenario for every phone recording in simulation/recordings/ that no scenario names yet."""
    named = set()
    for path in (SIM / 'scenarios').glob('*.json'):
        scenario = json.loads(path.read_text())
        if 'recording' in scenario:
            named.add((path.parent / scenario['recording']).resolve())
    auto_dir = out_dir / 'auto-scenarios'
    if auto_dir.exists():
        shutil.rmtree(auto_dir)
    auto_dir.mkdir(parents=True)
    paths = []
    for recording in sorted((SIM / 'recordings').glob('*.feelrec')):
        if recording.resolve() in named:
            continue
        stamp = recording.stem.removeprefix('feel-').replace('T', ' ').rstrip('Z')
        path = auto_dir / f'{recording.stem}.json'
        path.write_text(json.dumps({'title': f'Walk {stamp}', 'recording': str(recording.resolve()),
                                    'description': 'Phone recording, not labelled yet. Add a scenario in simulation/scenarios/ to label it.'}))
        paths.append(path)
    return paths


def run_all(args):
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = [Path(p).resolve() for p in args.scenarios] if args.scenarios else sorted((SIM / 'scenarios').glob('*.json')) + auto_scenarios(out_dir)
    baselines = SIM / 'baselines'
    baselines.mkdir(exist_ok=True)
    entries, failed = [], False
    for path in paths:
        digests = set()
        entry = None
        for attempt in range(args.repeat):
            # Render the synthetic camera view only once, on the final run.
            entry = run_scenario(path, out_dir, camera=not args.no_web and attempt == args.repeat - 1)
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
        if not args.no_web and 'skipped' not in entry:
            export_web(entry, out_dir)
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
    if not args.no_web:
        write_snapshots(entries, out_dir, args.snapshot)
        write_web_index(out_dir)
        print('Replay page: cd web && npm run dev, then open http://127.0.0.1:3000/replay')
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
    parser.add_argument('--no-web', action='store_true', help='skip the /replay web bundles (camera video and depth frames)')
    parser.add_argument('--snapshot', metavar='LABEL', help='also save this run\'s pin timelines as a named snapshot, '
                        'so /replay can show it beside a later run of the same recording (the last run is always kept as "previous")')
    parser.add_argument('--watch', action='store_true', help='rebuild and rerun whenever sources, scenarios or recordings change')
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error('--repeat must be at least 1')
    if args.snapshot is not None:
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,40}', args.snapshot) or args.snapshot == 'previous':
            parser.error('--snapshot LABEL: letters, digits, . _ -, up to 41 characters, and not "previous" (that name is kept for the last run)')
        if args.no_web:
            parser.error('--snapshot needs the web output; drop --no-web')
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

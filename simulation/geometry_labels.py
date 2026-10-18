#!/usr/bin/env python3
"""Derive labelled windows for a synthetic scenario from its geometry, before it is run.

For every 10 Hz tick this samples the surfaces of the scene's objects (box faces, cylinder sides and
caps) inside the obstacle height window, keeps the points the iPhone wide camera can see (±33.6° by
±26.5°), and takes the nearest horizontal range per column, exactly the sector rule the encoder uses
(nearest point, 0.6–2.1 m above the floor, within 4 m, seven 12.86° columns). Runs of a constant band
per column become `expect` windows with ±0.35 s trimmed around every transition, so a label never sits
on a tick where the answer changes. Occlusion is ignored: a nearer surface always wins the column, so
hiding a farther one changes nothing.

    python3 simulation/geometry_labels.py simulation/scenarios/hallway-cluttered.json           # print the windows
    python3 simulation/geometry_labels.py simulation/scenarios/hallway-cluttered.json --write   # replace "expect" in the file

Labels are therefore a statement of the geometry, not of the pipeline's output. A pass means the pins
matched the geometry; a change in the pins after a code change shows up on /replay in compare mode.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

HALF_H = math.atan(960 / 1445)  # horizontal half view of the wide camera, radians (33.6°)
HALF_V = math.atan(720 / 1445)  # vertical half view (26.5°)
MIN_HEIGHT, MAX_HEIGHT, MAX_RANGE = 0.6, 2.1, 4.0
COLUMN_WIDTH = 90 / 7
TRIM, MIN_RUN, MIN_WINDOW = 0.35, 0.9, 0.2
STEP = 0.03  # surface sampling pitch in metres
# A tick is labelled only when its answer is robust: the band must not change under a ±4 % range
# error (noise, sampling, the 4 m cut-off) and must not rest on a sliver less than EDGE degrees wide
# at a column edge, where pixel quantisation decides which column sees it.
TOLERANCE, EDGE = 0.04, 0.7
UNCERTAIN = -1


def band(distance):
    if not distance or distance <= 0 or distance > 4:
        return 0
    return 1 if distance < 0.9 else 2 if distance < 1.6 else 3 if distance < 2.5 else 4


def column(bearing_deg):
    if bearing_deg < -45 or bearing_deg > 45:
        return None
    return 6 if bearing_deg == 45 else min(6, int((bearing_deg + 45) // COLUMN_WIDTH))


def pose(scene, t):
    keys = scene['path']
    x, z, yaw = keys[0]['x'], keys[0]['z'], keys[0].get('yaw', 0)
    if t >= keys[-1]['t']:
        x, z, yaw = keys[-1]['x'], keys[-1]['z'], keys[-1].get('yaw', 0)
    elif t > keys[0]['t']:
        i = next(i for i, k in enumerate(keys) if k['t'] > t)
        a, b = keys[i - 1], keys[i]
        u = (t - a['t']) / (b['t'] - a['t'])
        x, z = a['x'] + (b['x'] - a['x']) * u, a['z'] + (b['z'] - a['z']) * u
        yaw = a.get('yaw', 0) + (b.get('yaw', 0) - a.get('yaw', 0)) * u
    r, p = math.radians(yaw), math.radians(scene.get('pitch', 0))
    forward = (math.sin(r), 0, -math.cos(r))
    right = (math.cos(r), 0, math.sin(r))
    f = (forward[0] * math.cos(p), math.sin(p), forward[2] * math.cos(p))
    up = (-forward[0] * math.sin(p), math.cos(p), -forward[2] * math.sin(p))
    return (x, scene.get('cameraHeight', 1.2), z), right, up, f


def frange(a, b, step):
    n = max(1, int(math.ceil((b - a) / step)))
    return [a + (b - a) * i / n for i in range(n + 1)]


def surface_points(obj, t):
    """Points on the object's surface inside the height window, at time t."""
    if obj.get('from') is not None and t < obj['from'] or obj.get('to') is not None and t > obj['to']:
        return []
    v = obj.get('velocity') or [0, 0]
    s = t - (obj.get('from') or 0)
    ox, oz = v[0] * s, v[1] * s
    pts = []
    if obj['kind'] == 'box':
        lo, hi = obj['min'], obj['max']
        y0, y1 = max(lo[1], MIN_HEIGHT), min(hi[1], MAX_HEIGHT)
        if y0 > y1:
            return []
        ys = frange(y0, y1, STEP)
        xs, zs = frange(lo[0] + ox, hi[0] + ox, STEP), frange(lo[2] + oz, hi[2] + oz, STEP)
        for y in ys:
            for x in xs:
                pts += [(x, y, lo[2] + oz), (x, y, hi[2] + oz)]
            for z in zs:
                pts += [(lo[0] + ox, y, z), (hi[0] + ox, y, z)]
        if MIN_HEIGHT <= hi[1] <= MAX_HEIGHT:   # top face
            pts += [(x, hi[1], z) for x in xs for z in zs]
    else:
        cx, cz, r, h = obj['center'][0] + ox, obj['center'][1] + oz, obj['radius'], obj['height']
        base = obj.get('base', 0)
        y0, y1 = max(base, MIN_HEIGHT), min(base + h, MAX_HEIGHT)
        if y0 > y1:
            return []
        angles = [2 * math.pi * i / 90 for i in range(90)]
        for y in frange(y0, y1, STEP):
            pts += [(cx + r * math.cos(a), y, cz + r * math.sin(a)) for a in angles]
        if MIN_HEIGHT <= base + h <= MAX_HEIGHT:
            pts += [(cx + rr * math.cos(a), base + h, cz + rr * math.sin(a)) for rr in frange(0, r, STEP) for a in angles]
    return pts


def ranges_at(scene, t):
    cam, right, up, fwd = pose(scene, t)
    best = [None] * 7
    who = [None] * 7
    inner = [None] * 7      # nearest point at least EDGE degrees inside the column
    nearest_any = [None] * 7  # nearest point in the column ignoring the 4 m limit
    for obj in scene.get('objects') or []:
        for (x, y, z) in surface_points(obj, t):
            dx, dy, dz = x - cam[0], y - cam[1], z - cam[2]
            depth = dx * fwd[0] + dy * fwd[1] + dz * fwd[2]
            if depth <= 0.05:
                continue
            xc = dx * right[0] + dy * right[1] + dz * right[2]
            yc = dx * up[0] + dy * up[1] + dz * up[2]
            if abs(xc / depth) > math.tan(HALF_H) or abs(yc / depth) > math.tan(HALF_V):
                continue
            if not (MIN_HEIGHT <= y <= MAX_HEIGHT):
                continue
            # The encoder works in camera space: horizontal range and bearing from the camera's x and z.
            zc = -(dx * fwd[0] + dy * fwd[1] + dz * fwd[2])
            distance = math.hypot(xc, zc)
            bearing = math.degrees(math.atan2(xc, -zc))
            c = column(bearing)
            if c is None:
                continue
            if nearest_any[c] is None or distance < nearest_any[c]:
                nearest_any[c] = distance
            if distance > MAX_RANGE:
                continue
            if best[c] is None or distance < best[c]:
                best[c], who[c] = distance, obj.get('label') or obj['kind']
            lo, hi = -45 + c * COLUMN_WIDTH, -45 + (c + 1) * COLUMN_WIDTH
            if bearing - lo >= EDGE and hi - bearing >= EDGE and (inner[c] is None or distance < inner[c]):
                inner[c] = distance
    return best, who, inner, nearest_any


def robust_band(d, inner, nearest_any):
    """The band for this column, or UNCERTAIN when a small error could change it."""
    if d is None:
        return UNCERTAIN if nearest_any is not None and nearest_any * (1 - TOLERANCE) <= MAX_RANGE else 0
    b = band(d)
    if band(d * (1 - TOLERANCE)) != b or band(d * (1 + TOLERANCE)) != b:
        return UNCERTAIN
    if inner is None or band(inner) != b:
        return UNCERTAIN
    return b


def windows(scene, ticks=10):
    duration = scene['duration']
    times = [i / ticks for i in range(int(duration * ticks) + 1)]
    bands, names = [], []
    for t in times:
        r, w, inner, any_ = ranges_at(scene, t)
        bands.append([robust_band(r[c], inner[c], any_[c]) for c in range(7)]); names.append(w)
    entries = []
    for c in range(7):
        i = 0
        while i < len(times):
            j = i
            while j + 1 < len(times) and bands[j + 1][c] == bands[i][c]:
                j += 1
            t0, t1 = times[i], times[j]
            if bands[i][c] != UNCERTAIN and t1 - t0 >= MIN_RUN:
                a = max(0.3, t0 + TRIM) if i > 0 else max(0.3, t0)
                b = t1 - TRIM if j + 1 < len(times) else duration
                if b - a >= MIN_WINDOW:
                    mid = (i + j) // 2
                    entries.append({'from': round(a, 2), 'to': round(b, 2), 'column': c, 'band': bands[i][c], 'who': names[mid][c]})
            i = j + 1
    # Second pass for moving objects: while one object owns a column (approaching, so its band keeps
    # changing) the pin must be up in one of the bands it passes through. Only where no constant-band
    # window already covers the time.
    covered = {(e['column'], i) for e in entries for i, t in enumerate(times) if e['from'] <= t <= e['to']}
    for c in range(7):
        i = 0
        while i < len(times):
            j = i
            while j + 1 < len(times) and names[j + 1][c] == names[i][c] and bands[j + 1][c] > 0 and bands[i][c] > 0:
                j += 1
            t0, t1 = times[i], times[j]
            if bands[i][c] > 0 and t1 - t0 >= MIN_RUN:
                a, b = max(0.3, t0 + TRIM), t1 - TRIM
                inside = [k for k in range(i, j + 1) if a <= times[k] <= b]
                if b - a >= MIN_WINDOW and sum((c, k) in covered for k in inside) < len(inside) / 2:
                    seen = sorted({bands[k][c] for k in inside})
                    entries.append({'from': round(a, 2), 'to': round(b, 2), 'column': c, 'bands': seen, 'who': names[i][c]})
            i = j + 1
    merged = {}
    for e in entries:
        key = (e['from'], e['to'], e.get('band'), tuple(e.get('bands', [])), e['who'])
        merged.setdefault(key, []).append(e['column'])
    out = []
    for (a, b, bd, bds, who), cols in sorted(merged.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[1][0])):
        entry = {'from': a, 'to': b, 'columns': 'all' if len(cols) == 7 else sorted(cols)}
        if bds:
            entry['bands'] = list(bds); entry['label'] = f'{who} (bands {"/".join(map(str, bds))})'
        else:
            entry['band'] = bd; entry['label'] = 'clear' if bd == 0 else f'{who} (band {bd})'
        out.append(entry)
    return out, times, bands


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('scenario', type=Path)
    parser.add_argument('--write', action='store_true', help='replace the scenario\'s "expect" with the derived windows')
    parser.add_argument('--timeline', action='store_true', help='also print the expected band per column at every tick')
    args = parser.parse_args()
    scenario = json.loads(args.scenario.read_text())
    if 'scene' not in scenario:
        raise SystemExit('only synthetic scenarios have geometry to derive labels from')
    expect, times, bands = windows(scenario['scene'])
    if args.timeline:
        for t, b in zip(times, bands):
            print(f'{t:6.2f}  ' + ' '.join('?' if x == UNCERTAIN else str(x) if x else '.' for x in b))
    for e in expect:
        cols = e['columns'] if e['columns'] == 'all' else ','.join(map(str, e['columns']))
        what = f"band {e['band']}" if 'band' in e else 'bands ' + '/'.join(map(str, e['bands']))
        print(f"{e['from']:6.2f}–{e['to']:<6.2f} columns {cols:<14} {what:<10} {e['label']}")
    if args.write:
        scenario['expect'] = expect
        args.scenario.write_text(json.dumps(scenario, indent=2, ensure_ascii=False) + '\n')
        print(f'wrote {len(expect)} windows to {args.scenario}')


if __name__ == '__main__':
    main()

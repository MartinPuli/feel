#!/usr/bin/env python3
"""Export and verify the Pin Puck production CAD (CAD.md sections 4 and 5).

Exports every deliverable with the Manifold backend, then checks:
  0. derived parameters equal the values stated in CAD.md section 2
  1. mesh: one watertight body, positive volume, min z = 0, bounding box within 0.1 mm
  2. collision sweep: shaft/servo/chassis/guide intersections are empty at every listed angle
  3. horn insertion: horn x shaft is empty at every insertion offset
  4. cam numbers: pointed-foot simulation on the exact lobe polygon

Geometry only. Says nothing about print quality, fit of real parts, or forces.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import numpy as np

HERE = Path(__file__).resolve().parent
PUCK = HERE / 'puck.scad'
REPO = HERE.parent.parent

DELIVERABLES = {  # file stem: (qty, size mm)
    'chassis': (1, (100.5, 92.5, 26.7)),
    'guide': (1, (84.1, 56.5, 6.0)),
    'face': (1, (88.5, 92.5, 7.9)),
    'shaft': (7, (11.0, 10.9, 58.2)),
    'shaft3': (7, (11.0, 10.9, 58.2)),
    'pins': (1, (63.0, 58.0, 24.7)),
    'foam_template': (1, (11.0, 49.0, 1.2)),
    'pack_tray': (1, (71.7, 105.4, 16.0)),
}
BBOX_TOL = 0.1

DERIVED = {  # CAD.md section 2, as stated
    'z_guide_top': -11.2, 'z_guide_bot': -17.2, 'z_rod': -23.35, 'foot_rest': -20.45,
    'pin_len': 20.95, 'collar_z': 9.25, 'z_floor_top': -29.6, 'servo_body_bot': -28.15,
    'z_bottom': -31.2, 'servo_tab_y': -7.5, 'bulk_y0': -7.0, 'bulk_y1': -0.5, 'wrist_in_y': -25.5,
    'wrist_out_y': -30.5, 'far_in_y': 57.0, 'far_out_y': 62.0, 'half_w': 44.25, 'crown_yc': 34.0,
    'crown_R': 1019.7, 'screw_x': 41.25, 'screw_y0': -28.0, 'screw_y1': 59.5, 'lift': 2.85,
    'cam_max_r': 5.45, 'gap0': 29.0, 'gap1': 87.0, 'gap2': 145.0, 'pack_in_l': 101.4,
    'pack_in_w': 55.7, 'pack_out_l': 105.4, 'pack_out_w': 59.7, 'pack_y1': -48.5, 'pack_y0': -153.9,
    'foam_strip_w': 11.0,
}
# Stated values are rounded to the digits shown; crown_R to 0.1.
DERIVED_TOL = {'crown_R': 0.05}

SWEEP_ANGLES = [-5, 0, 29, 58, 87, 116, 145, 174, 180]
SHAFT_PAIRS = ['x_shaft_chassis', 'x_shaft_servo', 'x_shaft_guide', 'x_shaft_shaft']
STATIC_PAIRS = ['x_servo_chassis', 'x_servo_guide', 'x_servo_servo']
HORN_OFFSETS = [0, 1, 2, 3, 3.4]
# Coincident faces (allowed at full insertion) export as a zero-thickness shell.
TOUCH_MM3 = 1e-6

# Cam parameters, CAD.md section 2 (mirrors params.scad; DERIVED check ties lift/max_r back to it).
CAM = dict(base_r=2.6, lift=2.85, foot_clear=0.3, step=0.5, stroke=2.55)
SHAFTS = {
    'shaft': dict(rows=[0, 1, 2, 3], angles=[0, 58, 116, 174], flat=5, ramp=24),
    'shaft3': dict(rows=[0, 2, 3], angles=[0, 55, 110], flat=5, ramp=22.5),
}


# ---------------------------------------------------------------- OpenSCAD
def scad_args(part: str, **defs) -> list[str]:
    args = ['-D', f'part="{part}"']
    for k, v in defs.items():
        args += ['-D', f'{k}={v}']
    return args


def run_scad(out: Path, part: str, **defs) -> tuple[int, str]:
    cmd = ['openscad', '--backend', 'Manifold', *scad_args(part, **defs), '-o', str(out), str(PUCK)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# ---------------------------------------------------------------- mesh
def load_stl(path: Path) -> np.ndarray:
    data = path.read_bytes()
    if data[:5] == b'solid' and b'facet' in data[:512]:
        v = [l.split()[1:] for l in data.decode().splitlines() if l.lstrip().startswith('vertex')]
        return np.array(v, dtype=np.float64).reshape(-1, 3, 3)
    n = int.from_bytes(data[80:84], 'little')
    rec = np.dtype([('n', '<f4', 3), ('v', '<f4', (3, 3)), ('a', '<u2')])
    return np.frombuffer(data, dtype=rec, count=n, offset=84)['v'].astype(np.float64)


def mesh_report(path: Path) -> dict:
    """Exact-vertex topology: no rounding, so sub-micron slivers are not merged into defects."""
    tris = load_stl(path)
    uniq, idx = np.unique(tris.reshape(-1, 3), axis=0, return_inverse=True)
    f = idx.reshape(-1, 3)
    collapsed = int(np.sum((f[:, 0] == f[:, 1]) | (f[:, 1] == f[:, 2]) | (f[:, 0] == f[:, 2])))
    directed = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    key = directed[:, 0].astype(np.int64) * len(uniq) + directed[:, 1]
    rkey = directed[:, 1].astype(np.int64) * len(uniq) + directed[:, 0]
    ukey, counts = np.unique(key, return_counts=True)
    dup = int(np.sum(counts != 1))
    unpaired = int(np.sum(~np.isin(rkey, ukey)))
    # Components: faces sharing an undirected edge.
    parent = np.arange(len(f))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    und = np.sort(directed, axis=1)
    ekey = und[:, 0].astype(np.int64) * len(uniq) + und[:, 1]
    face_of = np.tile(np.arange(len(f)), 3)
    order = np.argsort(ekey, kind='stable')
    for a, b in zip(order[:-1], order[1:]):
        if ekey[a] == ekey[b]:
            ra, rb = find(face_of[a]), find(face_of[b])
            if ra != rb:
                parent[rb] = ra
    components = len({find(i) for i in range(len(f))})
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    volume = float(np.sum(np.einsum('ij,ij->i', a, np.cross(b, c))) / 6)
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    lo, hi = tris.reshape(-1, 3).min(0), tris.reshape(-1, 3).max(0)
    return dict(triangles=len(f), components=components, collapsed=collapsed,
                duplicate_edges=dup, unpaired_edges=unpaired, volume_mm3=round(volume, 3),
                slivers_lt_1e8_mm2=int(np.sum(area < 1e-8)),
                min=[round(x, 4) for x in lo], max=[round(x, 4) for x in hi],
                size=[round(x, 4) for x in (hi - lo)])


def intersection_volume(part: str, **defs) -> tuple[float, str]:
    with tempfile.TemporaryDirectory() as d:
        out = Path(d) / 'x.stl'
        code, log = run_scad(out, part, **defs)
        if 'Current top level object is empty' in log:
            return 0.0, 'empty'
        if code != 0 or not out.exists():
            raise RuntimeError(f'{part} {defs}: openscad failed\n{log}')
        t = load_stl(out)
        v = float(np.sum(np.einsum('ij,ij->i', t[:, 0], np.cross(t[:, 1], t[:, 2]))) / 6)
        return abs(v), f'{len(t)} triangles'


# ---------------------------------------------------------------- cam
def lobe_s(d, flat, ramp):
    a = abs((d + 180) % 360 - 180)
    if a <= flat:
        return 1.0
    if a >= flat + ramp:
        return 0.0
    return 0.5 * (1 + math.cos(math.radians(180 * (a - flat) / ramp)))


def lobe_polygon(flat, ramp):
    ts = np.arange(0, 360, CAM['step'])
    r = np.array([CAM['base_r'] + CAM['lift'] * lobe_s(t, flat, ramp) for t in ts])
    th = np.radians(ts)
    return np.stack([-r * np.sin(th), r * np.cos(th)], axis=1)


def foot_height(poly, rot_deg):
    """Height on +Y (toward the palm) of a pointed foot on the polygon rotated by rot_deg."""
    c, s = math.cos(math.radians(rot_deg)), math.sin(math.radians(rot_deg))
    p = poly @ np.array([[c, s], [-s, c]])
    q = np.roll(p, -1, axis=0)
    best = 0.0
    cross = (p[:, 0] <= 0) != (q[:, 0] <= 0)
    for (x0, y0), (x1, y1) in zip(p[cross], q[cross]):
        y = y0 + (y1 - y0) * (0 - x0) / (x1 - x0)
        best = max(best, y)
    return best


def cam_numbers(name: str) -> dict:
    cfg = SHAFTS[name]
    poly = lobe_polygon(cfg['flat'], cfg['ramp'])
    rest = CAM['base_r'] + CAM['foot_clear']

    def lifts(a):
        out = {}
        for row in range(4):
            if row in cfg['rows']:
                b = cfg['angles'][cfg['rows'].index(row)]
                out[row] = max(0.0, foot_height(poly, a - b) - rest)
            else:
                out[row] = 0.0
        return out

    angles = cfg['angles']
    rows = cfg['rows']
    strokes = {r: lifts(b)[r] for r, b in zip(rows, angles)}
    gaps = [(angles[i] + angles[i + 1]) / 2 for i in range(len(angles) - 1)]
    gap_rise = {g: max(lifts(g).values()) for g in gaps}
    tap = {}
    hold = {}
    fine = np.arange(0, 20.0001, 0.05)
    for r, b in zip(rows, angles):
        worst = 0.0
        for sgn in (-1, 1):
            for d in fine:
                L = lifts(b + sgn * d)
                worst = max(worst, max(v for k, v in L.items() if k != r))
        dip = strokes[r] - min(lifts(b - 20)[r], lifts(b + 20)[r])
        tap[r] = dict(neighbour_rise=worst, selected_dip_at_20=dip)
        thr = CAM['stroke'] - 0.05
        half = []
        for sgn in (-1, 1):
            d = 0.0
            while lifts(b + sgn * (d + 0.01))[r] >= thr:
                d += 0.01
            half.append(d)
        hold[r] = min(half)
    return dict(strokes=strokes, gap_rise=gap_rise, tap=tap, hold_half_window=hold)


# ---------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', type=Path, default=REPO / 'stl' / 'production')
    ap.add_argument('--evidence', type=Path, default=HERE / 'evidence')
    ap.add_argument('--jobs', type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    args.evidence.mkdir(parents=True, exist_ok=True)
    report: dict = {'scope': 'CAD geometry only; printing, real-part fit and forces NOT VERIFIED'}
    lines: list[str] = []
    ok_all = True

    def log(ok: bool | None, msg: str):
        nonlocal ok_all
        tag = 'INFO' if ok is None else ('PASS' if ok else 'FAIL')
        if ok is False:
            ok_all = False
        lines.append(f'{tag} {msg}')
        print(lines[-1], flush=True)

    ver = subprocess.run(['openscad', '--version'], capture_output=True, text=True)
    report['openscad'] = (ver.stdout + ver.stderr).strip()
    log(None, report['openscad'])

    # 0. derived parameters
    with tempfile.TemporaryDirectory() as d:
        code, out = run_scad(Path(d) / 'd.stl', 'derived')
    got = {m.group(1): float(m.group(2)) for m in re.finditer(r'DERIVED (\w+) (-?[\d.e+-]+)', out)}
    report['derived'] = {}
    for k, want in DERIVED.items():
        tol = DERIVED_TOL.get(k, 1e-6)
        ok = k in got and abs(got[k] - want) <= tol
        report['derived'][k] = dict(stated=want, computed=got.get(k), pass_=ok)
        if not ok:
            log(False, f'derived {k}: stated {want}, computed {got.get(k)}')
    log(all(v['pass_'] for v in report['derived'].values()),
        f'derived parameters: {len(DERIVED)} values match CAD.md section 2 '
        f'(crown_R computed {got.get("crown_R", float("nan")):.3f})')

    # 1. export + mesh
    def export(stem):
        path = args.out / f'{stem}.stl'
        code, out = run_scad(path, stem)
        return stem, code, out
    report['mesh'] = {}
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        exports = list(ex.map(export, DELIVERABLES))
    for stem, code, out in exports:
        warns = [l for l in out.splitlines() if 'WARNING' in l or 'ERROR' in l]
        path = args.out / f'{stem}.stl'
        if code != 0 or not path.exists():
            log(False, f'{stem}.stl export failed:\n{out}')
            continue
        m = mesh_report(path)
        qty, size = DELIVERABLES[stem]
        dev = [abs(a - b) for a, b in zip(m['size'], size)]
        checks = {
            'export_clean': code == 0 and not warns,
            'one_body': m['components'] == 1,
            'watertight': m['collapsed'] == 0 and m['duplicate_edges'] == 0 and m['unpaired_edges'] == 0,
            'volume_positive': m['volume_mm3'] > 0,
            'on_bed': abs(m['min'][2]) <= 1e-6,
            'bbox': max(dev) <= BBOX_TOL,
        }
        m.update(stated_size=size, max_bbox_dev=round(max(dev), 4), checks=checks, warnings=warns)
        report['mesh'][stem] = m
        failed = [k for k, v in checks.items() if not v]
        log(not failed, f'{stem}.stl: {m["components"]} body, {m["triangles"]} tris, '
            f'vol {m["volume_mm3"]:.1f} mm3, min z {m["min"][2]:.4f}, '
            f'size {m["size"][0]:.3f} x {m["size"][1]:.3f} x {m["size"][2]:.3f} '
            f'(stated {size[0]} x {size[1]} x {size[2]}, max dev {max(dev):.3f})'
            + (f' FAILED: {failed}' if failed else ''))

    # 2. collision sweep
    jobs = [(p, dict(angle=a, variant=v)) for v in (4, 3) for a in SWEEP_ANGLES for p in SHAFT_PAIRS]
    jobs += [(p, {}) for p in STATIC_PAIRS]
    # 3. horn insertion
    jobs += [('x_horn', dict(offset=o, variant=v)) for v in (4, 3) for o in HORN_OFFSETS]
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        res = list(ex.map(lambda j: (j, intersection_volume(j[0], **j[1])), jobs))
    report['collision'] = []
    report['horn'] = []
    for (part, defs), (vol, note) in res:
        if 0 < vol <= TOUCH_MM3:
            note += ', coincident faces only'
        rec = dict(check=part, **defs, volume_mm3=vol, result=note)
        (report['horn'] if part == 'x_horn' else report['collision']).append(rec)
    for key, label in (('collision', 'collision sweep'), ('horn', 'horn insertion')):
        recs = report[key]
        bad = [r for r in recs if r['volume_mm3'] > TOUCH_MM3]
        for r in bad:
            log(False, f'{label}: {r}')
        log(not bad, f'{label}: {len(recs)} intersections, max volume '
            f'{max(r["volume_mm3"] for r in recs):.6f} mm3')
    groups = {}
    for r in report['collision']:
        groups.setdefault(r['check'], []).append(r['volume_mm3'])
    for k, vs in groups.items():
        log(None, f'  {k}: {len(vs)} cases, max {max(vs):.6f} mm3')
    for v in (4, 3):
        vs = [r['volume_mm3'] for r in report['horn'] if r['variant'] == v]
        log(None, f'  horn x {"shaft" if v == 4 else "shaft3"} at offsets {HORN_OFFSETS}: '
            f'{", ".join(f"{x:.6f}" for x in vs)} mm3')

    # 4. cam numbers
    report['cam'] = {}
    for name in SHAFTS:
        c = cam_numbers(name)
        report['cam'][name] = c
        s = list(c['strokes'].values())
        log(all(abs(x - CAM['stroke']) <= 0.05 for x in s),
            f'{name} stroke per lobe: {", ".join(f"{x:.4f}" for x in s)} mm (2.55 +- 0.05)')
        g = c['gap_rise']
        log(all(x <= 0.15 for x in g.values()),
            f'{name} rise at null gaps {list(g)}: {", ".join(f"{x:.4f}" for x in g.values())} mm (<= 0.15)')
        t = c['tap']
        log(all(x['neighbour_rise'] <= 0 for x in t.values()),
            f'{name} neighbour rise during +-20 deg tap: '
            f'{", ".join(f"{x["neighbour_rise"]:.4f}" for x in t.values())} mm (<= 0); '
            f'selected pin dips {", ".join(f"{x["selected_dip_at_20"]:.3f}" for x in t.values())} mm at 20 deg')
        h = c['hold_half_window']
        log(all(x >= 7 for x in h.values()),
            f'{name} flat hold window (lift >= stroke - 0.05): '
            f'+-{", +-".join(f"{x:.2f}" for x in h.values())} deg (>= +-7)')

    report['pass'] = ok_all
    (args.evidence / 'verify.json').write_text(json.dumps(report, indent=1, default=str) + '\n')
    (args.evidence / 'verify.log').write_text('\n'.join(lines) + '\n')
    print(('ALL CHECKS PASS' if ok_all else 'SOME CHECKS FAILED') + f'; evidence in {args.evidence}')
    return 0 if ok_all else 1


if __name__ == '__main__':
    sys.exit(main())

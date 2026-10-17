#!/usr/bin/env python3
"""Dependency-free STL topology/bed check. It does NOT certify printability/fit."""
from __future__ import annotations
import argparse
import collections
import json
import math
from pathlib import Path
import struct
import sys


def read_stl(path: Path):
    data = path.read_bytes()
    if len(data) >= 84 and len(data) == 84 + 50 * struct.unpack_from('<I', data, 80)[0]:
        count = struct.unpack_from('<I', data, 80)[0]
        return [tuple(tuple(struct.unpack_from('<3f', data, 84 + 50*i + 12 + 12*j))
                      for j in range(3)) for i in range(count)]
    vertices = []
    for line in data.decode('ascii').splitlines():
        fields = line.split()
        if fields[:1] == ['vertex']:
            if len(fields) != 4:
                raise ValueError('malformed ASCII vertex')
            vertices.append(tuple(map(float, fields[1:])))
    if not vertices or len(vertices) % 3:
        raise ValueError('empty or incomplete STL')
    return [tuple(vertices[i:i+3]) for i in range(0, len(vertices), 3)]


def inspect(path: Path, expected_components=1, bed_tolerance=0.02):
    triangles = read_stl(path)
    if not triangles:
        raise ValueError('no triangles')
    edges = collections.defaultdict(list)
    parents = list(range(len(triangles)))
    lo, hi = [float('inf')]*3, [-float('inf')]*3
    volume = 0.0
    errors = []

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for i, tri in enumerate(triangles):
        if any(not math.isfinite(v) for p in tri for v in p):
            raise ValueError('nonfinite coordinate')
        pts = [tuple(round(x, 5) for x in p) for p in tri]
        u, v = [tri[1][j]-tri[0][j] for j in range(3)], [tri[2][j]-tri[0][j] for j in range(3)]
        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        # Valid tiny sliver triangles arise where curved cap and bores intersect.
        # Reject actual collapsed/zero-area faces, not an arbitrary mm-scale area.
        if len(set(pts)) != 3 or sum(q*q for q in cross) < 1e-24:
            errors.append('degenerate triangle')
        a,b,c = tri
        volume += (a[0]*(b[1]*c[2]-b[2]*c[1]) + a[1]*(b[2]*c[0]-b[0]*c[2]) + a[2]*(b[0]*c[1]-b[1]*c[0]))/6
        for p in tri:
            for j in range(3):
                lo[j],hi[j] = min(lo[j],p[j]),max(hi[j],p[j])
        for a,b in zip(pts, pts[1:]+pts[:1]):
            edge = tuple(sorted((a,b)))
            edges[edge].append((i, 1 if a < b else -1))
    bad_edges = 0
    for incidences in edges.values():
        if len(incidences) != 2 or sum(s for _,s in incidences) != 0:
            bad_edges += 1
        first = root(incidences[0][0])
        for i,_ in incidences[1:]:
            parents[root(i)] = first
    components = len({root(i) for i in parents})
    if bad_edges: errors.append(f'{bad_edges} nonmanifold or inconsistently oriented edges')
    if components != expected_components: errors.append(f'{components} components; expected {expected_components}')
    if abs(lo[2]) > bed_tolerance: errors.append(f'lowest Z={lo[2]:.4f}; expected bed Z=0')
    if volume <= 0: errors.append(f'nonpositive signed volume {volume:.4f}')
    return {'path':str(path),'pass':not errors,'triangles':len(triangles),'components':components,
            'bounds_mm':[lo,hi],'volume_mm3':round(volume,3),'errors':sorted(set(errors))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths',nargs='+',type=Path)
    parser.add_argument('--json',type=Path)
    args=parser.parse_args()
    results=[]
    for path in args.paths:
        try: result=inspect(path)
        except (OSError,ValueError,UnicodeError,struct.error) as exc:
            result={'path':str(path),'pass':False,'errors':[str(exc)]}
        results.append(result)
        print(f"{'PASS' if result['pass'] else 'FAIL'} {path}: " +
              (f"{result.get('triangles')} triangles / {result.get('components')} body / on bed" if result['pass'] else '; '.join(result['errors'])))
    if args.json:
        args.json.parent.mkdir(parents=True,exist_ok=True)
        args.json.write_text(json.dumps({'scope':'mesh topology only; physical fit/strength NOT VERIFIED','files':results},indent=2)+'\n')
    return 0 if all(r['pass'] for r in results) else 1


if __name__=='__main__': sys.exit(main())

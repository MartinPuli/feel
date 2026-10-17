#!/usr/bin/env python3
"""Ideal geometric contact with the actual OpenSCAD polygon, not a physics model.

A vertical, frictionless follower has a 0.6mm flat tip and conical underside.
Contact is the maximum of cam surface Z minus the follower underside height.
All polygon vertices AND segment intersections with follower kinks are tested.
This includes finite-tip broadening; it does not assume radial lift == pin lift.
"""
from __future__ import annotations
import argparse
import ast
import csv
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def load_geometry(defines=()):
    executable=shutil.which('openscad')
    if not executable: raise RuntimeError('OpenSCAD is required: simulation must use the actual CAD vertices')
    with tempfile.TemporaryDirectory(prefix='feel-cam-') as tmp:
        result=subprocess.run([executable,'-o',str(Path(tmp)/'profile.csg'),*[item for value in defines for item in ('-D',value)],str(ROOT/'cad/tools/profile.scad')],capture_output=True,text=True,timeout=60)
    if result.returncode or 'ERROR:' in result.stderr or 'WARNING:' in result.stderr:
        raise RuntimeError(result.stderr)
    profiles={}
    params=None
    for line in result.stderr.splitlines():
        if not line.startswith('ECHO: '): continue
        data=ast.literal_eval(line[6:])
        if data[0]=='PARAMETERS': params=data[1:]
        elif data[0]=='PROFILE': profiles[(data[1],data[2])]=data[3]
    if params is None or len(profiles)!=12 or any(len(p)<90 for p in profiles.values()):
        raise RuntimeError('Missing/empty exported geometry; fail closed')
    return params,profiles


def contact_height(polygon, angle, pin_radius, tip_radius, half_angle):
    angle=math.radians(angle)
    ca,sa=math.cos(angle),math.sin(angle)
    vertices=[(x*ca+y*sa, -x*sa+y*ca) for x,y in polygon]
    slope=1/math.tan(math.radians(half_angle))
    best=-math.inf
    def candidate(x,z):
        return z-max(0,abs(x)-tip_radius)*slope
    for (x,z),(x2,z2) in zip(vertices,vertices[1:]+vertices[:1]):
        if abs(x)<=pin_radius+1e-9: best=max(best,candidate(x,z))
        if abs(x2-x)>1e-12:
            for cutoff in (-pin_radius,-tip_radius,tip_radius,pin_radius):
                t=(cutoff-x)/(x2-x)
                if 0<t<1: best=max(best,candidate(cutoff,z+(z2-z)*t))
    if not math.isfinite(best): raise ValueError('Follower does not intersect cam projection')
    return best


def run_checks(step=0.5):
    params,profiles=load_geometry()
    bands,gaps,tap,base,stroke,pin_r,tip_r,half_angle,pitch,cam_step=params
    checks=[]
    curves=[]
    def check(name,passed,observed):
        checks.append({'name':name,'pass':bool(passed),'observed':observed})
    def lifts(variant,angle):
        return [max(0,contact_height(profiles[(variant,b)],angle,pin_r,tip_r,half_angle)-base) for b in range(4)]
    check('protocol bands',bands==[0,40,80,120],bands)
    check('protocol gaps',gaps==[20,60,100],gaps)
    check('full 2mm design stroke',stroke==2,stroke)
    check('120 degree shaft range',min(bands)==0 and max(bands)==120,bands)
    check('pitch envelope',2*(base+stroke)<pitch,{'cam_d':2*(base+stroke),'pitch':pitch})
    for variant,label in enumerate(('A','H','G')):
        for band,angle in enumerate(bands):
            values=lifts(variant,angle)
            check(f'{label} band {band+1} selected',abs(values[band]-stroke)<0.015,values)
            check(f'{label} band {band+1} neighbours down',all(v<0.03 for i,v in enumerate(values) if i!=band),values)
            toward_gap=min(gaps,key=lambda gap:(abs(gap-angle),gap))
            tap_angle=angle+math.copysign(tap,toward_gap-angle)
            check(f'{label} band {band+1} firmware tap angle',tap_angle==[13,27,67,107][band],tap_angle)
            tapped=lifts(variant,tap_angle)
            check(f'{label} band {band+1} tap dip',0.65<=values[band]-tapped[band]<=1.4,{'angle':tap_angle,'lift':tapped[band],'drop':values[band]-tapped[band]})
            check(f'{label} band {band+1} tap no neighbour',all(v<0.03 for i,v in enumerate(tapped) if i!=band),tapped)
        for angle in gaps:
            values=lifts(variant,angle)
            check(f'{label} gap {angle} all down',max(values)<0.03,values)
        violations=[]
        max_lift=0
        angles=[i*step for i in range(int(120/step)+1)]
        for angle in angles:
            values=lifts(variant,angle)
            curves.append([label,angle,*[round(v,6) for v in values]])
            if sum(v>0.12 for v in values)>1: violations.append([angle,values])
            max_lift=max(max_lift,max(values))
        check(f'{label} sweep no two active above 0.12mm',not violations,violations[:5])
        check(f'{label} sweep bounded stroke',max_lift<=stroke+0.015,max_lift)
    return {'scope':'SIMULATION — rigid ideal cam/conical follower contact; no force, friction, foam, backlash, tolerance, servo or user testing',
            'geometry':'OpenSCAD evaluated cad/lib.scad cam_points; exact polygon contact at sampled shaft angles',
            'shaft_angle_step_degrees':step,'cam_polygon_step_degrees':cam_step,
            'checks':checks,'pass':all(c['pass'] for c in checks)},curves


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json',type=Path)
    parser.add_argument('--csv',type=Path)
    parser.add_argument('--step',type=float,default=0.5)
    args=parser.parse_args()
    if not 0<args.step<=1: parser.error('--step must be between 0 and 1 degree')
    try: report,curves=run_checks(args.step)
    except (RuntimeError,ValueError,subprocess.TimeoutExpired) as exc:
        print(f'FAIL: {exc}',file=sys.stderr);return 1
    for result in report['checks']:
        print(f"{'PASS' if result['pass'] else 'FAIL'} {result['name']}: {result['observed']}")
    if args.json:
        args.json.parent.mkdir(parents=True,exist_ok=True)
        args.json.write_text(json.dumps(report,indent=2)+'\n')
    if args.csv:
        args.csv.parent.mkdir(parents=True,exist_ok=True)
        with args.csv.open('w',newline='') as f:
            writer=csv.writer(f);writer.writerow(['variant','angle_degrees','band1_mm','band2_mm','band3_mm','band4_mm']);writer.writerows(curves)
    print(f"{sum(c['pass'] for c in report['checks'])}/{len(report['checks'])} ideal geometry checks passed; PHYSICAL VALIDATION PENDING")
    return 0 if report['pass'] else 1


if __name__=='__main__': sys.exit(main())

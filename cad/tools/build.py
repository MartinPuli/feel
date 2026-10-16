#!/usr/bin/env python3
"""Headless real OpenSCAD STL export, topology checks, and a physical print gate."""
from __future__ import annotations
import argparse
import ast
import csv
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from check_stl import inspect

ROOT=Path(__file__).resolve().parents[2]
TEST_PARTS=['frame','strip','guide','shaft_A','shaft_H','shaft_G','pins_tip21','pins_tip15','crank','dummy_servo','foam_template','hole_coupon','pitch_coupon','coupling_C1','coupling_C2','coupling_C3']
PUCK_PARTS=['chassis','face','guide','shaft_A','pins','foam_template','servo_retainer','pack_tray']
FAST_PARTS={'shaft_A','pins_tip21','hole_coupon','coupling_C1'}


def is_true(text,key):
    return re.search(r'^\s*'+re.escape(key)+r'\s*=\s*true\s*;',text,re.MULTILINE) is not None


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fast',action='store_true',help='Only representative test-column STLs')
    parser.add_argument('--print-ready',action='store_true',help='Require recorded measurement flags; still NOT a physical certification')
    parser.add_argument('--output',type=Path,help='Default: stl/ for full builds, stl/fast/ for --fast')
    parser.add_argument('--part',help='Export one part by test/name or puck/name')
    args=parser.parse_args()
    openscad=shutil.which('openscad')
    if not openscad: parser.error('OpenSCAD is not installed')
    params=(ROOT/'cad/params.scad').read_text()
    measured=is_true(params,'measurements_confirmed') and is_true(params,'horn_fit_confirmed')
    if args.print_ready and not measured:
        print('BLOCKED: params.scad has UNMEASURED servo/horn/pack dimensions. Record measurements and verify fit before --print-ready.',file=sys.stderr)
        return 2
    print('CAD GEOMETRY EXPORT ONLY — hardware fit, return, strength and tactile behavior NOT VERIFIED',flush=True)
    jobs=[('test',p) for p in TEST_PARTS]+[('puck',p) for p in PUCK_PARTS]
    if args.fast: jobs=[(g,p) for g,p in jobs if g=='test' and p in FAST_PARTS]
    if args.part:
        if tuple(args.part.split('/')) not in jobs: parser.error('Unknown --part or excluded by --fast')
        jobs=[tuple(args.part.split('/'))]
    args.output=(args.output or (ROOT/'stl/fast' if args.fast else ROOT/'stl')).resolve()
    args.output.mkdir(parents=True,exist_ok=True)
    # Keep the descriptor alive for the entire export. macOS and Linux release
    # this advisory lock even after a killed process; no stale PID-file cleanup.
    lock_file=(args.output/'.build.lock').open('a')
    try:
        fcntl.flock(lock_file.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        print(f'BLOCKED: another CAD build is writing {args.output}; wait for it to finish.',file=sys.stderr)
        return 2
    probe=subprocess.run([openscad,'-o',str(args.output/'nominal-fit.csg'),str(ROOT/'cad/tools/fit_probe.scad')],capture_output=True,text=True,timeout=60)
    (args.output/'nominal-fit.csg').unlink(missing_ok=True)
    (args.output/'nominal-fit.log').write_text(probe.stderr)
    if probe.returncode or 'ERROR:' in probe.stderr or 'WARNING:' in probe.stderr or 'NOMINAL_FIT' not in probe.stderr:
        print('FAIL selected nominal fit checks: '+probe.stderr,file=sys.stderr);return 1
    print('PASS selected nominal envelope checks (not a full collision check)',flush=True)
    with (args.output/'pin-lengths.csv').open('w',newline='') as f:
        writer=csv.writer(f);writer.writerow(['column','band','x_mm','y_mm','pin_length_mm','selected_tip_z_mm'])
        for line in probe.stderr.splitlines():
            if line.startswith('ECHO: ["PIN",'):
                writer.writerow(ast.literal_eval(line[6:])[1:])
    records=[]
    for group,part in jobs:
        source='pack.scad' if part=='pack_tray' else 'test_column.scad' if group=='test' else 'puck.scad'
        dest=args.output/group/(part+'.stl')
        dest.parent.mkdir(parents=True,exist_ok=True)
        tmp=dest.with_name('.'+dest.stem+f'.{os.getpid()}.building.stl')
        start=time.monotonic()
        command=[openscad,'--export-format','binstl','-o',str(tmp),'-D',f'part="{part}"',str(ROOT/'cad'/source)]
        try:
            process=subprocess.run(command,capture_output=True,text=True,timeout=240)
        except subprocess.TimeoutExpired:
            tmp.unlink(missing_ok=True)
            print(f'FAIL {group}/{part}: OpenSCAD timed out',file=sys.stderr);return 1
        if process.returncode or 'ERROR:' in process.stderr or 'WARNING:' in process.stderr or not tmp.exists():
            tmp.unlink(missing_ok=True)
            print(f'FAIL {group}/{part}: {process.stderr}',file=sys.stderr);return 1
        record=inspect(tmp)
        if not record['pass']:
            tmp.unlink(missing_ok=True)
            print(json.dumps(record,indent=2),file=sys.stderr);return 1
        tmp.replace(dest)
        record.update(path=str(dest.relative_to(args.output)),sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),seconds=round(time.monotonic()-start,2))
        records.append(record)
        print(f"PASS {group}/{part}: {record['triangles']} triangles, one body, on bed ({record['seconds']}s)",flush=True)
    manifest={'scope':'GEOMETRY ONLY — not physically verified','hardware_measurements_confirmed':measured,
              'mode':'fast' if args.fast else 'single' if args.part else 'full','files':records,
              'copies':{'puck/shaft_A.stl':8,'puck/pins.stl':1,'puck/foam_template.stl':1},
              'notes':['Print 7 working shafts + 1 spare; 28 pins on removable sprues.','C3 is a nominal bore sizing coupon, not an engineered 20T spline.','Bed contact and closed mesh do not prove support-free printing.']}
    manifest_name='manifest-fast.json' if args.fast else 'manifest-single.json' if args.part else 'manifest.json'
    (args.output/manifest_name).write_text(json.dumps(manifest,indent=2)+'\n')
    return 0


if __name__=='__main__': sys.exit(main())

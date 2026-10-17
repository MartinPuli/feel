#!/usr/bin/env python3
"""Greenfield V1 evidence runner. No device signing, flashing, or hardware IO."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import subprocess
import sys
from run_v2_checks import run_check
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'.artifacts/v1-checks')
    parser.add_argument('--skip-cad-build',action='store_true',help='Validate existing meshes; CAD build reported NOT RUN')
    args=parser.parse_args(); output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    checks=[]
    def check(name,command,**kwargs):
        result=run_check(name,command,output,**kwargs)
        if result['status']=='BLOCKED':result['next_action']='Install the toolchain or implement the missing component; rerun. Original source is not required.'
        checks.append(result);print(f"{result['status']:8} {name}",flush=True)
    check('source-presence',[sys.executable,'scripts/check_sources.py'],blocked_exit=True)
    check('tooling-regressions',[sys.executable,'-m','unittest','discover','-s','scripts/tests','-v'])
    check('historical-reference-model',[sys.executable,'-m','unittest','discover','-s','validation/tests','-v'],scope='historical specification model only')
    check('firmware-host',['sh','firmware/test/run_host_tests.sh'],files=('firmware/test/run_host_tests.sh',),tools=('g++',))
    check('firmware-bench-host',['sh','-c','mkdir -p firmware/build && c++ -std=c++11 -Wall -Wextra -Werror -Wpedantic -O2 -I firmware/bench-single/include firmware/bench-single/test/state_test.cpp -o firmware/build/single-bench-tests && firmware/build/single-bench-tests'],files=('firmware/bench-single/test/state_test.cpp','firmware/bench-single/include/bench.hpp'),tools=('c++',),scope='standalone single-servo bench state machine; no hardware IO')
    check('swift-core',['sh','ios/scripts/test_portable.sh'],tools=('swift',),timeout=600)
    check('swift-cli',['swift','build','-j','2','--package-path','ios/Shared/FeelCore'],tools=('swift',),timeout=600)
    check('production-integration',[sys.executable,'validation/production/run.py','--output',str(output/'simulation')],files=('ios/Shared/FeelCore/.build/debug/feel-replay','firmware/build/feel-sim'),scope='compiled production Swift and C++ with synthetic inputs')
    check('firmware-build',['pio','run','-j','2','--project-dir','firmware'],tools=('pio',),timeout=1200)
    check('firmware-single-demo-build',['pio','run','-j','2','--project-dir','firmware','-e','esp32-single-demo'],tools=('pio',),files=('firmware/platformio.ini',),timeout=1200,scope='single-servo BLE demo compile only; no upload')
    check('firmware-single-live-build',['pio','run','-j','2','--project-dir','firmware','-e','esp32-single-live'],tools=('pio',),files=('firmware/platformio.ini',),timeout=1200,scope='single-servo nominal120 live compile only; no upload')
    check('firmware-bench-build',['pio','run','-j','2','--project-dir','firmware/bench-single','-e','esp32-single-center'],tools=('pio',),files=('firmware/bench-single/platformio.ini',),timeout=1200,scope='standalone single-servo bench compile only; no upload')
    check('firmware-enabled-compile',['sh','firmware/test/build_output_paths.sh'],tools=('pio',),timeout=1200)
    if not args.skip_cad_build:check('cad-build',['sh','cad/build.sh'],tools=('openscad',),timeout=1200)
    else:checks.append({'name':'cad-build','status':'NOT RUN','command':'sh cad/build.sh','reason':'Explicit --skip-cad-build; existing meshes checked separately.'})
    stls=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'stl').glob('*/*.stl'))
    check('cad-meshes',[sys.executable,'cad/tools/check_stl.py',*stls],files=('cad/tools/check_stl.py',))
    check('cam-model',[sys.executable,'cad/tools/cam_sim.py'],files=('cad/tools/cam_sim.py',))
    check('cad-firmware-contract',[sys.executable,'validation/check_cam_contract.py'],tools=('openscad',),files=('firmware/build/feel-sim',),scope='compiled controller commands against evaluated CAD polygon contact')
    check('cad-tool-tests',[sys.executable,'-m','unittest','discover','-s','cad/test','-v'])
    check('coreml-resource',[sys.executable,'scripts/fetch_model.py'])
    check('ios-platform',['bash','scripts/check_ios.sh'],tools=('xcodegen','xcodebuild','xcrun'),blocked_exit=True,timeout=2400)
    failed=any(x['status']=='FAIL' for x in checks);incomplete=any(x['status'] in ('BLOCKED','NOT RUN') for x in checks)
    report={'version':'V1 greenfield','timestamp_utc':datetime.now(timezone.utc).isoformat(),'platform':platform.platform(),
            'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'working_tree_dirty':bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip()),
            'available_checks':'FAIL' if failed else 'PASS','complete_software_gate':'FAIL' if failed else 'BLOCKED' if incomplete else 'PASS',
            'physical_hardware':'NOT VERIFIED','checks':checks}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"Available checks: {report['available_checks']}; complete gate: {report['complete_software_gate']}; physical NOT VERIFIED")
    print(f"Evidence: {output/'report.json'}")
    return 1 if failed else 2 if incomplete else 0
if __name__=='__main__':raise SystemExit(main())

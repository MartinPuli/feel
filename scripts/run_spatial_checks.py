#!/usr/bin/env python3
"""V2 checks: production memory, preserved V1 contract, and explicit Apple gate."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import sys
from run_v2_checks import run_check
ROOT = Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=ROOT/'.artifacts/v2-checks')
    args=p.parse_args(); output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    checks=[]
    def check(name,command,**kwargs):
        result=run_check(name,command,output,**kwargs)
        if result['status']=='BLOCKED': result['next_action']='Run with the listed toolchain and current source; original source files are not required.'
        checks.append(result)
        print(f"{result['status']:8} {name}",flush=True)
    check('swift-core',['sh','ios/scripts/test_portable.sh'],tools=('swift',),timeout=600)
    check('swift-cli',['swift','build','-j','2','--package-path','ios/Shared/FeelCore'],tools=('swift',),timeout=600)
    check('firmware-host',['sh','firmware/test/run_host_tests.sh'],tools=('g++',))
    check('v1-production-contract',[sys.executable,'validation/production/run.py','--output',str(output/'foundation-replay')])
    check('spatial-production-contract',[sys.executable,'validation/spatial/run.py','--output',str(output/'spatial-replay')])
    check('ios-platform',['bash','scripts/check_ios.sh'],tools=('xcodegen','xcodebuild','xcrun'),blocked_exit=True,timeout=2400)
    failed=any(c['status']=='FAIL' for c in checks); incomplete=any(c['status']!='PASS' for c in checks)
    report={'version':'V2 spatial memory','timestamp_utc':datetime.now(timezone.utc).isoformat(),
            'platform':platform.platform(),'available_checks':'FAIL' if failed else 'PASS',
            'complete_software_gate':'FAIL' if failed else 'BLOCKED' if incomplete else 'PASS',
            'physical_hardware':'NOT VERIFIED','checks':checks,
            'foundation_evidence':'docs/evidence/v1/report.json; CAD/firmware source unchanged from V1 milestone'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"Available checks: {report['available_checks']}; complete gate: {report['complete_software_gate']}; physical NOT VERIFIED")
    return 1 if failed else 2 if incomplete else 0
if __name__=='__main__':raise SystemExit(main())

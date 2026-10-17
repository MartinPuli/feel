#!/usr/bin/env python3
"""V3 production checks with preserved foundation/spatial replay and Apple gate."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import sys
from run_v2_checks import run_check

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'.artifacts/v3-checks')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(name, command, completion=None, **kwargs):
        result = run_check(name, command, output, **kwargs)
        # Some restricted Linux hosts have returned zero from a prematurely
        # terminated Swift subprocess. Require its completion output as well.
        if result['status'] == 'PASS' and completion:
            log = Path(result['log']).read_text(errors='replace')
            if completion not in log:
                result.update(status='FAIL', error='Process exited zero without required completion output: '+completion)
        if result['status'] == 'BLOCKED':
            result['next_action'] = 'Run the same source on the listed platform/toolchain; consult hosted CI evidence separately.'
        checks.append(result)
        print(f"{result['status']:8} {name}", flush=True)
    check('swift-core', ['sh','ios/scripts/test_portable.sh'], tools=('swift',), timeout=600,
          completion="Test Suite 'All tests' passed")
    check('swift-cli', ['swift','build','-j','2','--package-path','ios/Shared/FeelCore'], tools=('swift',), timeout=600,
          completion='Build complete!')
    check('firmware-host', ['sh','firmware/test/run_host_tests.sh'], tools=('g++',))
    for name, folder in [('v1-production-contract','production'),
                         ('v2-spatial-contract','spatial'),
                         ('v3-advanced-contract','advanced')]:
        check(name, [sys.executable,f'validation/{folder}/run.py','--output',str(output/folder)])
    check('ios-platform', ['bash','scripts/check_ios.sh'], tools=('xcodegen','xcodebuild','xcrun'),
          blocked_exit=True, timeout=2400)
    failed = any(c['status'] == 'FAIL' for c in checks)
    incomplete = any(c['status'] != 'PASS' for c in checks)
    report = {'version':'V3 advanced', 'timestamp_utc':datetime.now(timezone.utc).isoformat(),
              'platform':platform.platform(), 'available_checks':'FAIL' if failed else 'PASS',
              'complete_software_gate':'FAIL' if failed else 'BLOCKED' if incomplete else 'PASS',
              'physical_hardware':'NOT VERIFIED', 'checks':checks,
              'prerequisite_evidence':['docs/evidence/v1-release/report.json','docs/evidence/v2-main/report.json']}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"Available checks: {report['available_checks']}; complete gate: {report['complete_software_gate']}; physical NOT VERIFIED")
    return 1 if failed else 2 if incomplete else 0

if __name__ == '__main__':
    raise SystemExit(main())

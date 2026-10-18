#!/usr/bin/env python3
"""Run the Swift component tests and publish a compact result for /replay."""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'ios' / 'Shared' / 'FeelCore'
REPORT = ROOT / 'simulation' / 'out' / 'web' / 'unit-tests.json'
PIN_DIAGNOSTICS = ROOT / 'simulation' / 'pin_diagnostics.py'
CASE = re.compile(r"Test Case '-\[[^.]+\.(?P<suite>[^ ]+) (?P<name>[^]]+)\]' (?P<status>passed|failed|skipped)")
FAILURE = re.compile(r"error: .*?: (?P<message>.+)$")


def main() -> int:
    result = subprocess.run(
        ['swift', 'test', '--package-path', str(PACKAGE)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    cases: dict[str, list[dict[str, str]]] = defaultdict(list)
    failures: list[str] = []
    for line in result.stdout.splitlines():
        match = CASE.search(line)
        if match:
            cases[match.group('suite')].append({
                'name': match.group('name'),
                'status': match.group('status').upper(),
            })
        elif 'error:' in line:
            failure = FAILURE.search(line)
            failures.append(failure.group('message') if failure else line.strip())

    suites = []
    for name in sorted(cases):
        tests = cases[name]
        counts = {status.lower(): sum(t['status'] == status for t in tests)
                  for status in ('PASSED', 'FAILED', 'SKIPPED')}
        suites.append({
            'name': name,
            'total': len(tests),
            'passed': counts['passed'],
            'failed': counts['failed'],
            'skipped': counts['skipped'],
            'tests': tests,
        })

    total = sum(suite['total'] for suite in suites)
    passed = sum(suite['passed'] for suite in suites)
    failed = sum(suite['failed'] for suite in suites)
    skipped = sum(suite['skipped'] for suite in suites)
    if total == 0:
        failures.append('No XCTest cases were parsed; inspect the Swift test output before claiming a pass.')
    diagnostics = subprocess.run(
        [sys.executable, str(PIN_DIAGNOSTICS)], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    diagnostic_ok = diagnostics.returncode == 0
    if not diagnostic_ok:
        failures.extend(line for line in diagnostics.stdout.splitlines() if line.strip())

    report = {
        'generatedAt': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'status': 'PASS' if result.returncode == 0 and total > 0 and failed == 0 and diagnostic_ok else 'FAIL',
        'exitCode': result.returncode if result.returncode else diagnostics.returncode,
        'total': total,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'suites': suites,
        'errors': failures[-20:],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['status']}: {passed}/{total} unit tests passed, {failed} failed, {skipped} skipped")
    print(diagnostics.stdout.strip())
    print(f'Replay data: {REPORT}')
    if result.returncode != 0 and not failures:
        print(result.stdout[-4000:], file=sys.stderr)
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

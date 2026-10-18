#!/usr/bin/env python3
"""Exercise every physical pin through the production app encoder and firmware controller.

This validates the software command path. It deliberately does not claim that a
servo or pin physically moved, because the puck has no position feedback.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'ios' / 'Shared' / 'FeelCore'
APP = PACKAGE / '.build' / 'release' / 'feel-replay'
SIM = ROOT / 'firmware' / 'build' / 'feel-sim'
REPORT = ROOT / 'simulation' / 'out' / 'web' / 'pin-diagnostics.json'

SLOTS = [
    {'slot': 1, 'label': 'L3', 'gpio': 33},
    {'slot': 2, 'label': 'L2', 'gpio': 25},
    {'slot': 3, 'label': 'L1', 'gpio': 26},
    {'slot': 4, 'label': 'R1', 'gpio': 27},
    {'slot': 5, 'label': 'R2', 'gpio': 14},
    {'slot': 6, 'label': 'R3', 'gpio': 13},
]
BANDS = [
    {'band': 1, 'distance': 0.5, 'angle': 0, 'pulse': 650},
    {'band': 2, 'distance': 1.2, 'angle': 58, 'pulse': 1263},
    {'band': 3, 'distance': 2.0, 'angle': 116, 'pulse': 1876},
    {'band': 4, 'distance': 3.0, 'angle': 174, 'pulse': 2489},
]


def build() -> None:
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'feel-replay', '--package-path', str(PACKAGE)], check=True)
    SIM.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        'c++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-Wpedantic', '-O2',
        '-I', str(ROOT / 'firmware' / 'include'), str(ROOT / 'firmware' / 'src' / 'controller.cpp'),
        str(ROOT / 'firmware' / 'src' / 'commands.cpp'), str(ROOT / 'firmware' / 'host' / 'simulator.cpp'),
        '-o', str(SIM),
    ], check=True)


def app_packets() -> list[dict]:
    commands = []
    case_index = 0
    for slot in SLOTS:
        for band in BANDS:
            distances = [None] * 7
            distances[slot['slot']] = band['distance']
            commands.append({
                'op': 'perceive', 'seq': case_index, 'now': 10, 'frameTimestamp': 10,
                'tracking': True, 'floorCalibrated': True, 'distances': distances,
            })
            case_index += 1
    result = subprocess.run([str(APP), 'stdio'], input=''.join(json.dumps(c) + '\n' for c in commands),
                            text=True, stdout=subprocess.PIPE, check=True)
    replies = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    if len(replies) != len(commands) or not all(reply.get('valid') for reply in replies):
        raise RuntimeError('production app encoder did not return one valid packet per pin test')
    return replies


def controller_state(hex_packet: str, now: int) -> dict:
    bytes_ = [str(value) for value in bytes.fromhex(hex_packet)]
    lines = [f'CONNECT {now - 1}', f'PACKET {now} ' + ' '.join(bytes_), f'TICK {now + 100}']
    result = subprocess.run([str(SIM)], input='\n'.join(lines) + '\n', text=True,
                            stdout=subprocess.PIPE, check=True)
    states = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    return states[-1]


def main() -> int:
    build()
    replies = app_packets()
    cases = []
    index = 0
    for slot in SLOTS:
        for band in BANDS:
            reply = replies[index]
            expected_bands = [0] * 7
            expected_bands[slot['slot']] = band['band']
            state = controller_state(reply['hex'], 1000 + index * 1000)
            stages = {
                'appEncoder': reply.get('bands') == expected_bands and reply.get('state') == 'live',
                'wirePacket': reply.get('hex') == f"{index:02x}" + ''.join(f'{value:02x}' for value in expected_bands) + 'ff',
                'firmwareAccepted': state.get('result') == 'ok' and state.get('active') is True,
                'firmwareBand': state.get('bands') == expected_bands,
                'firmwareAngle': state.get('angles_deg', [None] * 7)[slot['slot']] == band['angle'],
                'firmwarePulse': state.get('pulses_us', [None] * 7)[slot['slot']] == band['pulse'],
            }
            failed = next((name for name, passed in stages.items() if not passed), None)
            cases.append({
                'label': slot['label'], 'slot': slot['slot'], 'gpio': slot['gpio'],
                'expectedBand': band['band'], 'expectedAngleDeg': band['angle'], 'expectedPulseUs': band['pulse'],
                'packetHex': reply['hex'], 'actualBands': state.get('bands'),
                'actualAngleDeg': state.get('angles_deg', [None] * 7)[slot['slot']],
                'actualPulseUs': state.get('pulses_us', [None] * 7)[slot['slot']],
                'stages': stages, 'status': 'PASS' if failed is None else 'FAIL',
                'firstFailure': failed,
                'physicalMotion': 'UNVERIFIED',
                'physicalNote': 'No position feedback is available from this puck. Check wiring, power, servo range, and mechanics on hardware.',
            })
            index += 1
    passed = sum(case['status'] == 'PASS' for case in cases)
    report = {
        'generatedAt': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'status': 'PASS' if passed == len(cases) else 'FAIL',
        'total': len(cases), 'passed': passed, 'failed': len(cases) - passed,
        'hardware': 'UNVERIFIED',
        'hardwareNote': 'These are software command-path results, not measured pin or servo movement.',
        'cases': cases,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['status']}: {passed}/{len(cases)} app-to-firmware pin command tests passed")
    print(f'Replay data: {REPORT}')
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

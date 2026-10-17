#!/usr/bin/env python3
"""Compare compiled controller commands with evaluated CAD polygon contact.

No device I/O. Fails if firmware angles/pulses diverge from the 120-degree CAD
or if a commanded band/gap/tap violates ideal static pin-selection criteria.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'cad/tools'))
from cam_sim import contact_height, load_geometry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firmware', type=Path, default=ROOT/'firmware/build/feel-sim')
    args = parser.parse_args()
    params, profiles = load_geometry()
    bands, gaps, tap, base, stroke, pin_r, tip_r, half_angle, *_ = params
    assert bands == [0, 40, 80, 120] and gaps == [20, 60, 100] and tap == 13
    checks = 0

    def check(condition, message):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(message)

    for band, angle in enumerate(bands, 1):
        gap = min(gaps, key=lambda g: (abs(g-angle), g))
        tapped = angle + (tap if gap > angle else -tap)
        commands = ['RESET 0', 'CONNECT 0',
                    f'PACKET 1 0 {" ".join([str(band)]*7)} 255',
                    'PACKET 2 1 0 0 0 0 0 0 0 255',
                    f'PACKET 3 2 {" ".join([str(band)]*7)} 0',
                    'TICK 103', 'TICK 503']
        result = subprocess.run([str(args.firmware.resolve())], input='\n'.join(commands)+'\n',
                                text=True, capture_output=True, check=True, timeout=10)
        states = [json.loads(line) for line in result.stdout.splitlines()]
        check(len(states) == len(commands), 'Missing controller response')
        expected = [(2, [angle]*7), (3, [gap]*7),
                    (4, [tapped]+[angle]*6), (5, [angle]*7), (6, [gap]*7)]
        for index, angles in expected:
            check(states[index]['angles_deg'] == angles, f'Band {band}: CAD/controller angle mismatch at {commands[index]}')
            check(states[index]['pulses_us'] == [900+10*a for a in angles], f'Band {band}: pulse mapping mismatch')
        for variant in range(3):
            def lifts(at):
                return [max(0, contact_height(profiles[(variant, b)], at, pin_r, tip_r, half_angle)-base)
                        for b in range(4)]
            selected, down, dipped = lifts(states[2]['angles_deg'][0]), lifts(states[3]['angles_deg'][0]), lifts(states[4]['angles_deg'][0])
            check(abs(selected[band-1]-stroke) < .015, f'Band {band} variant {variant}: full lift lost')
            check(all(v < .03 for i,v in enumerate(selected) if i != band-1), f'Band {band}: neighbour at selected angle')
            check(max(down) < .03, f'Band {band}: neutral does not release pins')
            check(.65 <= selected[band-1]-dipped[band-1] <= 1.4, f'Band {band}: tap drop out of range')
            check(all(v < .03 for i,v in enumerate(dipped) if i != band-1), f'Band {band}: tap lifts neighbour')
    print(f'PASS: {checks} compiled-firmware / actual-CAD contract checks; physical validation pending')


if __name__ == '__main__':
    main()

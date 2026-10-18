#!/usr/bin/env python3
"""Raise exactly the pins you ask for on the real puck, and read back what the firmware did.

Two ways to say which pins:

  --pins 3:2 5:4            wire slot 3 to band 2 and slot 5 to band 4, nothing else
  --lidar -30:1.2 20:0.6    obstacles at a bearing (degrees, right positive) and range (metres);
                            they go through the production depth projector and encoder, so
                            this is a synthetic projector/encoder check, not the full camera pipeline

Slots are the six wire slots 1..6 (L3 L2 L1 R1 R2 R3). Bands: 1 near (<0.9 m), 2 (<1.6), 3 (<2.5),
4 far (<=4 m). Slot 0 has no servo.

Transports:
  default                 BLE to the live firmware (advertises "FEEL Puck"); disconnect the phone first
  --serial /dev/cu.XXX    bench firmware over USB (ARM / B / KEEP / STOP)
  --dry-run               print the packet and the pin picture, touch no hardware

The firmware reports the bands it is holding; the tool compares them with what you asked. It cannot
see the servo move. Watch the puck.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / 'ios' / 'Shared' / 'FeelCore'
REPLAY = PACKAGE / '.build' / 'release' / 'feel-replay'

SERVICE = '7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000'
COMMAND = '7D2A0002-5C6B-4F9A-8E21-0BCE7F0A1000'
STATUS = '7D2A0003-5C6B-4F9A-8E21-0BCE7F0A1000'
SLOTS = [1, 2, 3, 4, 5, 6]
LABELS = {1: 'L3', 2: 'L2', 3: 'L1', 4: 'R1', 5: 'R2', 6: 'R3'}
GPIO = {1: 33, 2: 25, 3: 26, 4: 27, 5: 14, 6: 13}
BAND_EDGES = [(0.9, 1), (1.6, 2), (2.5, 3), (4.0, 4)]
WATCHDOG_S = 0.5
PERIOD_S = 0.1


def parse_pins(specs: list[str]) -> list[int]:
    """'3:2' -> bands list of 7 with slot 3 at band 2. Repeated slots are an error."""
    bands = [0] * 7
    seen = set()
    for spec in specs:
        try:
            slot_text, band_text = spec.split(':')
            slot, band = int(slot_text), int(band_text)
        except ValueError:
            raise SystemExit(f'--pins wants SLOT:BAND, got {spec!r}')
        if slot not in SLOTS:
            raise SystemExit(f'slot {slot} is not a physical pin; use 1..6 (slot 0 has no servo)')
        if not 1 <= band <= 4:
            raise SystemExit(f'band {band} out of range; use 1 (near) .. 4 (far)')
        if slot in seen:
            raise SystemExit(f'slot {slot} given twice')
        seen.add(slot)
        bands[slot] = band
    return bands


def parse_obstacles(specs: list[str]) -> list[dict]:
    obstacles = []
    for spec in specs:
        parts = spec.split(':')
        try:
            if len(parts) not in (2, 3):
                raise ValueError('unexpected obstacle fields')
            bearing, distance = float(parts[0]), float(parts[1])
            height = float(parts[2]) if len(parts) > 2 else 1.0
        except (ValueError, IndexError):
            raise SystemExit(f'--lidar wants BEARING:DISTANCE[:HEIGHT], got {spec!r}')
        if not all(math.isfinite(value) for value in (bearing, distance, height)):
            raise SystemExit('obstacle bearing, distance, and height must be finite')
        if not -45 <= bearing <= 45:
            raise SystemExit(f'bearing {bearing} is outside the pins\' field (-45..45 degrees)')
        if not 0 < distance <= 4:
            raise SystemExit(f'distance {distance} must be in (0, 4] metres')
        obstacles.append({'bearingDegrees': bearing, 'distance': distance, 'height': height})
    return obstacles


def band_of(distance: float | None) -> int:
    if distance is None:
        return 0
    for edge, band in BAND_EDGES:
        if distance < edge or (band == 4 and distance <= edge):
            return band
    return 0


def packet(seq: int, bands: list[int], highlight: int = 255) -> bytes:
    assert len(bands) == 7 and all(0 <= b <= 4 for b in bands)
    return bytes([seq & 0xFF] + bands + [highlight])


def picture(bands: list[int], highlight: int = 255, title: str = '') -> str:
    """Pins seen from the wearer's side: columns L3..R3, rows far (4) to near (1)."""
    lines = []
    if title:
        lines.append(title)
    lines.append('        ' + ' '.join(f'{LABELS[s]:>2}' for s in SLOTS))
    for band in (4, 3, 2, 1):
        edge = {4: 'far ', 3: '    ', 2: '    ', 1: 'near'}[band]
        cells = []
        for s in SLOTS:
            up = bands[s] == band
            cells.append((' ▲' if highlight == s else ' █') if up else ' ·')
        lines.append(f'{edge} {band}  ' + ' '.join(cells))
    lines.append('        ' + ' '.join(f'{s:>2}' for s in SLOTS) + '   wire slot')
    return '\n'.join(lines)


def decode_status(data: bytes) -> dict:
    if len(data) < 15 or data[0] != 1:
        return {'raw': data.hex()}
    return {
        'connected': bool(data[1]), 'active': bool(data[2]), 'sequenceValid': bool(data[3]),
        'lastSequence': data[4], 'highlight': data[5], 'benchArmed': bool(data[6]),
        'output': {0: 'disabled', 1: 'ready', 2: 'fault'}.get(data[7], str(data[7])),
        'bands': list(data[8:15]),
    }


def lidar_to_bands(obstacles: list[dict], build: bool) -> tuple[list[int], list[float | None]]:
    if not REPLAY.exists() or build:
        print('Building feel-replay (production projector and encoder)...', flush=True)
        subprocess.run(['swift', 'build', '-c', 'release', '--product', 'feel-replay', '--package-path', str(PACKAGE)],
                       check=True, stdout=subprocess.DEVNULL)
    command = {'op': 'lidar', 'seq': 0, 'obstacles': obstacles}
    result = subprocess.run([str(REPLAY), 'stdio'], input=json.dumps(command) + '\n', text=True,
                            stdout=subprocess.PIPE, check=True)
    reply = json.loads(result.stdout.strip().splitlines()[-1])
    if not reply.get('valid'):
        raise SystemExit(f"projector rejected the scene: {reply.get('error')}")
    return reply['bands'], reply['distances']


def describe_expectation(bands: list[int]) -> str:
    up = [f'{LABELS[s]} (slot {s}, GPIO{GPIO[s]}) to band {bands[s]}' for s in SLOTS if bands[s]]
    return 'Expect to rise: ' + ('; '.join(up) if up else 'nothing') + '. Every other pin stays down.'


def compare(expected: list[int], reported: list[int]) -> list[str]:
    problems = []
    for s in SLOTS:
        if expected[s] != reported[s]:
            problems.append(f'{LABELS[s]} slot {s}: asked band {expected[s]}, firmware holds band {reported[s]}')
    if reported[0]:
        problems.append(f'slot 0 reports band {reported[0]} but has no servo')
    return problems


async def run_ble(bands: list[int], highlight: int, seconds: float, name: str) -> int:
    from bleak import BleakClient, BleakScanner

    print(f'Scanning for "{name}"... (the phone app must be disconnected; the puck accepts one central)', flush=True)
    device = await BleakScanner.find_device_by_name(name, timeout=10)
    if device is None:
        print(f'No BLE device named "{name}" found. Is the puck powered and not connected to the phone?')
        return 2
    # Samples are collected only during the hold. Clear packets also report active=True,
    # so an "active" status alone cannot distinguish hold evidence from cleanup.
    statuses: list[tuple[float, dict]] = []
    collecting = True
    seq = 1
    last_sent: tuple[int, float] | None = None
    cleanup_failed = False
    hold_failed = False
    operation_timeout = 0.15  # keep each operation bounded below the 500 ms watchdog

    def on_status(_, data: bytearray):
        if collecting:
            statuses.append((time.monotonic(), decode_status(bytes(data))))

    async with BleakClient(device) as client:
        notified = False
        try:
            await asyncio.wait_for(client.start_notify(STATUS, on_status), 5.0)
            notified = True
            deadline = time.monotonic() + seconds
            print(f'Connected. Holding for {seconds:.1f} s (packets every {int(PERIOD_S*1000)} ms; the watchdog drops pins after {int(WATCHDOG_S*1000)} ms of silence).', flush=True)
            while time.monotonic() < deadline:
                sent_seq, sent_at = seq, time.monotonic()
                seq = (seq + 1) % 256
                await asyncio.wait_for(client.write_gatt_char(
                    COMMAND, packet(sent_seq, bands, highlight), response=False), operation_timeout)
                last_sent = (sent_seq, sent_at)
                await asyncio.sleep(PERIOD_S)
            try:
                data = await asyncio.wait_for(client.read_gatt_char(STATUS), operation_timeout)
                on_status(None, data)
            except Exception as error:
                print(f'(status read failed: {error}; checking correlated notifications)')
        except Exception as error:
            hold_failed = True
            print(f'Hold failed: {error}')
        finally:
            # Freeze evidence before lowering pins. Try every neutral even if a previous
            # write failed. Context exit disconnects; the firmware watchdog is the fallback.
            collecting = False
            evidence_time = time.monotonic()
            for _ in range(3):
                clear_seq = seq
                seq = (seq + 1) % 256
                try:
                    await asyncio.wait_for(client.write_gatt_char(
                        COMMAND, packet(clear_seq, [0] * 7), response=False), operation_timeout)
                except Exception as error:
                    cleanup_failed = True
                    print(f'Neutral write failed: {error}')
                await asyncio.sleep(PERIOD_S)
            if notified:
                try:
                    await asyncio.wait_for(client.stop_notify(STATUS), operation_timeout)
                except Exception as error:
                    cleanup_failed = True
                    print(f'Status cleanup failed: {error}')

    if hold_failed or cleanup_failed:
        print('Test failed. Disconnected; neutral delivery was not fully verified. Check the puck before continuing.')
        return 1
    correlated = [] if last_sent is None else [
        status for received_at, status in statuses
        if status.get('lastSequence') == last_sent[0]
        and last_sent[1] <= received_at <= evidence_time
        and evidence_time - last_sent[1] < WATCHDOG_S
        and evidence_time - received_at < WATCHDOG_S
    ]
    if not correlated:
        print('No fresh status acknowledged the final hold packet; the requested hold is unverified.')
        return 1
    last = correlated[-1]
    problems = compare(bands, last['bands'])
    for field, expected in (('connected', True), ('active', True), ('sequenceValid', True),
                            ('benchArmed', False), ('output', 'ready'), ('highlight', highlight)):
        if last.get(field) != expected:
            problems.append(f'{field}: expected {expected}, firmware reports {last.get(field)}')
    print(picture(last['bands'], last['highlight'], 'Firmware reported during hold:'))
    if problems:
        print('MISMATCH between request and firmware:\n  ' + '\n  '.join(problems))
        return 1
    print('Firmware reported the requested pins with output ready. Physical movement remains unverified; observe the puck.')
    return 0


def run_serial(bands: list[int], highlight: int, seconds: float, port: str) -> int:
    import serial

    print('Bench firmware over USB. Opening the port may reset the board.', flush=True)
    with serial.Serial(port, 115200, timeout=0.05, write_timeout=0.2) as connection:
        time.sleep(2)
        connection.reset_input_buffer()

        def command(text: str) -> None:
            connection.write((text + '\n').encode('ascii'))
            deadline = time.monotonic() + 0.35
            while time.monotonic() < deadline:
                response = connection.readline().decode('ascii', errors='replace').strip()
                if response == 'ok':
                    return
                if response:
                    raise RuntimeError(f'{text}: {response}')
            raise TimeoutError(f'No acknowledgment for {text}')

        try:
            connection.write(b'STATUS\n')
            deadline = time.monotonic() + 0.35
            ready = False
            while time.monotonic() < deadline:
                response = connection.readline().decode('ascii', errors='replace').strip()
                if response.startswith('STATUS '):
                    ready = 'outputState=1(' in response
                    if 'motion comes from live BLE' in response or 'live adapter' in response:
                        break
                if response.startswith('ERROR live adapter'):
                    print('This board runs the live firmware: serial motion is refused. Use BLE (drop --serial).')
                    return 2
            if not ready:
                print('Output is disabled or faulted on this board; no motion sent.')
                return 1
            command('ARM')
            for s in SLOTS:
                if bands[s]:
                    command(f'B {s} {bands[s]}')
            if highlight in SLOTS:
                command(f'HL {highlight}')
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                time.sleep(PERIOD_S)
                command('KEEP')
            print('Bench commands acknowledged. Serial mode does not verify held bands or physical movement.')
            return 0
        finally:
            connection.write(b'STOP\n')
            connection.flush()


class PinArgumentParser(argparse.ArgumentParser):
    def _parse_optional(self, arg_string):
        # Negative BEARING:DISTANCE tokens are values, not short options.
        if arg_string.startswith('-') and not arg_string.startswith('--') and ':' in arg_string:
            return None
        return super()._parse_optional(arg_string)


def main(argv: list[str] | None = None) -> int:
    parser = PinArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument('--pins', nargs='+', metavar='SLOT:BAND', help='raise these wire slots to these bands')
    what.add_argument('--lidar', nargs='+', metavar='BEARING:DISTANCE', help='obstacles seen by the camera; the projector decides the pins')
    what.add_argument('--each', action='store_true', help='walk every slot 1..6 at the given --band, one at a time')
    parser.add_argument('--band', type=int, default=4, help='band for --each (default 4, the full rise)')
    parser.add_argument('--tap', type=int, metavar='SLOT', help='also tap (highlight) this slot; it must be raised')
    parser.add_argument('--seconds', type=float, default=3.0, help='how long to hold each picture (0.5..20)')
    parser.add_argument('--serial', metavar='PORT', help='use the bench firmware over this USB port instead of BLE')
    parser.add_argument('--name', default='FEEL Puck', help='BLE name to connect to')
    parser.add_argument('--build', action='store_true', help='rebuild feel-replay before a --lidar run')
    parser.add_argument('--dry-run', action='store_true', help='print what would be sent; no hardware')
    args = parser.parse_args(argv)
    if not 0.5 <= args.seconds <= 20:
        parser.error('--seconds must be within 0.5..20')
    if args.each and not 1 <= args.band <= 4:
        parser.error('--band must be 1..4')

    pictures: list[tuple[list[int], str]] = []
    if args.pins:
        pictures.append((parse_pins(args.pins), 'Requested:'))
    elif args.lidar:
        obstacles = parse_obstacles(args.lidar)
        bands, distances = lidar_to_bands(obstacles, args.build)
        shown = ', '.join(f'{LABELS[s]} {distances[s]:.2f} m' for s in SLOTS if distances[s] is not None) or 'nothing in the field'
        pictures.append((bands, f'Projector saw: {shown}'))
    else:
        for s in SLOTS:
            bands = [0] * 7
            bands[s] = args.band
            pictures.append((bands, f'Slot {s} ({LABELS[s]}, GPIO{GPIO[s]}) alone:'))

    highlight = args.tap if args.tap is not None else 255
    if highlight != 255 and (highlight not in SLOTS or any(b[highlight] == 0 for b, _ in pictures)):
        parser.error('--tap must name a raised slot 1..6')

    worst = 0
    for bands, title in pictures:
        print(picture(bands, highlight, title))
        print(describe_expectation(bands))
        print('packet: ' + packet(0, bands, highlight).hex() + '  (seq, b0..b6, highlight)')
        if args.dry_run:
            print()
            continue
        if args.serial:
            code = run_serial(bands, highlight, args.seconds, args.serial)
        else:
            code = asyncio.run(run_ble(bands, highlight, args.seconds, args.name))
        worst = max(worst, code)
        print()
        if code != 0:
            break  # Do not start another hold after a failed or unverified test.
        if len(pictures) > 1:
            time.sleep(1.0)  # let the pins fall before the next slot
    return worst


if __name__ == '__main__':
    sys.exit(main())

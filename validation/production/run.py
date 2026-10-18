#!/usr/bin/env python3
"""Production Swift -> binary packet -> production C++ replay. No device IO."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import selectors
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

class Peer:
    def __init__(self, command):
        self.process = subprocess.Popen(command, text=True, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=sys.stderr, bufsize=1)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
    def ask(self, line):
        self.process.stdin.write(line + '\n')
        self.process.stdin.flush()
        if not self.selector.select(timeout=10):
            raise RuntimeError('Production adapter did not respond within 10 seconds')
        response = self.process.stdout.readline()
        if not response:
            raise RuntimeError('Production adapter exited before responding')
        return json.loads(response)
    def close(self):
        self.selector.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()

class Replay:
    def __init__(self, swift, firmware):
        self.swift = Peer([str(swift), 'stdio'])
        self.firmware = Peer([str(firmware)])
        self.steps = []
        self.checks = 0
        self.angles = [20.] * 7
        self.previous = [20.] * 7
        self.last_ms = 0
        self.stalled = set()
    def close(self):
        self.swift.close()
        self.firmware.close()
    def swift_call(self, **fields):
        return self.swift.ask(json.dumps(fields, allow_nan=False))
    def expect(self, actual, expected, context):
        self.checks += 1
        if actual != expected:
            raise AssertionError(f'{context}: expected {expected!r}, got {actual!r}')
    def command(self, line, name='', **expected):
        state = self.firmware.ask(line)
        if 'result' not in expected and expected.get('accepted') is not False:
            expected['result'] = 'ok'
        for key, value in expected.items():
            actual = (state.get('result') == 'ok') if key == 'accepted' else state.get(key)
            self.expect(actual, value, f'{name or line}: {key}')
        self.expect(all(0 <= angle <= 175 for angle in state['angles_deg']), True,
                    f'{name or line}: 175-degree assumed envelope')
        self.expect(all(650 <= pulse <= 2500 for pulse in state['pulses_us']), True,
                    f'{name or line}: FS0307 assumed wide pulse envelope')
        # Synthetic speed-limited motor model integrates the PREVIOUS command.
        # 300deg/s is illustrative, not a measured FS0307 rating; jam is injected.
        now = int(line.split()[1])
        elapsed = ((now - self.last_ms) & 0xffffffff) / 1000.
        if elapsed > 10:  # Explicit independent replay/reset, not centuries of motion.
            elapsed = 0
        for i in range(7):
            if i not in self.stalled:
                delta = self.previous[i] - self.angles[i]
                self.angles[i] += max(-300*elapsed, min(300*elapsed, delta))
        self.previous = state['angles_deg'][:]
        self.last_ms = now
        self.steps.append({'name': name or line, 'command': line, 'state': state,
                           'estimated_motor_deg': [round(a, 3) for a in self.angles],
                           'injected_stall_columns': sorted(self.stalled)})
        return state
    def reset(self, ms=0):
        self.command(f'RESET {ms}')
        self.command(f'CONNECT {ms}', bands=[0]*7, highlight=255)
        self.angles = [20.] * 7
        self.previous = [20.] * 7
        self.last_ms = ms
        self.stalled.clear()
    def packet(self, ms, hex_string, name='', **expected):
        return self.command('PACKET ' + str(ms) + ' ' + ' '.join(str(b) for b in bytes.fromhex(hex_string)),
                            name=name, **expected)
    def perceive(self, ms, seq, distances, **kwargs):
        reply = self.swift_call(op='perceive', seq=seq, now=ms/1000,
                                frameTimestamp=kwargs.pop('frameTimestamp', ms/1000),
                                tracking=kwargs.pop('tracking', True), distances=distances, **kwargs)
        if not reply.get('valid', True) or 'hex' not in reply:
            raise AssertionError(f'Perception adapter failed: {reply}')
        return reply


def run(replay):
    r = replay
    vectors_path = ROOT / 'protocol/vectors.json'
    vectors = json.loads(vectors_path.read_text())
    if not vectors['valid'] or not vectors['invalid']:
        raise AssertionError('Empty contract vectors cannot pass')
    for v in vectors['valid']:
        decoded = r.swift_call(op='decode', hex=v['hex'])
        for key in ('seq', 'bands', 'highlight'):
            r.expect(decoded[key], v[key], f"Swift decode {v['id']} {key}")
        encoded = r.swift_call(op='encode', seq=v['seq'], bands=v['bands'], highlight=v['highlight'])
        r.expect(encoded['hex'], v['hex'], 'Swift golden bytes '+v['id'])
        r.reset()
        effective = v['highlight'] if v['highlight'] < 7 and v['bands'][v['highlight']] > 0 else 255
        r.packet(0, encoded['hex'], 'Golden '+v['id'], accepted=True, bands=v['bands'], highlight=effective)
    for v in vectors['invalid']:
        r.expect(r.swift_call(op='decode', hex=v['hex'])['valid'], False, 'Swift rejects '+v['id'])
        r.reset()
        r.packet(0, v['hex'], 'Malformed '+v['id'], accepted=False, bands=[0]*7,
                 result='bad_length' if len(v['hex']) != 18 else 'bad_band' if any(b > 4 for b in bytes.fromhex(v['hex'])[1:8]) else 'bad_highlight')
    # Contract equivalence over independent deterministic legal and illegal inputs.
    rng = random.Random(20261016)
    for index in range(160):
        bands = [rng.randrange(5) for _ in range(7)]
        seq = rng.randrange(256)
        hl = rng.choice([255, *range(7)])
        encoded = r.swift_call(op='encode', seq=seq, bands=bands, highlight=hl)
        r.expect(bytes.fromhex(encoded['hex']), bytes([seq,*bands,hl]), 'random byte contract')
        r.reset()
        r.packet(0, encoded['hex'], f'Contract sample {index}', accepted=True, bands=bands)
    r.reset()
    bands = [0,2,3,4,4,0,0]
    reply = r.perceive(100,254,[.2,.9,1.6,2.5,4,4.001,None])
    r.expect(reply['bands'], bands, 'distance interval edges')
    r.packet(100, reply['hex'], 'Swift perception → firmware', accepted=True, bands=bands)
    reply = r.perceive(200,255,[1]*7)
    r.packet(200, reply['hex'], 'Sequence 255', accepted=True, bands=[0]+[2]*6)
    reply = r.perceive(300,0,[2]*7)
    r.packet(300, reply['hex'], 'Sequence wrap 255 → 0', accepted=True, bands=[0]+[3]*6)
    r.packet(350, reply['hex'], 'Duplicate does not refresh', accepted=False, bands=[0]+[3]*6, result='duplicate')
    old = r.swift_call(op='encode',seq=255,bands=[4]*7,highlight=255)
    r.packet(400,old['hex'],'Reordered packet', accepted=False, bands=[0]+[3]*6, result='stale_sequence')
    r.command('TICK 799','Before watchdog', bands=[0]+[3]*6, active=True)
    r.command('TICK 800','Exact 500ms watchdog', bands=[0]*7, highlight=255, active=False)
    r.packet(801,old['hex'],'Fresh baseline after watchdog',accepted=True,bands=[4]*7)
    r.command('DISCONNECT 802','Immediate disconnect',bands=[0]*7,highlight=255)
    r.packet(803,old['hex'],'Packets while disconnected',accepted=False,bands=[0]*7,result='disconnected')
    r.reset(1000)
    for n,(name,opts) in enumerate([
        ('Tracking lost',{'tracking':False}),
        ('Depth stale',{'frameTimestamp':.5}),
        ('Depth from future',{'frameTimestamp':50}),
    ]):
        ms=1000+n*100
        p=r.perceive(ms,n,[.5]*7,**opts)
        r.expect(p['bands'],[0]*7,name)
        r.packet(ms,p['hex'],name,accepted=True,bands=[0]*7,highlight=255)
    r.reset(2000)
    for index,(bearing,column) in enumerate([(-45,1),(0,4),(45,6)]):
        ms=2000+index*100
        p=r.perceive(ms,index,[2]*7,target={'bearingDegrees':bearing,'distance':2,'timestamp':ms/1000})
        r.expect(p['highlight'],column,'target bearing')
        r.packet(ms,p['hex'],f'Find target {bearing}°',accepted=True,highlight=column)
    p=r.perceive(2300,3,[2]*7,target={'bearingDegrees':0,'distance':2,'timestamp':1.7})
    r.expect(p['highlight'],255,'Expired target')
    r.packet(2300,p['hex'],'Target disappeared',highlight=255)
    p=r.perceive(2400,4,[2]*7,target={'bearingDegrees':46,'distance':2,'timestamp':2.4})
    r.expect(p['highlight'],255,'Out of FOV target')
    r.packet(2400,p['hex'],'Target outside FOV',highlight=255)
    # No-checksum limitation must be visible: a legal corruption is accepted.
    r.reset(3000)
    p=r.swift_call(op='encode',seq=1,bands=[1]*7,highlight=255)
    corrupt=bytearray.fromhex(p['hex']);corrupt[4]=4
    r.packet(3000,corrupt.hex(),'Legal-byte corruption is undetectable',accepted=True,bands=[1,1,1,4,1,1,1])
    # Motor stall is deliberately invisible to sensorless firmware.
    r.stalled={3}
    r.command('TICK 3100','Injected column 3 jam (SIMULATED; firmware cannot detect)',bands=[1,1,1,4,1,1,1])
    r.command('TICK 3500','Watchdog commands neutral; jam does not imply physical return',bands=[0]*7)
    # Explicit commanded-angle assertions exercise the production scheduler.
    r.reset(4000)
    p=r.swift_call(op='encode',seq=1,bands=[1,2,3,4,0,0,0],highlight=0)
    r.packet(4000,p['hex'],'Band centres plus first highlight dip',accepted=True,
             angles_deg=[13,58,116,174,29,29,29],tap_active=True)
    r.command('TICK 4100','Tap returns after100ms',angles_deg=[0,58,116,174,29,29,29],tap_active=False)
    r.command('TICK 4500','Timeout gaps by former band',angles_deg=[29,29,87,145,29,29,29],bands=[0]*7)
    r.reset(0xfffffff0)
    p=r.swift_call(op='encode',seq=42,bands=[1]*7,highlight=255)
    r.packet(0xfffffff0,p['hex'],'millis rollover baseline',accepted=True)
    r.command('TICK 483','499ms across rollover',active=True,bands=[1]*7)
    r.command('TICK 484','500ms across rollover',active=False,bands=[0]*7)
    if r.checks < 100 or not r.steps:
        raise AssertionError('Replay did not execute meaningful assertions')
    return {'schema':1,'label':'SIMULATION — compiled production logic, synthetic sensors and motors',
            'physical_hardware':'NOT VERIFIED','seed':20261016,'assertions':r.checks,
            'status':'PASS','vectors_sha256':hashlib.sha256(vectors_path.read_bytes()).hexdigest(),
            'motor_model':{'speed_deg_s':300,'measured':False,'jam_feedback':False},'steps':r.steps}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--swift',type=Path,default=ROOT/'ios/Shared/FeelCore/.build/debug/feel-replay')
    p.add_argument('--firmware',type=Path,default=ROOT/'firmware/build/feel-sim')
    p.add_argument('--output',type=Path,default=ROOT/'.artifacts/production')
    args=p.parse_args()
    for binary in (args.swift,args.firmware):
        if not binary.is_file():
            p.error(f'Missing compiled production adapter: {binary}; build it first')
    r=Replay(args.swift.resolve(),args.firmware.resolve())
    try:
        report=run(r)
    finally:
        r.close()
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    template=(Path(__file__).parent/'viewer.html').read_text()
    (args.output/'index.html').write_text(template.replace('__REPORT__',json.dumps(report).replace('<','\\u003c')))
    print(f"PASS: {report['assertions']} cross-layer assertions, {len(report['steps'])} firmware states; physical NOT VERIFIED")
    return 0
if __name__=='__main__':
    raise SystemExit(main())

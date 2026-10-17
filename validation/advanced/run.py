#!/usr/bin/env python3
"""V3 black-box checks against production Swift and the production C++ puck."""
from __future__ import annotations
import argparse
import base64
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'validation/production'))
from run import Replay

def pose(z=2):
    return {'position':[0,0,z], 'right':[1,0,0], 'up':[0,1,0], 'back':[0,0,1]}

def run(r):
    def call(op, valid=True, **fields):
        reply = r.swift_call(op=op, **fields)
        r.expect(reply['valid'], valid, op+' validity')
        return reply
    voice_cases = [
        ('en','remember Desk',{'action':'remember','name':'Desk'}),
        ('en','recall Desk',{'action':'recall','name':'Desk'}),
        ('en','return',{'action':'return'}), ('en','stop',{'action':'stop'}),
        ('en','list places',{'action':'listPlaces'}),
        ('en','find chair',{'action':'find','mode':'chair'}),
        ('en','find barcode',{'action':'find','mode':'barcode'}),
        ('es','recuerda Entrada',{'action':'remember','name':'Entrada'}),
        ('es','recupera Entrada',{'action':'recall','name':'Entrada'}),
        ('es','vuelve',{'action':'return'}), ('es','para',{'action':'stop'}),
        ('es','lista lugares',{'action':'listPlaces'}),
        ('es','busca silla',{'action':'find','mode':'chair'}),
        ('es','busca código',{'action':'find','mode':'barcode'}),
    ]
    for language, text, expected in voice_cases:
        r.expect(call('voiceParse',text=text,language=language,final=True)['intent'],expected,'voice grammar '+text)
    for text in ['', 'remember', 'recall', 'find unicorn', 'stop and return', 'x'*257, 'remember bad\nname']:
        call('voiceParse',valid=False,text=text,language='en',final=True)
    call('voiceParse',valid=False,text='stop',language='en',final=False)
    call('voiceParse',valid=False,text='stop',language='xx',final=True)

    # Archive bytes are deliberately synthetic; the native adapter additionally
    # securely decodes ARWorldMap and checks its real marker anchor.
    map_id='11111111-1111-4111-8111-111111111111'
    anchor_id='22222222-2222-4222-8222-222222222222'
    other_id='33333333-3333-4333-8333-333333333333'
    call('memoryBegin',session='archive-source')
    common=dict(session='archive-source',now=1,frameTimestamp=1,tracking=True)
    call('memoryRemember',id='entry',name='Entry',pose=pose(0),**common)
    call('memorySetReturn',pose=pose(0),**common)
    call('memoryRemember',id='desk',name='Desk',pose=pose(-2),**common)
    call('memoryRecall',id='entry')
    archive=call('archiveExport',mapID=map_id,anchorID=anchor_id,
                 mapDataBase64=base64.b64encode(b'SYNTHETIC MAP BYTES, NOT ARKIT').decode())['archive']
    r.expect(archive['version'],1,'versioned archive')
    r.expect(len(archive['bookmarks']),2,'multiple archived places')
    for forbidden in ['session','activeID','selectedID']:
        r.expect(forbidden in archive,False,'no persisted active session/intent '+forbidden)
    r.expect(archive['returnPoint'],{'x':0,'y':0,'z':0},'return point preserved')
    original=call('memoryState')['memory']
    malformed=[]
    for key,value in [('version',2),('mapID','not-a-uuid'),('anchorID','bad'),('mapDataBase64','%invalid%')]:
        bad=copy.deepcopy(archive);bad[key]=value;malformed.append(bad)
    bad=copy.deepcopy(archive);bad['bookmarks'][1]['id']='entry';malformed.append(bad)
    bad=copy.deepcopy(archive);bad['bookmarks'][0]['name']='bad\nname';malformed.append(bad)
    bad=copy.deepcopy(archive);bad['bookmarks'][0]['position']['x']=10001;malformed.append(bad)
    for index,bad in enumerate(malformed):
        call('archiveImport',valid=False,archive=bad,session=f'rejected-{index}',now=2)
        r.expect(call('memoryState')['memory'],original,'invalid archive import is atomic')

    session='restored-demo'
    call('archiveImport',archive=archive,session=session,now=10)
    r.expect(len(call('memoryState')['memory']['bookmarks']),0,'coordinates withheld until relocalization')
    call('memoryRecall',valid=False,id='entry')
    def observe(ms, expected, **changes):
        fields=dict(session=session,mapID=map_id,anchorID=anchor_id,now=ms/1000,
                    frameTimestamp=ms/1000,tracking=True,relocalizing=False,pose=pose())
        fields.update(changes)
        reply=call('archiveObserve',**fields)
        r.expect(reply['restoreState'],expected,'restore gate at '+str(ms))
        return reply
    observe(10000,'awaitingRelocalization') # Normal alone cannot certify map identity.
    observe(10100,'awaitingRelocalization',tracking=False,relocalizing=True)
    observe(10200,'awaitingRelocalization',mapID=other_id)
    observe(10300,'awaitingRelocalization',anchorID=other_id)
    observe(10400,'awaitingRelocalization',session='wrong-session')
    observe(10500,'awaitingRelocalization',frameTimestamp=10)
    observe(10600,'awaitingRelocalization')
    observe(10800,'awaitingRelocalization')
    observe(11000,'awaitingRelocalization')
    observe(11099,'awaitingRelocalization')
    restored=observe(11101,'ready')
    r.expect(len(restored['memory']['bookmarks']),2,'places installed after settled tracking')
    r.expect(restored['memory'].get('activeID'),None,'restoring never auto-recalls')
    call('memoryRecall',id='entry')
    r.reset(11200)
    def memory_packet(ms, seq, name, tracking=True):
        reply=call('memoryGuide',seq=seq,session=session,now=ms/1000,frameTimestamp=ms/1000,
                   tracking=tracking,pose=pose(),distances=[None,None,.5,None,None,None,None])
        expected=[0,0,1,3,0,0,0] if tracking else [0]*7
        r.expect(reply['bands'],expected,name+' bands')
        r.expect(reply['highlight'],3 if tracking else 255,name+' highlight')
        r.packet(ms,reply['hex'],name,bands=expected,highlight=3 if tracking else 255,accepted=True)
        r.steps[-1]['advanced']=reply
    memory_packet(11200,1,'Restored place explicitly recalled through production packets')
    memory_packet(11300,2,'Tracking loss after restore still neutralizes every column',False)
    memory_packet(11400,3,'Tracking recovery reprojects the saved place')
    call('archiveCancel')
    r.expect(call('memoryState')['memory']['bookmarks'],[],'cancel clears coordinates')

    session='interrupted-settle'
    call('archiveImport',archive=archive,session=session,now=15)
    observe(15000,'awaitingRelocalization',tracking=False,relocalizing=True)
    observe(15100,'awaitingRelocalization')
    observe(16100,'awaitingRelocalization') # Missing observations cannot count as continuous tracking.
    observe(16200,'awaitingRelocalization')
    observe(16400,'awaitingRelocalization')
    observe(16601,'ready')
    call('archiveCancel')

    # No successful software gate can be carried into another session or past a
    # timeout/clock failure. These inputs are mocked evidence, not real AR frames.
    for kind, changes, when in [
        ('timeout',{},80001),
        ('backwards-clock',{},19000),
    ]:
        session='failed-'+kind
        call('archiveImport',archive=archive,session=session,now=20)
        observe(when,'failed',**changes)
        observe(when+1000,'failed')
        r.expect(call('memoryState')['memory']['bookmarks'],[],kind+' never installs coordinates')
    session='cancel-on-new-session'
    call('archiveImport',archive=archive,session=session,now=100)
    call('memoryBegin',session='fresh-world')
    observe(100100,'idle')
    r.expect(call('memoryState')['memory']['bookmarks'],[],'late map callback cannot restore old world')

    bands=[1,2,3,4,1,2,3]
    sequence=250
    def adaptive_packet(ms, now, profile, expected_hl, name, source=bands, source_hl=3,
                        identity='cadence', tap=None, angle=None):
        nonlocal sequence
        sequence=(sequence+1)%256
        reply=call('adaptive',seq=sequence,bands=source,highlight=source_hl,
                   profile=profile,session=identity,now=now)
        r.expect(reply['seq'],sequence,name+' sequence unchanged')
        r.expect(reply['bands'],source,name+' obstacle bands unchanged')
        r.expect(reply['highlight'],expected_hl,name+' effective highlight')
        expected=dict(bands=source,highlight=expected_hl,accepted=True)
        if tap is not None:expected['tap_active']=tap
        state=r.packet(ms,reply['hex'],name,**expected)
        if angle is not None:r.expect(state['angles_deg'][3],angle,name+' actual firmware angle')
        r.steps[-1]['advanced']={'profile':profile,'inputNow':now,**reply}
        return reply
    call('adaptiveReset');r.reset(50000)
    for dt in range(0,1300,100):
        dip=dt%600==0
        adaptive_packet(50000+dt,dt/1000,'standard',3,f'Standard cadence {dt} ms',
                        tap=dip,angle=107 if dip else 120)
    call('adaptiveReset');r.reset(60000)
    for dt in range(0,4900,100):
        enabled=dt%2400>=1800;dip=dt%2400==1800
        adaptive_packet(60000+dt,dt/1000,'reduced',3 if enabled else 255,
                        f'Reduced cadence {dt} ms',tap=dip,angle=107 if dip else 120)
    r.command('TICK 65300','500 ms watchdog after reduced stream stops',bands=[0]*7,highlight=255,active=False)
    call('adaptiveReset');r.reset(70000)
    for dt in range(0,7100,100):
        close=dt<1500 or dt>=5000
        source=[0,0,1 if close else 0,4,0,0,0]
        if dt<3900:highlight=3 if dt%2400>=1800 else 255
        elif dt<5000:highlight=3
        else:highlight=3 if dt-5000>=1800 else 255
        adaptive_packet(70000+dt,dt/1000,'automatic',highlight,
                        f'Automatic close-obstacle hysteresis {dt} ms',source=source)
    call('adaptiveReset');r.reset(80000)
    adaptive_packet(80000,0,'reduced',255,'New reduced session starts quiet')
    adaptive_packet(81900,1.9,'reduced',3,'Reduced highlight becomes eligible after quiet interval')
    adaptive_packet(82000,2,'reduced',255,'Session change restarts quiet interval',identity='new-cadence')
    adaptive_packet(83900,3.9,'reduced',3,'New session settled cadence',identity='new-cadence')
    adaptive_packet(84000,4,'reduced',255,'Changed target column restarts quiet interval',identity='new-cadence',source_hl=4)
    adaptive_packet(84100,4.1,'standard',4,'Explicit standard profile resumes target',identity='new-cadence',source_hl=4)
    adaptive_packet(84200,4,'standard',255,'Backwards app clock suppresses target',identity='new-cadence',source_hl=4)
    adaptive_packet(84300,4.3,'standard',255,'No source highlight stays absent',identity='new-cadence',source_hl=255)
    r.command('DISCONNECT 84400','Radio disconnect still commands neutral',bands=[0]*7,highlight=255)
    if r.checks<700 or len(r.steps)<120:
        raise AssertionError('Advanced replay did not exercise the intended state space')
    return {'schema':1,'version':'V3','label':'SIMULATION — production advanced logic and controller',
            'status':'PASS','physical_hardware':'NOT VERIFIED','assertions':r.checks,
            'voice_cases':len(voice_cases),'seed':20261016,
            'mocked':['speech transcripts','AR map bytes','relocalization evidence','poses','motor motion'],
            'motor_model':{'speed_deg_s':300,'measured':False,'jam_feedback':False},'steps':r.steps}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--swift',type=Path,default=ROOT/'ios/Shared/FeelCore/.build/debug/feel-replay')
    p.add_argument('--firmware',type=Path,default=ROOT/'firmware/build/feel-sim')
    p.add_argument('--output',type=Path,default=ROOT/'.artifacts/advanced')
    args=p.parse_args()
    for binary in (args.swift,args.firmware):
        if not binary.is_file():p.error(f'Missing compiled production binary: {binary}')
    replay=Replay(args.swift.resolve(),args.firmware.resolve())
    try:report=run(replay)
    finally:replay.close()
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    template=(Path(__file__).parent/'viewer.html').read_text()
    (args.output/'index.html').write_text(template.replace('__REPORT__',json.dumps(report).replace('<','\\u003c')))
    print(f"PASS: {report['assertions']} advanced cross-layer assertions, {len(report['steps'])} firmware states; physical NOT VERIFIED")
    return 0

if __name__=='__main__':raise SystemExit(main())

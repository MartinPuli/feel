#!/usr/bin/env python3
"""Remember/move/recall against production Swift and the production C++ puck."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'validation/production'))
from run import Replay

def pose(x=0,y=0,z=0,yaw=0):
    a=math.radians(yaw);c=math.cos(a);s=math.sin(a)
    return {'position':[x,y,z],'right':[c,0,-s],'up':[0,1,0],'back':[s,0,c]}

def run(r):
    session='demo-a'; ms=1000; seq=0
    def call(op,valid=True,**fields):
        reply=r.swift_call(op=op,**fields)
        r.expect(reply['valid'],valid,op+' validity')
        return reply
    def capture(op,location,**fields):
        return call(op,session=session,now=ms/1000,frameTimestamp=ms/1000,
                    tracking=True,pose=location,**fields)
    def guide(name,location,expected_state,expected_bands,expected_highlight,**fields):
        nonlocal ms,seq
        ms+=100;seq=(seq+1)%256
        args=dict(seq=seq,session=session,now=ms/1000,frameTimestamp=ms/1000,
                  tracking=True,pose=location,distances=[None]*7,floorCalibrated=True)
        args.update(fields)
        reply=call('memoryGuide',**args)
        r.expect(reply['memoryState'],expected_state,name+' memory state')
        r.expect(reply['bands'],expected_bands,name+' Swift bands')
        r.expect(reply['highlight'],expected_highlight,name+' Swift highlight')
        r.packet(ms,reply['hex'],name,bands=expected_bands,highlight=expected_highlight,accepted=True)
        r.steps[-1].update(memory=reply,pose=location)
        return reply
    zero=[0]*7
    r.reset(ms)
    call('memoryBegin',session=session)
    capture('memoryRemember',pose(),id='entry',name='Entry')
    capture('memorySetReturn',pose())
    capture('memoryRemember',pose(2,0,0),id='desk',name='Desk')
    r.expect(len(call('memoryState')['memory']['bookmarks']),2,'two bookmarks')
    call('memoryRecall',id='entry')
    guide('Recall Entry from two metres ahead',pose(0,0,2),'guiding',[0,0,0,3,0,0,0],3)
    guide('Translation reprojects target left',pose(1,0,2),'guiding',[0,3,0,0,0,0,0],1)
    guide('90 degree rotation uses world coordinates',pose(2,0,0,90),'guiding',[0,0,0,3,0,0,0],3)
    guide('180 degree rotation uses world coordinates',pose(0,0,-2,180),'guiding',[0,0,0,3,0,0,0],3)
    obstacles=[.5,1,2,3,None,None,None]; obstacle_bands=[1,2,3,4,0,0,0]
    guide('Target behind: obstacle sensing continues',pose(0,0,-2),'behind',obstacle_bands,255,distances=obstacles)
    a=math.radians(60)
    guide('Target outside field: no false edge highlight',pose(-2*math.sin(a),0,2*math.cos(a)),'outsideFieldOfView',zero,255)
    guide('Farther than four metres is not a false range',pose(0,0,5),'beyondRange',zero,255)
    guide('Different floor is not an arrival',pose(0,2,0),'differentLevel',zero,255)
    guide('Arrival suppresses target tapping',pose(0,0,.2),'arrived',zero,255)
    guide('Nearer obstacle preserved under target',pose(0,0,2),'guiding',[0,0,0,1,0,0,0],3,distances=[None,None,None,.5,None,None,None])
    guide('Tracking lost: every pin neutral',pose(0,0,2),'trackingLost',zero,255,tracking=False,distances=[.5]*7)
    guide('Tracking recovered in the same session',pose(0,0,2),'guiding',[0,0,0,3,0,0,0],3)
    guide('Stale pose cannot guide',pose(0,0,2),'stalePose',zero,255,frameTimestamp=0,distances=[.5]*7)
    invalid=pose();invalid['right']=[2,0,0]
    guide('Invalid camera basis cannot guide',invalid,'invalidPose',zero,255,distances=[.5]*7)
    guide('Old-session pose cannot guide',pose(0,0,2),'sessionMismatch',zero,255,session='other',distances=[.5]*7)
    # Exact internal sector edges and small offsets, using independently constructed poses.
    for index in range(1,7):
        edge=-45+90*index/7
        for delta,column in [(-.0001,index-1),(0,index),(.0001,index)]:
            angle=math.radians(edge+delta)
            bands=zero.copy();bands[column]=3
            guide(f'Sector boundary {index} ({delta:+.4f} degrees)',pose(-2*math.sin(angle),0,2*math.cos(angle)),
                  'guiding',bands,column)
    for angle,column in [(-45,0),(45,6)]:
        rad=math.radians(angle);bands=zero.copy();bands[column]=3
        guide(f'Inclusive field edge {angle}',pose(-2*math.sin(rad),0,2*math.cos(rad)),'guiding',bands,column)
    call('memorySelect',id='desk');call('memoryRecall')
    guide('Recall second bookmark after selection',pose(2,0,2),'guiding',[0,0,0,3,0,0,0],3)
    call('memoryRename',id='desk',name='Table')
    reply=call('memoryState');r.expect([b['name'] for b in reply['memory']['bookmarks']],['Entry','Table'],'rename')
    call('memoryRename',valid=False,id='desk',name='entry')
    capture('memoryRemember',pose(),valid=False,id='entry',name='Duplicate ID')
    capture('memoryRemember',pose(),valid=False,id='bad name',name='Invalid ID')
    capture('memoryRemember',pose(),valid=False,id='bad',name='\n')
    r.expect(len(call('memoryState')['memory']['bookmarks']),2,'rejected mutations preserve bookmarks')
    call('memoryReturn')
    guide('Return to explicitly set starting point',pose(0,0,3),'guiding',[0,0,0,4,0,0,0],3)
    call('memoryStop')
    guide('Stop recall preserves live obstacle sensing',pose(0,0,3),'idle',obstacle_bands,255,distances=obstacles)
    call('memoryRecall',id='desk');call('memoryDelete',id='desk')
    guide('Deleting active bookmark stops recall',pose(2,0,2),'idle',zero,255)
    r.expect(len(call('memoryState')['memory']['bookmarks']),1,'delete selected bookmark')
    call('memoryBegin',session='demo-b');session='demo-b'
    r.expect(len(call('memoryState')['memory']['bookmarks']),0,'new AR session clears memory')
    call('memoryRecall',valid=False,id='entry');call('memoryReturn',valid=False)
    call('memoryEnd')
    guide('Ended session cannot emit remembered guidance',pose(),'sessionUnavailable',zero,255,distances=[.5]*7)
    r.command(f'TICK {ms+500}','Firmware watchdog still stops after memory app loss',bands=zero,highlight=255,active=False)
    if r.checks<200 or len(r.steps)<40:raise AssertionError('Spatial replay was incomplete')
    return {'schema':1,'version':'V2','label':'SIMULATION — production spatial memory and controller',
            'physical_hardware':'NOT VERIFIED','status':'PASS','seed':20261016,'assertions':r.checks,
            'motor_model':{'speed_deg_s':300,'measured':False,'jam_feedback':False},'steps':r.steps}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--swift',type=Path,default=ROOT/'ios/Shared/FeelCore/.build/debug/feel-replay')
    p.add_argument('--firmware',type=Path,default=ROOT/'firmware/build/feel-sim')
    p.add_argument('--output',type=Path,default=ROOT/'.artifacts/spatial')
    args=p.parse_args()
    for binary in (args.swift,args.firmware):
        if not binary.is_file():p.error(f'Missing compiled production binary: {binary}')
    replay=Replay(args.swift.resolve(),args.firmware.resolve())
    try:report=run(replay)
    finally:replay.close()
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    template=(ROOT/'validation/spatial/viewer.html').read_text()
    (args.output/'index.html').write_text(template.replace('__REPORT__',json.dumps(report).replace('<','\\u003c')))
    print(f"PASS: {report['assertions']} spatial cross-layer assertions, {len(report['steps'])} firmware states; physical NOT VERIFIED")
    return 0
if __name__=='__main__':raise SystemExit(main())

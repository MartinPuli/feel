#!/usr/bin/env python3
"""Package real STL geometry into an offline, dependency-free WebGL viewer."""
import base64
import json
import math
from pathlib import Path
import re
import struct
from check_stl import read_stl,inspect

ROOT=Path(__file__).resolve().parents[2]


def scalar(name):
    m=re.search(r'^'+name+r'\s*=\s*([-\d.]+)\s*;', (ROOT/'cad/params.scad').read_text(),re.M)
    if not m: raise ValueError('Missing parameter '+name)
    return float(m[1])


def main():
    layers=[]
    def add(label,filename,color,transform=lambda v:v,explode=0,visible=True):
        path=ROOT/'stl'/filename
        report=inspect(path)
        if not report['pass']: raise RuntimeError(report)
        vertices=[n for triangle in read_stl(path) for v in triangle for n in transform(v)]
        payload=base64.b64encode(struct.pack('<'+'f'*len(vertices),*vertices)).decode('ascii')
        layers.append(dict(label=label,data=payload,color=color,explode=explode,visible=visible))
    add('Chassis','puck/chassis.stl',[.2,.25,.32])
    add('Lower guide','puck/guide.stl',[.36,.65,.74],lambda v:(v[0],-v[1],scalar('guide_z')+scalar('guide_t')-v[2]),1)
    add('Domed face','puck/face.stl',[.6,.82,.86],lambda v:(v[0],v[1],v[2]+scalar('body_h')-scalar('face_t')),2)
    ca,sa=math.cos(math.radians(58)),math.sin(math.radians(58))
    for c in range(7):
        add('Cam '+str(c),'puck/shaft_A.stl',[.94,.64,.24],lambda v,c=c:(v[0]*ca+v[1]*sa+(c-3)*scalar('pitch'),-v[2]+scalar('shaft_origin_y'),-v[0]*sa+v[1]*ca+scalar('shaft_axis_z')),0)
    add('Pin plate (as printed)','puck/pins.stl',[.3,.33,.38],lambda v:(v[0]-115,v[1],v[2]),0,False)
    add('Forearm tray','puck/pack_tray.stl',[.3,.33,.38],lambda v:(v[0]+115,v[1],v[2]),0,False)
    (ROOT/'cad/viewer/mesh_data.js').write_text('/* Generated from validated STL triangles. GEOMETRY ONLY. */\nwindow.FEEL_LAYERS='+json.dumps(layers,separators=(',',':'))+';\n')
    print(f'Packaged {len(layers)} actual-STL layers for cad/viewer/index.html. Browser behavior still requires a browser check.')


if __name__=='__main__': main()

#!/usr/bin/env python3
"""Render actual exported STL triangles for review (optional NumPy/Matplotlib)."""
from pathlib import Path
import argparse
import ast
import math
import re
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import to_rgb
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import numpy as np
from check_stl import read_stl

ROOT=Path(__file__).resolve().parents[2]


def scalar(name):
    match=re.search(r'^'+name+r'\s*=\s*([-\d.]+)\s*;', (ROOT/'cad/params.scad').read_text(),re.M)
    if not match: raise ValueError(f'Missing literal {name}')
    return float(match[1])


def mesh(path): return np.array(read_stl(ROOT/'stl'/path))


def shaft(c):
    v=mesh('puck/shaft_A.stl')
    ca,sa=math.cos(math.radians(40)),math.sin(math.radians(40))
    rotation=np.array([[ca,sa,0],[0,0,-1],[-sa,ca,0]])
    return v@rotation.T+np.array([(c-3)*scalar('pitch'),scalar('shaft_origin_y'),scalar('shaft_axis_z')])


def panel(ax,parts,title,elev=28,azim=-62):
    all_points=[]
    all_triangles=[]
    all_colors=[]
    light=np.array([-.35,-.5,1]);light=light/np.linalg.norm(light)
    for vertices,color in parts:
        normals=np.cross(vertices[:,1]-vertices[:,0],vertices[:,2]-vertices[:,0])
        norms=np.linalg.norm(normals,axis=1)
        normals=normals/np.maximum(norms[:,None],1e-12)
        shade=.52+.48*np.maximum(normals@light,0)
        colors=np.clip(np.array(to_rgb(color))[None,:]*shade[:,None],0,1)
        all_triangles.append(vertices)
        all_colors.append(colors)
        all_points.append(vertices.reshape(-1,3))
    # One collection lets Matplotlib depth-sort triangles across the different parts.
    ax.add_collection3d(Poly3DCollection(np.concatenate(all_triangles),facecolors=np.concatenate(all_colors),linewidths=0,rasterized=True))
    points=np.concatenate(all_points)
    lo,hi=points.min(axis=0),points.max(axis=0)
    span=hi-lo;mid=(lo+hi)/2;side=max(span)*.55
    ax.set_xlim(mid[0]-side,mid[0]+side)
    ax.set_ylim(mid[1]-side,mid[1]+side)
    ax.set_zlim(max(0,mid[2]-side*.65),max(hi[2]+2,mid[2]+side*.65))
    ax.set_box_aspect((1,1,.65))
    ax.set_proj_type('ortho');ax.view_init(elev=elev,azim=azim)
    ax.set_axis_off();ax.set_title(title,loc='left',fontsize=11,fontweight='bold',pad=3)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'cad/evidence/geometry-preview.png')
    args=parser.parse_args()
    fig=plt.figure(figsize=(16,10),facecolor='#f4f6f8')
    fig.suptitle('FEEL V1 · actual exported geometry',x=.04,y=.97,ha='left',fontsize=22,fontweight='bold')
    fig.text(.04,.926,'GEOMETRY REVIEW — no printed fit, servo travel, foam return or tactile validation',fontsize=12,color='#a13723')
    specs=[
        ([(mesh('test/frame.stl'),'#596579'),(shaft(3),'#e9a142')],'01  Manual-column frame + real cam mesh'),
        ([(mesh('puck/chassis.stl'),'#596579')]+[(shaft(c),'#e9a142') for c in range(7)],'02  Puck chassis + seven indexed camshafts'),
        ([(mesh('puck/face.stl'),'#69a8bd')],'03  Domed face · 28 guide holes + landmark'),
        ([(mesh('puck/guide.stl'),'#69a8bd')],'04  Lower guide · printed orientation / bearing caps'),
        ([(mesh('puck/pins.stl'),'#596579')],'05  Height-matched pin sprue · C0–C6'),
        ([(mesh('puck/pack_tray.stl'),'#596579')],'06  Forearm tray · straps / nominal component bays'),
    ]
    for i,(parts,title) in enumerate(specs): panel(fig.add_subplot(2,3,i+1,projection='3d'),parts,title,elev=42 if i==1 else 28)
    plt.subplots_adjust(left=.025,right=.985,top=.87,bottom=.04,hspace=.12,wspace=.04)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(args.output,dpi=150,facecolor=fig.get_facecolor())
    print(args.output)


if __name__=='__main__': main()

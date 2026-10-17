#!/usr/bin/env python3
"""Fetch the official Apple-hosted CoreML YOLOv3 model at a pinned revision.

This downloads model data, not executable code. Apple-platform compilation and
inference are separate checks. No user images leave the app.
"""
import argparse
import hashlib
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://huggingface.co/apple/coreml-YOLOv3/resolve/63316bf5bf817553ba9426fcac0a306a1b2ddc44/YOLOv3Int8LUT.mlmodel'
SHA256 = '0e32f297ad9cfc0ea8e67276867956488c7ee10dc87c057da4debc939e20b76d'

def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):
            value.update(chunk)
    return value.hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'ios/Lantern/Models/FEELDetector.mlmodel')
    args=parser.parse_args()
    dest=args.output.resolve()
    if dest.exists():
        if digest(dest)!=SHA256:
            raise SystemExit('Existing model has a different digest; preserve it and choose another --output.')
        print(f'PASS cached model SHA-256 {SHA256}')
        return
    dest.parent.mkdir(parents=True,exist_ok=True)
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(dir=dest.parent,suffix='.download',delete=False) as stream:
            temporary=Path(stream.name)
            request=urllib.request.Request(URL,headers={'User-Agent':'FEEL-build/1.0'})
            with urllib.request.urlopen(request,timeout=120) as response:
                while chunk:=response.read(1024*1024):
                    stream.write(chunk)
        if digest(temporary)!=SHA256:
            raise SystemExit('Downloaded model hash does not match pinned model; refusing to install.')
        temporary.replace(dest)
        print(f'PASS downloaded {dest.stat().st_size} bytes; SHA-256 {SHA256}')
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
if __name__=='__main__':main()

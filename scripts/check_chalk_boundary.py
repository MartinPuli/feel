#!/usr/bin/env python3
"""Verify V4 retains the existing physical-output implementation unchanged."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'validation/chalk/hardware-boundary.json').read_text())
failures=[]
for name,expected in manifest['sha256'].items():
    path=ROOT/name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        failures.append(name)
if failures:
    raise SystemExit('Physical-output boundary changed; review explicitly:\n'+'\n'.join(failures))
print(f"PASS: {len(manifest['sha256'])} baseline files unchanged; firmware, CAD, protocol, tactile core and BLE adapter preserved. Not a physical test.")

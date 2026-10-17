#!/usr/bin/env python3
"""Invalid pulse inputs must exit before importing serial or opening a device."""
from pathlib import Path
import subprocess
import sys

helper = Path(__file__).resolve().parents[1] / "tools" / "bench.py"
for pulse in (0, 649, 2501, 20000):
    result = subprocess.run(
        [sys.executable, str(helper), "--port", "/no-device-for-software-test", "--pulse", "0", str(pulse)],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 2, result.stderr
    assert "pulse must be 650..2500" in result.stderr, result.stderr
    assert "REAL HARDWARE" not in result.stdout
print("PASS firmware bench helper: 4 out-of-range inputs rejected before serial access")

#!/usr/bin/env python3
"""Execute the real build hook against synthetic SCons target lists; no flashing."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import runpy
import sys
import types


class UserError(Exception):
    pass


errors = types.ModuleType("SCons.Errors")
errors.UserError = UserError
script = types.ModuleType("SCons.Script")
sys.modules["SCons"] = types.ModuleType("SCons")
sys.modules["SCons.Errors"] = errors
sys.modules["SCons.Script"] = script
hook = Path(__file__).resolve().parents[1] / "tools" / "compile_only.py"
cases = [([], False), (["buildprog"], False), (["upload"], True), (["uploadfs"], True), (["uploadfsota"], True), (["program"], True)]
for targets, reject in cases:
    script.COMMAND_LINE_TARGETS = targets
    rejected = False
    try:
        with redirect_stdout(io.StringIO()):
            runpy.run_path(str(hook))
    except UserError:
        rejected = True
    assert rejected == reject, targets
print("PASS firmware compile-only hook: 6 target guard cases (no upload command executed)")

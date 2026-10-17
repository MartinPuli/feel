#!/usr/bin/env python3
"""Run available software checks, recording missing prerequisites as BLOCKED.

This runner never flashes/signs hardware and never certifies a V2 release.
The actual code review and iOS/firmware contract comparison remain required.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def now():
    return datetime.now(timezone.utc).isoformat()


def run_check(name, command, output, files=(), tools=(), timeout=900,
              blocked_exit=False, scope="production"):
    record = {"name": name, "scope": scope, "command": shlex.join(command),
              "timestamp_utc": now(), "status": "NOT RUN"}
    missing = [p for p in files if not (ROOT / p).is_file()]
    missing += [f"tool:{p}" for p in tools if not shutil.which(p)]
    if missing:
        record.update(status="BLOCKED", missing=missing,
                      next_action="Import original sources or provide the listed toolchain; rerun.")
        return record
    log = output / (name + ".log")
    try:
        with log.open("w") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream,
                                       stderr=subprocess.STDOUT,
                                       start_new_session=(os.name == "posix"),
                                       env={**os.environ, "QT_QPA_PLATFORM": "offscreen"})
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # A shell may have launched compilers/other build descendants.
                # Linux/macOS checks own a session so the whole timed-out build stops.
                try:
                    if os.name == "posix":
                        os.killpg(process.pid, signal.SIGKILL)
                    else:
                        process.kill()
                except ProcessLookupError:
                    pass
                process.wait()
                record.update(status="FAIL", exit_code=process.returncode,
                              error=f"Exceeded {timeout} seconds; build process group terminated")
            else:
                record.update(exit_code=code,
                              status="PASS" if code == 0 else "BLOCKED" if blocked_exit and code == 2 else "FAIL")
    except OSError as exc:
        record.update(status="BLOCKED", error=str(exc))
    record["log"] = str(log.resolve())
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".artifacts/v2-checks")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(name, command, **kwargs):
        result = run_check(name, command, output, **kwargs)
        checks.append(result)
        print(f"{result['status']:8} {name}: {result['command']}", flush=True)

    check("source-presence", [sys.executable, "scripts/check_sources.py"], blocked_exit=True)
    check("reference-model-tests", [sys.executable, "-m", "unittest", "discover", "-s", "validation/tests", "-v"],
          files=("validation/run_scenarios.py",), scope="specification model")
    check("reference-scenarios", [sys.executable, "validation/run_scenarios.py", "--output", str(output / "simulation")],
          files=("validation/run_scenarios.py",), scope="specification model")
    check("firmware-host", ["sh", "firmware/test/run_host_tests.sh"], files=("firmware/test/run_host_tests.sh",), tools=("g++",))
    check("firmware-build", ["pio", "run", "--project-dir", "firmware"], files=("firmware/platformio.ini",), tools=("pio",), timeout=1200)
    check("cad-build", ["sh", "cad/build.sh"], files=("cad/build.sh", "cad/params.scad"), tools=("openscad",))
    stls = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "stl").glob("*/*.stl"))
    if stls:
        check("cad-meshes", [sys.executable, "cad/tools/check_stl.py", *stls], files=("cad/tools/check_stl.py",))
    else:
        checks.append({"name": "cad-meshes", "scope": "production", "timestamp_utc": now(), "status": "BLOCKED",
                       "command": "python3 cad/tools/check_stl.py stl/*/*.stl", "missing": ["stl/*/*.stl"]})
    check("cam-model", [sys.executable, "cad/tools/cam_sim.py"], files=("cad/tools/cam_sim.py",))
    check("ios-simulator", ["bash", "scripts/check_ios.sh"], files=("ios/project.yml",),
          tools=("xcodegen", "xcodebuild", "xcrun"), timeout=2400, blocked_exit=True)
    # Deliberately no placeholder adapter: a future adapter must call the real Swift encoder
    # and firmware decoder against validation/fixtures/protocol_vectors.json.
    check("production-contract", ["sh", "validation/adapters/run_contract_tests.sh"],
          files=("validation/adapters/run_contract_tests.sh",), scope="cross-layer production contract")
    report = {"timestamp_utc": now(), "platform": platform.platform(),
              "v2_gate": "FAIL" if any(x["status"] == "FAIL" for x in checks)
                         else "BLOCKED" if any(x["status"] == "BLOCKED" for x in checks)
                         else "REVIEW_REQUIRED",
              "physical_hardware": "NOT VERIFIED", "v3": "NOT STARTED", "checks": checks}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"V2 gate: {report['v2_gate']}; physical hardware: NOT VERIFIED")
    print(f"Evidence: {output / 'report.json'}")
    if any(x["status"] == "FAIL" for x in checks):
        return 1
    if any(x["status"] == "BLOCKED" for x in checks):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

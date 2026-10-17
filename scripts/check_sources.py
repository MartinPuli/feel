#!/usr/bin/env python3
"""Presence preflight only. Never treats supplied handoffs as executable sources."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = (
    "docs/BUILD-HANDOFF.md", "docs/PROTOCOL.md", "protocol/vectors.json",
    "cad/README.md", "cad/params.scad", "cad/build.sh",
    "cad/tools/check_stl.py", "cad/tools/cam_sim.py",
    "firmware/README.md", "firmware/test/run_host_tests.sh",
    "ios/README.md", "ios/project.yml",
)
SOURCE_GROUPS = {
    "cad source": ("cad", ("*.scad",)),
    "firmware source": ("firmware", ("*.ino", "*.cpp", "*.c")),
    "firmware tests": ("firmware/test", ("*.cpp", "*.c", "*.py")),
    "Lantern app": ("ios/Lantern", ("*.swift",)),
    "Beacon app": ("ios/Beacon", ("*.swift",)),
    "shared iOS code": ("ios/Shared", ("*.swift",)),
    "iOS tests": ("ios", ("*Tests.swift", "*Test.swift")),
}


def inspect(root):
    missing = [p for p in REQUIRED_FILES if not (root / p).is_file()
               or (root / p).stat().st_size == 0]
    groups = {}
    for name, (directory, patterns) in SOURCE_GROUPS.items():
        groups[name] = sorted({str(p.relative_to(root)) for pattern in patterns
                               for p in (root / directory).rglob(pattern)
                               if p.is_file() and p.stat().st_size > 0
                               and not any(part in {'.pio', '.build', 'build', 'DerivedData'} for part in p.relative_to(root).parts)})
        if not groups[name]:
            missing.append(f"{directory}/: {name} missing or empty")
    return {
        "status": "BLOCKED" if missing else "PRESENT_REVIEW_REQUIRED",
        "meaning": "File presence only; does not prove V1 builds, tests, compatibility, or readiness.",
        "missing": missing, "source_groups": groups,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    result = inspect(args.root.resolve())
    print(json.dumps(result, indent=2))
    return 2 if result["missing"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

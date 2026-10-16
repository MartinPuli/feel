# Executed test report — October 16, 2026

**Scope: new preparation tooling and specification model only. V2 production validation remains BLOCKED. Physical hardware is NOT VERIFIED.**

The lead engineer reran the final suites after an independent reviewer reproduced defects, inspected fixes and reran the affected checks. Exact UTC execution timestamps, commands, exit codes and log paths are recorded in [`evidence/executed-commands.json`](evidence/executed-commands.json). The blocker-aware runner's per-check timestamps and prerequisites are in [`evidence/checks.json`](evidence/checks.json).

| Check | Observed result | Evidence |
|---|---|---|
| Reference model unit suite | **PASS — 51 tests** | [`model-tests.log`](evidence/model-tests.log) |
| Source-preflight and command-runner regressions | **PASS — 6 tests** | [`preparation-tests.log`](evidence/preparation-tests.log) |
| Deterministic replay | **PASS — 18 scenarios, 77 asserted steps** | [`scenarios-summary.json`](evidence/scenarios-summary.json); full trace embedded in [`offline replay`](../demo/feel-simulation.html) |
| Python compilation | **PASS** | `python3 -m compileall -q validation scripts`; exit 0 |
| iOS helper shell syntax | **PASS**, syntax only | `bash -n scripts/check_ios.sh`; exit 0 |
| Generated replay JavaScript syntax | **PASS**, syntax only | `node --check .artifacts/replay-ui.js`; exit 0 |
| Source-presence preflight | **BLOCKED**, expected exit 2 | [`source-presence.log`](evidence/source-presence.log) |
| Full V2 check runner | **BLOCKED**, expected exit 2 | [`all-checks.log`](evidence/all-checks.log) |
| iOS direct invocation without sources | **BLOCKED**, expected exit 2 | [`ios-missing-source.log`](evidence/ios-missing-source.log) |
| Browser rendering / interaction | **BLOCKED / NOT RUN** | Playwright package is present, but no Chromium or other browser executable was available. No screenshot or browser QA is claimed. |
| Original CAD, firmware, iOS, detector and cross-layer contract | **BLOCKED** | Original sources/models/tests absent. See `RELEASE-STATUS.md`. |
| Servo/board/printed mechanism, BLE/LiDAR/UWB, tactile/user tests | **NOT RUN / NOT VERIFIED** | No physical device access supplied. |

## Reproduce the checks

Python standard library only; tested with Python 3.12.14 on Linux. The model's documented minimum is Python 3.9; other Python versions have not been executed in this session.

```bash
python3 -m unittest discover -s validation/tests -v
python3 -m unittest discover -s scripts/tests -v
python3 validation/run_scenarios.py --output .artifacts/simulation
python3 -m compileall -q validation scripts
bash -n scripts/check_ios.sh
python3 scripts/check_sources.py
python3 scripts/run_v2_checks.py --output .artifacts/v2-checks
```

The last two commands must remain nonzero/BLOCKED while the sources are missing. A passing reference-model job does not override that status. The runner does not flash boards or sign applications. `scripts/check_ios.sh` is a preparation helper whose actual builds remain unexecuted; align its scheme/tool versions with the imported project.

## Coverage and constraints

- Golden packet vectors: **5 valid and 8 invalid**, hand-authored. Exact nine-byte shape, every sequence value, every highlight value, invalid band values in each position, no mutation of invalid state, and logical one-pin-per-column selection.
- Watchdog: start-up neutral, accepted-receipt age, 499/500 ms boundary, rejected packets not refreshing the timer, disconnect/reconnect, packet loss, and sequence rollover. Sequence acceptance policies remain provisional, not confirmed firmware behavior.
- Synthetic upstream faults: tracking loss, stale/missing/invalid depth, boundary distances, stale target response, disappearing or conflicting targets, and empty-column highlights. Pose is metadata; no ARKit transform or real detector output is being tested.
- Nominal actuator requests: gap → band → assumed hold, neutral requests, and the handoff's 21-degree tap-angle hints. Timings are unmeasured model parameters. No continuous motion, force, pin return, real tapping cadence or intermediate lobe activation is simulated.
- Packet integrity limitations: valid-looking corruption and modulo sequence ambiguity are demonstrated. A passing limitation test means the model reproduces the limit, not that corruption is prevented.
- Fixture hygiene: empty suites/events/expectations, nested empty expectations, duplicate IDs and backward time are rejected. A regression injects incorrect neutral/999-degree output and requires scenario assertions to fail.
- Tooling: absent files never execute a command or claim readiness; command errors preserve output and exit code; timed-out Linux/macOS build process groups are terminated, including a real spawned-child regression.

Seed: **20261016**. The deterministic fixture hash and replay hash are committed in the scenario summary. Unit tests check seeded loss decisions and repeated output equality. The simulation clock uses Python integers; actual firmware clock-width/rollover behavior still needs production tests. These checks do not replace the earlier handoff's reported 28/33 firmware tests or 53 iOS tests; those originals remain missing.

## CI interpretation

`.github/workflows/validation.yml` separates the reference model from original-source presence. Missing original sources intentionally make the source job fail; downstream production jobs cannot be mistaken for passing tests. Mac/Xcode and board-build provisioning must be reconciled with the restored project. Actual hosted-run status is recorded separately at handoff; local execution alone is not a claim that GitHub Actions ran.

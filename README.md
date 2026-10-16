# FEEL — HackHarvard 2026

**V2: BLOCKED — original application, firmware, CAD, and tests have not been supplied. Physical hardware: NOT VERIFIED. V3: NOT STARTED.**

FEEL is the team's proposed iPhone-to-tactile-puck perception prototype: seven servo-driven columns, four selectable pins per column, and nine-byte Bluetooth commands. One pin per column can be selected; this is not a 28-actuator display.

On October 16, the connected GitHub API reported this repository empty (no commits or branches). The three supplied documents describe substantial prior work on another machine. Those claims are retained as handoff history, not reproduced test results. The preparation work is on [`feel/v2-preparation`](https://github.com/MartinPuli/hackharvard/tree/feel/v2-preparation).

## Team action needed

Upload the **original project folder including uncommitted source and tests**, or give the original repository URL. Keep CAD, firmware, iOS, models and earlier handoffs; exclude credentials, signing keys, personal recordings, caches and build products. Preserve original Git history where available. Do not force-push or replace another teammate's work.

Read `docs/RELEASE-STATUS.md` on the preparation branch for verified results and the exact blockers. The simulator on that branch is a new, explicitly labeled specification model. It cannot prove the missing software or physical mechanism works.

V3 Spatial Memory must remain separate and may start only after the actual V2 software gates pass. Eligibility for pre-event code/CAD needs organizer confirmation; do not hide prior work.

## Run the preparation demo

Requires Python 3.9+ (standard library; tested here with 3.12). From this branch:

```bash
python3 -m unittest discover -s validation/tests -v
python3 -m unittest discover -s scripts/tests -v
python3 validation/run_scenarios.py --output .artifacts/simulation
```

Open `.artifacts/simulation/index.html`, or download/open the committed [offline replay](demo/feel-simulation.html). It displays synthetic packet traces and unmeasured nominal commands; it has no hardware connection. Browser rendering remains unverified in this environment. The generated JavaScript passed syntax checks.

**Observed results:** 51 model tests + 6 tooling tests pass; 18 deterministic scenarios / 77 asserted steps pass. Read [test evidence and limits](docs/TEST-REPORT.md) and the [independent review](docs/REVIEW.md). These are new preparation checks, not the missing production test suites.

```bash
python3 scripts/check_sources.py
python3 scripts/run_v2_checks.py --output .artifacts/v2-checks
```

Both full-source checks intentionally return nonzero/BLOCKED while required sources are absent. CI preserves that distinction.

## Team handoff

- [Release status and next three actions](docs/RELEASE-STATUS.md)
- [Restore the original source](docs/SOURCE-IMPORT.md)
- [Beginner hardware bring-up](docs/HARDWARE-BRINGUP.md) and [calibration records](docs/CALIBRATION.md)
- [90-second demo and recovery](docs/DEMO.md)
- [Devpost draft](docs/DEVPOST.md) and [eligibility/provenance](docs/ELIGIBILITY.md)
- [Known issues](docs/KNOWN-ISSUES.md) and [model assumptions](validation/README.md)

The uploaded engineering/event/handoff documents are preserved under `AGENTS.md`, `HACKHARVARD-2026.md` and `HANDOFF-v7.md`. This preparation introduces no sponsor SDKs, credentials, source-history rewriting, physical test claims or V3 features.

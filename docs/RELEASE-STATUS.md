# FEEL release status — October 16, 2026

**V2 software: BLOCKED. Physical validation: NOT VERIFIED. V3: NOT STARTED.**

The supplied target repository was empty. GitHub returned HTTP 404 “This repository is empty” for its contents and `[]` for branches. This session imported the three supplied documents, prepared validation tooling and hardware/demo material, and created a separate `feel/v2-preparation` branch. It did not recover the missing application, firmware or CAD. The source audit and engineering instructions prohibit treating a substitute model as V2.

| Area | Status | Meaning |
|---|---|---|
| V2 software | **BLOCKED** | Original source, dependencies, models and tests are absent; Xcode unavailable locally. |
| V2 production-backed simulation | **BLOCKED** | Cannot reuse/verify missing production encoder, decoder or cam implementation. |
| New specification simulator | See `TEST-REPORT.md` | Independent, explicitly synthetic preparation tool; not V2 certification. |
| V2 physical hardware | **NOT VERIFIED** | No real device, servo, print, phone sensor or tactile user test. |
| V3 software | **NOT STARTED** | V2 software gate has not passed; no V3 branch or Spatial Memory implementation. |
| V3 physical hardware | **NOT VERIFIED** | No V3 hardware demonstration. |
| Hackathon eligibility | **BLOCKED pending organizer answer** | Pre-event work disclosed; acceptance not inferred. |

## Baseline and evidence

`docs/evidence/baseline.json` records input hashes, platform, installed tools and the initial empty-repository responses. Exact current test commands, timestamps, outputs and model limits are in `TEST-REPORT.md` and `docs/evidence/`. Historical counts in `HANDOFF-v7.md` remain historical claims; none of its board/iOS/CAD build claims was reproduced.

| Check | Command | Current state / next action |
|---|---|---|
| Original source presence | `python3 scripts/check_sources.py` | **BLOCKED**, expected exit 2; restore sources per `SOURCE-IMPORT.md`. |
| Full available-check report | `python3 scripts/run_v2_checks.py --output .artifacts/v2-checks` | Must remain **BLOCKED** until source/toolchain checks and actual contract adapter run. |
| Original firmware host suite | `sh firmware/test/run_host_tests.sh` | **BLOCKED**, script/source absent. |
| Original firmware board builds | `pio run --project-dir firmware` | **BLOCKED**, configuration/source/PlatformIO absent; inspect original pinned environments before use. |
| Original CAD export | `sh cad/build.sh` | **BLOCKED**, source absent; OpenSCAD 2021.01 is installed. |
| Mesh inspection | `python3 cad/tools/check_stl.py stl/*/*.stl` | **BLOCKED**, mesh/checker absent. |
| Original cam simulation | `python3 cad/tools/cam_sim.py` | **BLOCKED**, original code absent. |
| iOS tests / builds | `bash scripts/check_ios.sh` | **BLOCKED**, original project and macOS/Xcode unavailable. Helper discovers actual simulators, runs Lantern tests, compiles Beacon and unsigned device targets when available. |
| Production protocol comparison | `sh validation/adapters/run_contract_tests.sh` | **BLOCKED**, adapter must be implemented against real production code after import. |

## What this preparation changes

- Preserves the supplied instructions, v7 and updated event summary under canonical filenames.
- Adds a reference packet model, deterministic fault fixtures and an offline visual replay with no hardware I/O.
- Adds source-presence checks, a blocker-aware command runner, an unsigned iOS check helper and minimal CI. CI does not hide missing production source as a skipped green release.
- Adds assembly/calibration records, an honest live-versus-simulation demo, Devpost draft, source import steps, provenance and unresolved eligibility questions.
- Records independent review findings and actual retests. There is no claim that absent production code received a line-by-line audit.

## Exactly what the team does next

1. **Supply the original project:** upload the full working source folder (including uncommitted work), or the actual source repository URL. Preserve original authorship/history. The new preparation branch is not a replacement for that source.
2. **Run one-column hardware gates when parts arrive:** identify board and servo, obtain reliable electrical specs, review unpowered wiring, finish the manual rig using recovered CAD, record P1 selection / P2 return / P3 thumb contact / P4 100 cycles / P5 isolated taps. Then measure the actual servo/horn and calibrate one powered column. Stop on a failed gate.
3. **Integrate and demonstrate only verified behavior:** expand to seven columns after one-column passes, verify power/load/timeout and phone-to-palm direction, then test real LiDAR/BLE and optional UWB indoors with a spotter. Record results, confirm eligibility and update the submission before the supplied Sunday 8 AM EDT deadline.

Detailed work order: `HARDWARE-BRINGUP.md` → `CALIBRATION.md` → `DEMO.md`. V3 stays deferred until V2's actual software quality checks and review pass.

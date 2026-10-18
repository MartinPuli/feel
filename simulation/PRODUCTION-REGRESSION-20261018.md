# Production regression audit — 2026-10-18 UTC

Source baseline: `origin/main` at `8b0789c`, integrated working branch `codex/production-readiness`. This report supersedes the earlier 13-scene validation for current source. It covers portable software, simulation and replay web tools, not iOS installation, deployed cloud authorization or physical hardware acceptance.

## Fixed regressions

1. **P1: neutral guidance could resurrect.** The merged firmware stored bands when a new packet lowered them, then restored them after 150 ms without another packet. A tracking-loss neutral followed by packet loss therefore raised stale obstacle pins again. Reproduction: raised band at 100 ms, accepted neutral at 200 ms, old band restored at 350–699 ms, watchdog neutral at 700 ms. The nine-byte ABI contains no tap-versus-safety reason. `firmware/src/controller.cpp:104` now preserves neutral until a new accepted packet changes it. The safety test failed before the fix and passes afterward, including clock wraparound. Fresh packet restoration and the 500 ms watchdog remain unchanged. A lost restoring tap packet can now leave a pin down until the next valid command; safety-neutral takes precedence. No angles, pulses, electrical configuration, flashing or hardware actions changed.
2. **P2: out-of-order replay responses changed the selected scene/snapshot.** `web/public/replay/index.html` now assigns request generations to session and comparison loads, rejecting stale responses and stale errors after selection changes. Two tests failed against the original page and pass against the fix.
3. **P2: inferred taps could satisfy the wrong band.** `simulation/run.py:139` records the band's pre/post-tap provenance and requires live/simulation guidance. A band-2 tap cannot satisfy band 3, and tracking-loss zero cannot be called a tap. The added scorer test failed against the original harness and passes now. Per-window thresholds are unchanged.
4. **P2: snapshots absent from static builds.** `web/build.mjs:43` now exports only snapshots belonging to explicitly publishable sessions, with allowlisted metadata and tick fields. Private recordings and extra payload fields remain excluded. Public snapshot tests cover both completeness and privacy.

## Current validation

| Gate | Result | Actual command / evidence |
|---|---|---|
| Portable Swift core | PASS, 395/395, zero skips | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 simulation/unit_tests.py`; `/private/tmp/feel-production-core-diagnostics.log` |
| Encoder-to-controller pin paths | PASS, 24/24 on fixed firmware | `python3 simulation/pin_diagnostics.py`; `/private/tmp/feel-production-pin-final.log` |
| Firmware host/controller/adapter/config suites | PASS, including 44/44 controller tests | `sh firmware/test/run_host_tests.sh`; `/private/tmp/feel-production-firmware-fixed.log` |
| Scorer boundary/provenance tests | PASS, 5/5 | `python3 -m unittest discover -s simulation/tests -v` |
| Default replay | 30 PASS, 5 KNOWN, 0 FAIL; all 35 deterministic across three runs; zero reserved-slot violations | `python3 simulation/run.py --repeat 3 --no-web --no-build`; `/private/tmp/feel-production-replay-final.log` and `production-validation-20261018.json` |
| Additional movement candidates | 17 PASS, 3 FAIL; all 20 deterministic across two runs | `movement-validation.json`; failures retained in `pending-scenarios/` |
| Web regression tests | PASS, 11/11 | `cd web && npm test`; `/private/tmp/feel-production-web-tests-final.log` |
| Static web build | PASS | `npm --prefix web run build`; `/private/tmp/feel-production-web-build-fixed.log` |
| Physical BLE, tactile motion and user performance | NOT VERIFIED | No hardware touched or flashed |

An actual synthetic export using `--snapshot production-validation` was also built into `/private/tmp/feel-production-snapshot-dist`; its public snapshot index and all tick records were read back successfully. The static-build unit test separately confirms that private snapshots are withheld.

Before our fixes, current main's 17-scene suite had 12 PASS / 5 KNOWN with all stored baselines matching (`/private/tmp/feel-production-replay-before.log`). The corrected packet-loss case has a changed baseline because it deliberately preserves the last neutral command; no stored baseline was regenerated to conceal the change.

The five existing known cases remain visible: narrow doorway, doorway with lintel, slow detector highlighting, cluttered hallway filter lag and crossing-person filter lag. The third-nearest-depth-sample rule now passes the outlier scene. Replay does not model the path wave, BLE radio, real LiDAR, floor height changes on a worn phone, or the user's tactile interpretation; unit tests do not substitute for those checks.

## Movement fixtures and unresolved acceptance

Twenty source scenes from `origin/movement-simulation-tests` (`3c041c0`) have useful geometry. Nine originally labelled reserved wire slot 0, and other original labels also assumed seven sectors. They were not copied unchanged. All labels were regenerated before replay using the current six-sector `simulation/geometry_labels.py`: 3 cm surface sampling, 4% range tolerance, 0.7° edge exclusion and 0.35 s transition trim. Each file includes provenance. No scene geometry or accuracy threshold was changed to fit the output.

Seventeen passing scenes are included in the default suite:

- `scenarios/chair-in-front-of-wall.json`
- `scenarios/chair-narrow-centre.json`
- `scenarios/chair-outer-edge.json`
- `scenarios/chair-sector-edge.json`
- `scenarios/person-and-chair.json`
- `scenarios/person-crossing-close.json`
- `scenarios/person-crossing-far.json`
- `scenarios/person-crossing-right-left.json`
- `scenarios/person-crossing-right.json`
- `scenarios/person-stationary-centre.json`
- `scenarios/person-stationary-left.json`
- `scenarios/person-stationary-right.json`
- `scenarios/person-toward-centre.json`
- `scenarios/person-toward-left.json`
- `scenarios/person-toward-right.json`
- `scenarios/two-chairs-separated.json`
- `scenarios/wall-full-width.json`

Three are explicitly failing acceptance candidates, not part of a claim that every scenario passes:

- `pending-scenarios/person-away-centre.json`
- `pending-scenarios/person-away-left.json`
- `pending-scenarios/person-away-right.json`

Their failures are conservative nearer-band persistence during receding movement. `SectorFilter` (`ios/Shared/FeelCore/Sources/FeelCore/Perception.swift:106`) deliberately waits for 0.1 m beyond a farther boundary plus four agreeing frames, as verified by `SectorFilterTests.testFartherBandNeedsFourFramesAndMargin`. At 0.45 m/s, the margin adds about 0.22 s and agreement about 0.3 s, exceeding the independent geometry labels' 0.35 s trim. Centre: 1.75 s shows band 1 rather than 2; 3.35 s shows band 2 rather than 3. Left/right: 1.25–1.35 s retain band 1 rather than 2. No false-clear, missed obstacle or reserved-slot activation occurred in these cases. This is a P2 product latency/accuracy tradeoff consistent with the implemented filter contract, not a justification to lower thresholds or declare a physical result. The pending README contains exact window agreement and rerun instructions.

## Remote branch inventory

All remote branches were compared by ancestry against `8b0789c`. `claude/strange-swartz-7b6d9b` contains shared-memory read-side work being integrated separately by the iOS/backend owners. V2 spatial memory, V3 advanced and V4 Chalk refs retain unique historical commits, but their principal features were already ported into main; merging their old core wholesale would overwrite newer work. `feel/v2-preparation` only retains the repository-language documentation commit. The movement fixture branch is covered above. All other listed remote branches, including Ethan/CAD, diagnostics, authentication and Chalk tracks, had no commits outside this main baseline. Ancestry alone does not prove device activation; native feature validation remains a separate gate.

## CAD and board-build prerequisite audit

Read `cad/README.md`, `cad/production/README.md`, `firmware/README.md`, the build scripts and pinned configuration before these checks. No tools/dependencies were installed, no design/parameter files were changed, and no board was flashed.

| Check | Current result | Evidence |
|---|---|---|
| Portable mesh/contact math tests | PASS, 8/8 | `PYTHONPATH=cad/test python3 -m unittest test_geometry_tools.MeshChecks test_geometry_tools.FollowerChecks.test_contact_checks_segment_interior test_geometry_tools.FollowerChecks.test_tip_width_changes_actual_contact -v`; `/private/tmp/feel-production-cad-portable.log` |
| Complete CAD test suite | BLOCKED by missing OpenSCAD; command reported 15 tests, 8 pass, 2 failures, 5 errors | `python3 -m unittest discover -s cad/test -v`; `/private/tmp/feel-production-cad-tests.log`. The two assertion failures occur because tool absence is reported before the intended print-gate/lock branches; the five errors directly require OpenSCAD. This is not a passing geometry gate. |
| Fresh representative STL export | BLOCKED, OpenSCAD absent | `sh cad/build.sh --fast --output /private/tmp/feel-production-cad-fast`; `/private/tmp/feel-production-cad-build.log` |
| Actual-polygon cam contact simulation | BLOCKED, OpenSCAD absent | `python3 cad/tools/cam_sim.py --step 0.1 --json /private/tmp/feel-production-cam.json`; `/private/tmp/feel-production-cam.log` |
| Production CAD verifier | BLOCKED, NumPy and OpenSCAD unavailable to the available Python 3.12 runtime | `/Users/martinezequielpulitano/.local/bin/python3.12 cad/production/verify.py --help`; `/private/tmp/feel-production-cad-production-prereq.log`. System Python 3.9 also cannot parse the verifier's nested f-string syntax. |
| ESP32/ESP32-S3 board binaries and enabled-output compiler fixtures | BLOCKED, local dependency setup incomplete | `sh firmware/build.sh` fails because system Python lacks PlatformIO (`/private/tmp/feel-production-board-build.log`). An existing `/private/tmp/feel-travel-pio` environment has PlatformIO 6.1.18 and Espressif32 6.9.0/toolchain caches, but this checkout has no `.pio` dependency tree and the required NimBLE-Arduino 2.3.6 source was not found in existing inspected workspaces. The alternate environment was inventoried, not allowed to auto-install dependencies. |

OpenSCAD was absent from both PATH and `/Applications`; this checkout also has no exported `stl/` tree to validate independently. Older committed CAD evidence remains historical evidence, including its documented `shaft3` hold-window failure. It was not presented as a current rebuild or physical fit verification. Board compilation, actual waveform measurement, printed-fit checks and physical six-column operation remain separate outstanding gates.

# V2 updated from current V1 main

This branch integrates V1 `main` commit `a4c141e` into V2 Spatial Memory. The
previous V2 tip was `063c07c`. The later documentation-only main commit `a53cbf1`
(installation evidence) is also included; validated app source is unchanged. `main` remains V1; V2 is published on
`feel/v2-spatial-memory`, with V3 advanced work separate.

## What changed

- The iOS app retains current V1's camera-first screen, Geist fonts, compact tactile
  display, connection/settings sheets, larger-text layout and Stop controls.
  Normal launch requests camera access once; Stop or backgrounding does not restart it.
- My Places opens from the camera header in its own sheet with a visible Stop. Remember, select, rename, delete, Recall,
  Set return point, Return and Stop guidance retain their existing behavior.
  Memory simulation retains its movement, tracking-loss and session-reset controls.
- Places remain session-only. Stops, interruptions, resets and mode changes clear
  memory; transient tracking loss neutralizes output and preserves the same-session
  intent. No voice commands, saved world maps or other V3 features were added.
- Firmware and CAD come from current V1: nominal 120° geometry, 0/40/80/120° bands,
  13° tapping offset, 900–2100 µs nominal mapping, single-servo demo/live profiles,
  and seven-servo production preparation. Default outputs remain disabled;
  production still requires actual measurement records for all seven units.
- App marketing version is 2.0.0, build 4. Setup instructions select V2 and identify
  `main` as V1. CI retains V1 gates and the spatial replay.

## Validation

**PASS on October 17, 2026**, source `0daf914`, Xcode 26.6 (17F113), Swift 6.3.3,
XcodeGen 2.46.0 and the iPhone Air / iOS 26.5 simulator.
[Machine-readable report and commands](evidence/v2-main/report.json).

| Check | Result |
| --- | --- |
| Portable Swift | 58 tests, zero failures |
| Firmware host/controller/configuration/adapter suites | PASS |
| Foundation production replay | 2,634 assertions / 558 controller states |
| Spatial production replay | 444 assertions / 43 controller states |
| Stateful spatial CLI fixture | PASS |
| Lantern app/coordinator tests | 8 tests, zero failures |
| Lantern UI tests | 6 tests, zero failures |
| Beacon UI tests | 2 tests, zero failures |
| Lantern and Beacon unsigned device builds | Both PASS |
| Source presence, tooling, reference tests, model integrity | PASS; 7 tooling and 51 reference tests |
| Independent source review | No actionable integration defects |

The native command was `FEEL_TEST_DIAGNOSTICS=never bash scripts/check_ios.sh`.
This disables only verbose failure sysdiagnose for limited local disk; assertions,
screenshots and result bundles remain enabled. CI keeps its default diagnostics.
The script now exercises both applications' UI test suites before device builds.
[Full native log](evidence/v2-main/ios.log),
[camera view](evidence/v2-main/camera-simulation.png),
[memory entry](evidence/v2-main/memory-name-entry.png) and
[Recall controls](evidence/v2-main/memory-guiding.png) are retained.

Initial attempts exhausted disk space while compiling Apple SDK modules. A later
memory UI attempt failed an immediate post-focus hit-test precondition as the
keyboard changed the sheet geometry. The test now types a name and asserts the
actual field value before Remember; all motion, recall, neutral-output, recovery
and reset assertions remain. Its focused rerun and the complete native suite
passed. Failure excerpts are preserved, rather than reported as successful runs.
A failed result bundle could not finalize due disk exhaustion and was removed as
unreadable; its full text log remains locally and its failure excerpt is tracked.

CAD, firmware and protocol source are identical to the current main baseline.
Their inherited physical limits and historical evidence remain applicable; this
integration did not rerun embedded uploads or physical tests. Hosted CI was not
run as part of these local checks.

## Physical limits

No device was flashed, installed or moved during this integration. Simulator tests
and unsigned builds cannot validate LiDAR accuracy, AR drift, real BLE timing,
Nearby Interaction direction, physical memory guidance or seven-servo mechanics.
Prior one-servo user observations are historical V1 evidence, not new V2 acceptance.

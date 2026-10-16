# V2 executed tests

The final V2 runner completed five available checks successfully; its Apple gate
is BLOCKED on Linux; hosted Xcode16.4 subsequently passed all native checks. Evidence: `docs/evidence/v2/report.json` and adjacent logs.
Foundation evidence and exact counts are preserved in `TEST-REPORT-V1.md` and
`docs/evidence/v1/`.

- `sh ios/scripts/test_portable.sh`: **58 XCTest tests,0 failures**,20 new spatial.
- `swift build -j 2 --package-path ios/Shared/FeelCore`: **PASS**.
- `sh firmware/test/run_host_tests.sh`: **38 C++ cases,17 CLI commands,6 board
  configuration checks,6 compile-fixture guards PASS**.
- `python3 validation/production/run.py`: **1,518 assertions,558 states PASS**.
- `python3 validation/spatial/run.py`: **358 assertions,43 states PASS**.
- The actual stateful CLI also executed `ios/Fixtures/spatial-memory.json`: PASS.
- All17 Swift source files passed syntax parsing. This is not Apple typechecking.
- The independent reviewer executed the58-test binary directly and reviewed the
  app/AR/NI lifecycle and UI source. No unresolved critical/high finding remained.
- Headless Chromium exercised the recorded spatial viewer:28pins,next,slider,
  playback,desktop/mobile,no JavaScript errors or horizontal overflow.

Spatial coverage includes translations,90°/180° rotations, sector edges, arrival,
vertical mismatch, out-of-view/behind/far places, tracking loss/recovery, stale and
future poses, invalid bases, session isolation/reset, ID/name validation, capacity,
multiple targets, rename/delete, Return, Stop, closer obstacles and watchdog.
A review found pitch-dependent disagreement between memory and obstacle columns.
Memory now uses the same inverse-camera bearing and camera x/z range as V1;20°
and40° equivalence regressions compare it to the existing perception paths.
World-horizontal range and vertical distance remain separate arrival criteria.

Some non-PTY wrapper invocations hit the restricted host's `/proc` monitor and
exited SIGILL. No such failed invocation is reported as PASS. Final consolidated
execution in a PTY, and independent direct XCTest execution, both completed with
zero failures. Swift uses the same legacy-driver/private-libncurses workaround
recorded for V1. A normal Mac does not require those cloud-host paths.

The three new Apple-platform coordinator tests and memory UI flow subsequently
passed on hosted macOS. Together with V1, 6 app unit tests and 2 UI tests passed. No ARKit
relocalization, real phone pose, BLE transmission, servo, current, force or human
tactile behavior was verified. V2 memory intentionally does not persist across
AR resets and is not an obstacle-free route planner.

## First hosted Mac result

Run38972855892 compiled the app and passed6 app unit/coordinator tests, but the
2-test UI suite had3 assertion failures in the memory flow: two manual scroll
visibility preconditions and the tracking-loss control. This is a real failed
run, not a successful validation. The UI correction and a complete native rerun
are required before the V2 software gate passes. Metadata and exact failure lines
are in `evidence/v2/github-actions-initial-failure.json` and
`evidence/v2/ios-ci-initial-failure.log`.

## Successful native rerun

[Run38974519620](https://github.com/MartinPuli/hackharvard/actions/runs/38974519620)
passed all four jobs for source `6e59c5b5dbe3a96ba8f03d712af08a648dd3a9ff`.
Xcode16.4 passed6 app unit tests and2 UI tests with0 failures, followed by Beacon
simulator and Lantern/Beacon unsigned-device builds. The correction uses native
target scrolling and checks the actual switch value; it retains the original
flow and additionally asserts all28 virtual pins neutral on tracking loss and
correct target recovery. No application logic or assertion was bypassed.
Test execution is bounded and the native result bundle is retained in CI.
Final metadata/excerpts: `evidence/v2/github-actions.json`, `ios-ci-excerpt.log`.

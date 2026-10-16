# V2 executed tests

The final V2 runner completed five available checks successfully; its Apple gate
is BLOCKED on Linux. Evidence: `docs/evidence/v2/report.json` and adjacent logs.
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

Three new Apple-platform coordinator tests and one memory UI flow were written
but **not executed here**. They run in the configured Mac workflow. No ARKit
relocalization, real phone pose, BLE transmission, servo, current, force or human
tactile behavior was verified. V2 memory intentionally does not persist across
AR resets and is not an obstacle-free route planner.

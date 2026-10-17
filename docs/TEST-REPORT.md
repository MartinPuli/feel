# FEEL V2 — current main integration

Integration validation is recorded in [V2-MAIN-INTEGRATION.md](V2-MAIN-INTEGRATION.md).
The sections below retain prior V1 hardware and V2 software evidence; they do not
represent new physical testing of this integration.

> Seven-servo preparation: `esp32-production` and its English setup guide are
> ready in source. Host/configuration tests, enabled-output compile fixtures and
> 2,634 cross-layer assertions passed. Real deployment is still gated on the
> seven units' missing physical measurement records. No board was flashed; the
> user has only one servo connected. [Evidence](evidence/seven-production/report.json)
> and [setup](SEVEN-SERVO-PRODUCTION.md). This is not full-device physical acceptance.

> Latest installed profile: `esp32-single-live`, source64fae62, uses nominal120°
> production center-sector mapping on GPIO32. Compilation, host regressions,
> upload and idle readback passed; physical full-range motion remains unverified.
> [Installation evidence](SINGLE-SERVO-LIVE.md#installed-validation). Earlier
> references below to the installed midpoint demo describe the prior state.

## Inherited V1 release evidence (before this V2 integration)

The design uses nominal FS0307 **120°** travel, not a measured endpoint.
Default ESP32/ESP32-S3 firmware keeps seven-servo output disabled until measured
pulse limits are supplied. The separately selected `esp32-single-demo` uses only
GPIO32 and the center camera sector, within nominal1450–1550 µs. It is the version
last installed on the user's board; it does not operate the seven-column cam.

A signed iPhone installation and BLE packet receipt were verified locally. The
user reported successful five-second bench motion and then small live app-driven
servo motion. Boot readback confirmed the demo timer ready and output detached.
See [single-servo evidence](SINGLE-SERVO-IPHONE-VALIDATION.md) and
[bench evidence](../firmware/bench-single/VALIDATION.md). These observations do not
measure pulse width, angle, power under load, sensing accuracy or stop latency.

Release hardening adds explicit50 Hz APB timer configuration,14-bit duty
quantization within supplied pulse limits, malformed serial-line rejection, and
CI coverage for both single-servo builds. Physical validation of full120° travel,
seven actuators, printed mechanics and tactile use remains **NOT VERIFIED**.
Current local software checks **PASS** on source `5f3ded9`: five primary firmware
variants plus the standalone bench build; complete host regressions;38 Swift core
tests;2,634 cross-layer assertions;104 actual-CAD/controller contract checks;
24 mesh exports;80 cam checks; model integrity; Xcode26.6 simulator tests
(3 app tests and1 UI test), companion simulator build and both unsigned device
builds. [Commands and evidence](evidence/v1-release/report.json) identify each
check. Published to `feel/v1-foundation` at `57c7e6b`. Hosted CI is **BLOCKED**:
GitHub refused to start every job because of account billing/spending limits.
[GitHub evidence](evidence/v1-release/github-actions.json) records the exact
annotation and run URLs. Resolve account billing and rerun; no hosted test ran. The hardened firmware
has not been flashed; the board retains the prior tested single-demo build. No claim of production hardware readiness is made.

## Historical V2 validation before the current main integration

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

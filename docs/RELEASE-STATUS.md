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

## Current iPhone visual update

Lantern now uses a chevron drawer in the [camera-first interface](V1-CAMERA-UI.md).
Tapping or dragging the arrow reveals the 7×4 packet display, status and rounded
Start camera action. Connection and Settings float over the camera. Stop remains
available with the drawer closed and inside either modal. Five integration tests
and six UI tests passed locally; Lantern builds and signs as 1.0.0 (5).
[Current screenshots and checks](evidence/v1-drawer/validation.txt).

Lantern 1.0.0 (5) was installed and launched on the paired iPhone 17 Pro on
October 17. Device app inventory confirms build 5. This confirms installation
and launch, not physical sensing/actuation performance. Beacon's interface is
unchanged; it was not rebuilt or installed during this update.

## V1 consolidation on main

The user designated `main` as V1 on October 16, 2026. The integration preserves
the existing `main` planning document, incorporates foundation `2df1c07`, and
includes app design commit `da12787`. V2 and V3 remain separate.
The app redesign passed local simulator builds and 46 distinct tests (38 shared
core, 3 Lantern integration, 3 Lantern UI, 2 Beacon UI). See
[app design evidence](evidence/v1-design/validation.txt). The integration is
published with `[skip ci]` because of the existing Actions billing blocker;
no hosted validation result is claimed for this merge.

Post-merge local checks passed: source presence, 7 tooling tests, 51 reference
model tests, production firmware host/adapter/demo/bench checks, and 2,634
cross-layer assertions across 558 firmware states. No board was flashed during
the consolidation. [Integration log](evidence/v1-main-integration.log).

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

**V2 software validation: PASS, including hosted native iOS checks.
Physical hardware: NOT VERIFIED.** October 16, 2026.

V1 was validated first and preserved on `feel/v1-foundation`; its source is now
published at commit `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`. That remote tree
exactly matches the reviewed local V1 snapshot. All four hosted jobs, including
iOS app/UI tests and simulator/unsigned-device builds, passed in run38972250150.
See `evidence/v1/github-actions.json`. V2 native rerun38974519620 also passed all four jobs after the UI test interaction correction.

This isolated `feel/v2-spatial-memory` branch adds volatile bookmarks, Remember,
Recall, explicit Set Return Point/Return, multiple selection/rename/delete,
accessible controls and a production-backed replay. Memory resets when the AR
coordinate frame resets. Offscreen, behind, distant or different-level places do
not fabricate a target highlight. Closer obstacles remain encoded.

| V2 check | Result |
|---|---|
| Production Swift tests | 58 PASS, including 20 spatial-memory tests |
| Production Swift CLI build | PASS |
| Firmware host/controller regressions | PASS: unchanged V1 firmware |
| Preserved V1 packet/controller replay | PASS: 1,518 assertions, 558 states |
| Spatial-memory → packet → controller replay | PASS: 358 assertions, 43 states |
| Recorded spatial viewer | PASS browser rendering/controls/mobile layout |
| Apple-framework builds and app/UI tests | PASS: Xcode16.4, 6 app unit + 2 UI tests, both simulator and unsigned device builds |
| Printed mechanics, servo/electrical, actual AR/BLE/NI/touch | NOT VERIFIED |

Command: `python3 scripts/run_spatial_checks.py --output .artifacts/v2-validated`.
The final run returned2 because its Apple check is BLOCKED; all five available
checks passed. The host invocation used a PTY to avoid this environment's
intermittent `/proc` process-monitor failure. Earlier failed wrapper attempts
were environment failures, not successful tests; the final logs and independent
58-test direct run are the evidence. See `TEST-REPORT.md` and `evidence/v2/`.

V1 CAD, protocol and embedded source are unchanged. Their 24 exports,78 cam
assertions,13 tool tests and four embedded builds remain the V1 evidence; these
were not needlessly repeated as new V2 tests. PWM remains disabled by default.
The native gate now passes in [run38974519620](https://github.com/MartinPuli/hackharvard/actions/runs/38974519620),
source `6e59c5b5dbe3a96ba8f03d712af08a648dd3a9ff`. The initial failed run is
preserved in `evidence/v2/github-actions-initial-failure.json`; final results are
in `evidence/v2/github-actions.json`. V3 may now begin in an isolated branch.

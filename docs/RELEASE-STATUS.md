> **V4 on `feel/v4-chalk` (2026-10-17 02:45): Where-is through Chalk's Model Gateway, typed requests,
> sessions that survive missing sound output, and a minimalist-neobrutalist restyle, on top of
> main's OpenAI voice stack. Software checks PASS on this Mac and in the iOS Simulator.
> Physical camera, LiDAR, puck and live speech: NOT RUN here.** Details at the end of this file.

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

# Current V1 release candidate

## Current proactive voice update — October 17

Build 14 is signed, installed and launched on the paired iPhone at 01:48 EDT.
OpenAI accepted the expanded voice tool set; phone diagnostics show readiness
and successful audio-engine recovery. Spoken action checks with the user and
headset behavior remain pending. The production token service retains provider
credentials on Vercel. The FEEL wordmark has a matching control background.

V1 adds event-driven nearby-obstacle and target-movement notices, sensing
recovery, and spoken access to the app's operational controls. “Silence yourself”
mutes speech while preserving microphone capture and commands; “speak again”
unmutes. “Stop listening” ends capture and requires touch to resume. iOS permission
choices and credential entry remain manual. The phone still pauses capture when
backgrounded or locked. [Evidence](evidence/v1-proactive-voice/validation.txt).

All 60 native unit/integration tests and 7 UI tests passed.
Independent review identified a sub-0.3 m filtering issue, fixed with regression
coverage. Earlier [OpenAI migration evidence](evidence/v1-openai-voice/validation.txt)
records the prior 40 native tests, 7 UI tests and 18 service tests.

## Prior iPhone voice provisioning

Build 8 used Grok/Sal. The user confirmed live voice input and spoken responses,
then reported disconnections. Its historical activation evidence is preserved
in [the provisioning record](evidence/v1-voice-provisioning/validation.txt).
Build 6 introduced foreground listening and accessible Assistant controls.
Backgrounding or locking pauses microphone capture; camera images remain local.

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

## Historical foundation evidence (before the 120° revision)

# FEEL V1 release status

**Software validation: PASS, including hosted Apple-platform checks.
Physical hardware: NOT VERIFIED.** October 16, 2026.

This is a greenfield implementation from the specification. It does not recover
or inherit test results from an original implementation. The complete runner
executed 14 available checks successfully and returned exit 2 because this Linux
host has no Xcode/XcodeGen/iOS simulator. Hosted macOS CI then completed all four
jobs successfully for source commit `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`.
Xcode 16.4 passed three app unit tests, one UI test, both simulator builds and
both unsigned iPhone builds. CoreML inference and signed installation remain
device work. [CI run](https://github.com/MartinPuli/hackharvard/actions/runs/38972250150)
and [recorded results](evidence/v1/github-actions.json) identify the tested snapshot.
The user explicitly authorized publication after the earlier automatic-review block.

| Area | Result | Evidence / remaining gate |
|---|---|---|
| Production Swift core and CLI | PASS | 38 XCTest cases; compiled replay executable |
| Production firmware controller | PASS | 38 C++ cases; 17 CLI, 6 configuration and 6 upload-guard checks |
| ESP32 and ESP32-S3 | PASS compilation | Default and enabled-output compile fixtures, four builds; no flashing |
| Swift → nine-byte packet → C++ replay | PASS | 1,518 assertions, 558 firmware states, seed 20261016 |
| OpenSCAD and meshes | PASS geometry | 24 exports with manifest hashes, 78 cam assertions, 13 tool regressions |
| Apple CoreML resource | PASS integrity | Genuine pinned model downloaded and SHA-256 verified; inference NOT RUN |
| Offline replay and actual-mesh viewers | PASS | Chromium interaction/rendering, desktop/mobile; synthetic geometry/data |
| Tooling / historical Python model | PASS | 7 tooling and 51 reference-model tests; model is separate from production |
| iOS platform | PASS | Hosted Xcode 16.4: 3 app + 1 UI tests; Lantern/Beacon simulator and unsigned device builds |
| Servos, printed parts, power, BLE radio, LiDAR, NI, tactile use | NOT VERIFIED | Physical P1–P5 and device bring-up remain required |

Command: `python3 scripts/run_v1_checks.py --output .artifacts/v1-validated`.
Exact commands/logs and host limitations: [evidence/v1/report.json](evidence/v1/report.json),
[TEST-REPORT.md](TEST-REPORT.md), [REVIEW.md](REVIEW.md).

The user's criterion is all **available** software checks. That foundation gate
has passed, including the subsequently available hosted Mac checks; V2 Spatial
Memory may proceed in its own branch. V1 remains preserved here. This milestone
does not establish real sensor, radio, electrical or tactile behavior.

Primary hardware is the team's classic ESP32-WROOM. Servo PWM defaults OFF.
Published FS0307 travel/voltage differs from the handoff's 175°/650–2500 µs
assumption. Identify and measure the actual units before enabling output. Nominal
CAD clearances, horn fit, thin-guide stiffness and foam return are unverified.

## V4: Where-is through Chalk, typed requests, no-audio resilience (2026-10-17)

| Check | Result | How |
|---|---|---|
| Swift core (portable) | PASS, 54 tests incl. held target, depth grid, placement | `sh ios/scripts/test_portable.sh` |
| App unit tests (simulator) | PASS: gateway, Where-is service, `where_is` command, voice providers, existing suites | `xcodebuild … -only-testing:LanternTests` |
| UI tests | PASS: existing suite with the restyle, Where-is setup, provider picker | `bash scripts/check_ios.sh` |
| Chalk gateway from this Mac | PASS: text and image requests on `openai/gpt-6.1-sol`, 2.6–3.7 s | `chalk/check_connection.py --chat` |
| Chalk gateway from the app | PASS in the iOS Simulator: the sample photo went through the real request, parser and placement code; "Found '3D puck model' … in 4.2 s" | Assistant panel → Where-is setup → Test with a sample photo |
| Chalk Evaluation run | BLOCKED: needs `chalk login` and venue photos | `chalk/README.md` → Run the evaluation |
| Grok voice | NOT RUN here (an earlier entry above records a confirmed phone session) | — |
| OpenAI Realtime voice | PASS in the iOS Simulator for connect, session setup, readiness line, a typed request, the app tool call and the spoken reply as a caption. Sound output is unavailable in the simulator (no running audio engine); the session now continues without it. Audible speech and the microphone: check on the phone | Assistant panel, typed request "where is the exit" |
| Where-is on the LiDAR iPhone | NOT RUN: checklist below | — |

### Camera and LiDAR conventions, checked against Apple's documentation

- `ARCamera.transform`: in camera space the x-axis points right when the device is in
  `UIDeviceOrientation.landscapeLeft`, y points up, z points toward the screen side. The
  app's landscape-left mount therefore gives +x right, +y up and −z forward, which is what
  `CameraIntrinsics.unproject` and `TactileGeometry.bearing` assume.
- `ARCamera.intrinsics`: fx, fy and the principal point are in pixels from the top-left of
  the captured image; the app scales them to the 256×192 depth grid by the ratio of depth
  size to `imageResolution` (`ARPerception.intrinsics`).
- `ARDepthData.depthMap`: metres, `kCVPixelFormatType_DepthFloat32`; `confidenceMap` holds
  `ARConfidenceLevel` low/medium/high (0/1/2) and only medium and high are used.
- `ARFrame.capturedImage`: full-range YCbCr; `CIImage` converts it for the Where-is JPEG. It
  shares the depth map's orientation, so the model's box maps to depth pixels unrotated.

### Device checklist for the hardware session (not yet run)

1. Install from `feel/v4-chalk`; in Assistant settings choose the voice service and enter the
   Where-is gateway settings (or launch with the DEBUG provisioning variables).
2. Start the camera, calibrate with the measured lens height, confirm `Where-is ready`.
3. Say "where is the chair": confirmation within 1 s, spoken observation and pin within 6 s;
   turn 90°, the pin follows; walk to it: "You're at the chair."
4. Say "where is the refrigerator" with none present: "I couldn't see a refrigerator in the photo."; no pin change.
5. Hold a target, cover the camera until tracking resets: "Lost tracking. Say it again."; pins neutral.
6. Hold a target, turn your back to it: "chair is behind you." within 5 s; "stop": highlight off, obstacles still shown.
7. Record PASS/FAIL per step here with the commit.

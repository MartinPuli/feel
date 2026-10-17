# Current V2 synchronization

See [VERSION-VOICE-SYNC.md](VERSION-VOICE-SYNC.md) for this integration's results.
The following records describe earlier revisions and inherited main evidence.


> **Merged Ethan's branch (2026-10-17 ~11:45): direction arrows, point-to-describe, target spans,
> depth recording, synthetic scenes and the replay harness now live on `main` next to Where-is,
> on main's OpenAI voice stack.** Ported: the keyword listener borrows the OpenAI session's
> microphone; the "which one?" question is an in-conversation `response.create` (OpenAI has no
> `force_message`). A placed Where-is target becomes the arrows' route goal, so "where is the exit"
> gets the tactile arrow along the planned route and the pin, with no failure tone while the planner
> has no route yet. After the merge: FeelCore + FeelSim 184 tests, Lantern 112 unit tests (1 skipped
> in the simulator) and the UI suite pass locally. Ethan's own caveats below still hold: nothing of
> his has run on a hand, a LiDAR map, a route or a physical column.

> Replay harness (October 17): `python3 simulation/run.py` replays labelled depth
> recordings (12 synthetic scenes now; iPhone recordings via the new Lantern
> **Record depth** toggle) through the shared FeelCore depth step, the production
> encoder and the production C++ controller, and scores the commanded pin grid over
> time. 9 scenes pass and 3 KNOWN issues are reported: a 2.03 m door head reads as
> an obstacle, the tap drops out with ≥ 0.15 s detector latency, and single LiDAR
> outliers raise pins. 8 FeelSim and 148 FeelCore tests pass; Lantern builds and its
> 40 unit tests pass (1 skipped). No phone recording has been captured or replayed yet.
> [Harness](../simulation/README.md). The new FEEL site (`web/`, local only so far) adds
> `/replay`: choose a simulated or phone session and watch the camera recording beside the
> commanded pin grid and LiDAR depth. Phone camera video is recorded but untested on a device.

> Direction arrows (October 17, supersedes the repeating guidance wave): a V hand sign
> requests one tactile arrow along an A* route over a local LiDAR floor map to the
> target in view. Later arrows play only on noticeable route changes or a repeated
> sign. No firmware or protocol change. Local results: 118 FeelCore tests, 34
> Lantern unit tests (1 pointing detector test skipped in the simulator), 8 UI tests
> and the 11-scenario pointing harness passed. Both apps build. Not installed on the
> phone. No real hand, LiDAR map, route or physical column tested.
> Update: the V sign plus one spoken word ("exit") picks the target, using on-device
> recognition. Guidance uses sounds only (success chime, failure tone, listening blip).
> Several targets in view make the assistant ask which one (`choose_target`).
> Now 135 FeelCore, 40 Lantern unit and 8 UI tests pass. Speech recognition, the
> microphone hand-off and the assistant question are not tested on a device.

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
Primary hardware is the team's classic ESP32-WROOM. Servo PWM defaults OFF.
Published FS0307 travel/voltage differs from the handoff's 175°/650–2500 µs
assumption. Identify and measure the actual units before enabling output. Nominal
CAD clearances, horn fit, thin-guide stiffness and foam return are unverified.

## V4: Where-is through Chalk with an on-device fallback, typed requests, no-audio resilience (2026-10-17)

| Check | Result | How |
|---|---|---|
| Swift core (portable) | PASS, 65 tests incl. held target, depth grid, placement, on-device vocabulary, held-target guidance | `sh ios/scripts/test_portable.sh` |
| App unit tests (simulator) | PASS, 104 tests: gateway, Where-is service with the on-device fallback, `where_is` command, the review fix pass, existing suites | `xcodebuild … -only-testing:LanternTests` |
| On-device fallback (simulator) | PASS: `ObjectDetectorTests` reads a rendered EXIT sign through the same Vision path the phone uses; the Core ML classes need `python3 scripts/fetch_model.py` before the device build | `xcodebuild … -only-testing:LanternTests/ObjectDetectorTests` |
| UI tests | PASS, 8 tests: existing suite with the restyle and the Where-is setup (the voice-setup test now scrolls without momentum) | `bash scripts/check_ios.sh` |
| Chalk gateway from this Mac | PASS: text and image requests on `openai/gpt-6.1-sol`, 2.6–3.7 s | `chalk/check_connection.py --chat` |
| Chalk gateway from the app | PASS in the iOS Simulator: the sample photo went through the real request, parser and placement code; "Found '3D puck model' … in 4.2 s" | Assistant panel → Where-is setup → Test with a sample photo |
| Chalk Evaluation run | BLOCKED: needs `chalk login` and venue photos | `chalk/README.md` → Run the evaluation |
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

### On-device fallback

"Where is X?" asks Chalk first. Without Chalk settings, or when the gateway fails or does not
answer within 12 s, the same photo goes to the phone's own detector (`LocalWhereIs` →
`ObjectDetector`): Vision text recognition for EXIT signs, Vision rectangles for door candidates,
Core ML or Vision human rectangles for people, and the bundled Core ML detector
(`FEELDetector.mlmodelc`, Apple's pinned YOLOv3, 80 COCO classes) for chairs and common objects.
The user's words are matched against a fixed vocabulary (`LocalVocabulary`: articles dropped,
plurals tried, last word as a fallback, so "registration desk" finds a table). Anything else
offline gets "I can only look for the exit, a door, a person, a chair or common objects right
now." The target is named by the user's own words, never by a model label. The sample-photo
self-test stays Chalk-only so its result reflects the gateway setup.

### Review fix pass (fresh-context review of the whole branch)

Fixed, each with a test that failed first: a new ask clears the previous target, cancels the
lookup in flight and resets the finder; a photo from an earlier ask is dropped; a placement from
a world that has since reset is refused ("Lost tracking. Say it again."); a target placed outside
the pins' field says its direction at once and "I no longer see your target" is never spoken for
a held target; finder and teammate targets never shadow a held target; a result line the
assistant could not speak (mid-reply, or inside the five-second announce throttle) is retried
from the tick for ten seconds; a typed request is refused while a reply is running instead of
racing it; the "audio engine not running" tolerance is confined to simulator builds; arrival
("You're at the …") counts only while sensing is live.

### Device checklist for the hardware session (not yet run)

1. Run `python3 scripts/fetch_model.py` (pinned, SHA-256 checked) so the bundle includes the Core ML
   detector, then install from `feel/v4-chalk-ben` (or `main` after the merge). In Assistant
   settings enter the voice service; the Where-is gateway settings are optional (or launch with the
   DEBUG provisioning variables). Without them Where-is runs on-device only.
2. Start the camera, calibrate with the measured lens height, confirm `Where-is ready` (Chalk) or
   `Where-is not set up` (on-device only).
3. Say "where is the chair": confirmation within 1 s, spoken observation and pin within 6 s;
   turn 90°, the pin follows; walk to it: "You're at the chair."
4. Say "where is the refrigerator" with none present: "I couldn't see a refrigerator in the photo."; no pin change.
5. Hold a target, cover the camera until tracking resets: "Lost tracking. Say it again."; pins neutral.
6. Hold a target, turn your back to it: "chair is behind you." within 5 s; "stop": highlight off, obstacles still shown.
7. Airplane mode with Chalk configured, near an EXIT sign: "where is the exit" → pin within about
   13 s (12 s gateway timeout, then on-device); "where is the unicorn" → the vocabulary line.
8. Record PASS/FAIL per step here with the commit.

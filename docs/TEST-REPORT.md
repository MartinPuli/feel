## October 18 UTC — current production readiness

**Not ready for unrestricted production.** Latest source, cloud checks and remaining device/configuration gates are recorded in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md). That report supersedes the historical counts and branch/deployment statements below.

The unsafe 150 ms restoration of old pin bands after a neutral packet has been removed. Only a fresh valid command can raise them again. Angles and wiring are unchanged; this firmware has not been flashed. Shared context reads now have a verified-user server boundary, but remain disabled until FEEL's database identity is configured.

## October 17 — integrated versions, latest main and Chalk

Observed on this Mac with Xcode's installed iOS 26.5 simulator:

- `xcodebuild … -only-testing:LanternTests -only-testing:LanternUITests … test`: 268 native + 12 UI tests, zero failures. Result: `/private/tmp/feel-version-integration-build/Logs/Test/Test-Lantern-2026.10.17_22-50-13--0400.xcresult`.
- Final concise mute wording was additionally checked with `-only-testing:LanternTests/VersionFeatureIntegrationTests` (same scheme/destination); result log `/private/tmp/feel-integration-final-wording-tests.log`.
- `swift test`: 360 portable tests passed, including session memory, persistent-map gates, local grammar, adaptive feedback and existing perception/protocol checks.
- `sh firmware/test/run_host_tests.sh`: PASS, log `/private/tmp/feel-integration-firmware.log`.
- `python3 simulation/run.py --repeat 3 --no-web --no-build`: 13 scenarios, 9 PASS / 4 KNOWN / 0 FAIL, identical output across three runs; 24 pin-command diagnostics and four scorer tests pass. Existing compiled binaries came from the integrated production source.
- `npm --prefix web test`: 9 PASS; local static build succeeds with 13 regenerated synthetic sessions. Browser inspection was unavailable; the new rendering functions are covered by focused minimal-DOM tests.
- Pinned SDK `python -m unittest discover -s chalk/tests -v`: 135 PASS; `python -m unittest discover -s services/chalk -v`: 36 PASS.
- Five direct-engine synthetic context queries passed twelve assertions. The same inputs through native Chalk MCP disagree; the discrepancy is retained as a failure, not hidden by reseeding.
- One bounded live text holdout: 20 gateway attempts and four local Stop bypasses, no retry. One recorder error left an attempt unmeasured. Strict matches: 16/19 measured gateway responses plus 4/4 local Stop. No measured gateway response met the 1 s target (p50 1.70 s, p95 2.55 s).

UI workflows exercised saving/recalling a simulated place, tracking loss/neutral
output, stopping, local typed mute and cloud-consent defaults. Retained screenshots
were visually inspected; the app remains a dark camera-first interface with
additional functions inside collapsed assistant sections.

All new cloud tests used synthetic fixtures or mocked transports. No personal
camera/audio data was uploaded. No new hardware actuation or device installation
was performed. See [integration scope](VERSION-INTEGRATION.md) and its linked
reports for exact commands, provenance and known limitations. Earlier counts
below describe older revisions and are not added to these totals.

## October 17 proactive voice and full app controls

Build 14 is signed, installed and launched on the iPhone. All 60 native tests
and 7 UI tests passed, including deterministic proactive observations, strict command decoding,
mute preserving capture and tools, unmute, panel controls and simulation isolation.
The phone accepted the expanded OpenAI session and recovered the audio engine.
Physical spoken command evaluation and headphones remain pending.
[Current evidence](evidence/v1-proactive-voice/validation.txt).

## October 17 OpenAI migration and audio recovery

The native OpenAI client and protected token service are implemented. Build 13
is signed. All 40 native tests, 7 UI tests and 18 service tests passed. A live Cedar probe completed two readiness responses around 40 seconds
of streamed silent PCM with no provider or send errors. This probe is synthetic
input, not evidence of physical microphone or headphone performance.

An iPhone diagnostic captured `engine_not_running` on first playback. Guarded
engine restart and request-specific cancellation were independently reviewed.
The iPhone became unavailable before the final updated installation; real-device
recovery remains pending. [Current evidence](evidence/v1-openai-voice/validation.txt).

## October 17 V1 live voice provisioning

33 native unit/integration tests and 18 service tests passed. Build 8 was signed
and installed. Vercel authentication and real xAI ephemeral issuance passed.
Native URLSession/WebSocket received Sal readiness audio, 45600 PCM bytes with
transcript “I'm here.” Phone provisioning and launch succeeded at 01:24 EDT after unlocking.
The user confirmed live microphone input and spoken responses. Cold relaunch,
headset behavior and subjective voice quality remain unverified. [Evidence](evidence/v1-voice-provisioning/validation.txt).

## October 17 voice refinement

39 distinct native tests passed; 32 unit/integration tests were rerun after the
final spoken wording change. Build 7 is signed, installed and launched. Live
voice quality is not verified. [Evidence](evidence/v1-voice-polish/validation.txt).

## October 17 V1 assistant update

36 native tests and 10 token-service tests passed locally. The signed build 6
was installed and launched on iPhone 17 Pro after unlocking the phone. Live
Grok and physical headset checks remain pending. See [voice evidence](evidence/v1-voice/validation.txt)
and [behavior/provisioning](V1-VOICE.md).

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

# Executed V1 tests

October 16, 2026; Linux, Swift 6.1.3, OpenSCAD 2021.01, PlatformIO 6.1.18.
The final Linux run has **14 PASS and one BLOCKED** check. Hosted macOS subsequently
closed the Apple-platform gate: all four jobs in [run 38972250150](https://github.com/MartinPuli/hackharvard/actions/runs/38972250150)
passed for commit `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`.
No physical device was operated. Logs and hosted result metadata are under `docs/evidence/v1/`.

| Command / suite | Observed result |
|---|---|
| `python3 scripts/check_sources.py` | Required new source present; presence only |
| `python3 -m unittest discover -s scripts/tests -v` | 7 PASS, including process-group timeout and dependency-only source rejection |
| `python3 -m unittest discover -s validation/tests -v` | 51 PASS; historical independent specification model |
| `sh firmware/test/run_host_tests.sh` | 38 C++ cases +17 CLI commands +6 configuration +6 compile-fixture upload guards PASS |
| `sh ios/scripts/test_portable.sh` | 38 XCTest tests, zero failures; production Swift logic |
| `swift build -j 2 --package-path ios/Shared/FeelCore` | PASS, production CLI built |
| `python3 validation/production/run.py` | 1,518 assertions; 558 firmware states; PASS |
| `pio run -j 2 --project-dir firmware` | ESP32 +ESP32-S3 builds PASS |
| `sh firmware/test/build_output_paths.sh` | Both enabled-output compile fixtures PASS; upload prohibited |
| `sh cad/build.sh` | 24/24 actual OpenSCAD exports PASS |
| `python3 cad/tools/check_stl.py stl/*/*.stl` | 24 closed/oriented, single-body, finite, on-bed meshes PASS |
| `python3 cad/tools/cam_sim.py` | 78/78 geometric checks PASS using actual cam polygon vertices |
| `python3 -m unittest discover -s cad/test -v` | 13 PASS, including collision/print gate and concurrent writer rejection |
| `python3 scripts/fetch_model.py` | Pinned genuine model: 62,200,325 bytes; SHA-256 PASS |
| `bash scripts/check_ios.sh` | PASS on hosted Xcode 16.4: 3 app unit + 1 UI tests; both simulator and unsigned device builds. Locally BLOCKED on Linux. |

Protocol tests cover all 65,536 sequence pairs and 10,000 seeded corruption steps.
Production cross-layer replay uses seed 20261016, five valid and eight invalid
hand-authored vectors, 160 randomized valid packets, bearing/range boundaries,
tracking/depth freshness, sequence wrap/reordering, disconnect, exact 500 ms
watchdog and uint32 rollover. It asserts commanded angles and tap timing. It also
illustrates undetectable legal-byte corruption and a synthetic stalled motor;
there is no physical position/jam feedback. The motor estimate of 300°/s is an
explicit simulation assumption, not a measurement.

The full STL manifest was independently checked against all 24 generated file
hashes. Cam contact includes polygon edge interiors and the conical follower,
A/H/G profiles, real firmware tap angles 21/37/138/154 and sampled transitions.
It omits friction, elastic force, tolerances, torque and tactile perception.

Additional executed checks: production replay and actual-STL viewers passed
headless Chromium rendering/controls and mobile width checks; screenshots were
visually inspected. Portable firmware also passed ASan/UBSan with leak detection
disabled because this environment restricts LeakSanitizer. These are supplementary
to the final runner, not extra invented unit-test counts.

The first integrated attempt had a missing PATH entry for PlatformIO and collided
with a simultaneous CAD export. The final run used the correct tool path and a
newly tested CAD output lock, and completed sequentially. Linux Swift requires
`SWIFT_USE_OLD_DRIVER=1`, private libncurses and direct XCTest because the host can
restrict subprocess monitoring; final build and all assertions completed. Raw
logs preserve their own timestamps and source-parent/dirty-state metadata.

Hosted Xcode typechecking, simulator execution and unsigned device builds passed;
the test/build completion lines are in `evidence/v1/ios-ci-excerpt.log`.
No CoreML inference, signed app installation, BLE radio, LiDAR, UWB, physical PWM,
servo/print, electrical or human tactile test was performed. See
`HARDWARE-BRINGUP.md` for the physical gates.

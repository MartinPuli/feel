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
check. Hosted CI for this revision is pending publication. The hardened firmware
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

# Current 120° revision

The user selected nominal FS0307 120° travel on October 16, 2026.
Current source and executed checks are recorded in [FS0307-120-DESIGN.md](FS0307-120-DESIGN.md).
The earlier local Mac session installed FEEL and verified actual Bluetooth packet
reception with the previous PWM-disabled firmware; the 120° revision has not
been flashed or physically tested. Camera UI response was user-reported.

## Historical foundation evidence (before the 120° revision)

# Executed V1 tests

October 16, 2026; Linux, Swift 6.1.3, OpenSCAD 2021.01, PlatformIO 6.1.18.
The final sequential run has **14 PASS and one BLOCKED** check. No physical device
was operated. Each log is under `docs/evidence/v1/`.

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
| `bash scripts/check_ios.sh` | BLOCKED: no Xcode, XcodeGen or iOS simulator on Linux |

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

Apple source syntax and independent API review are not Xcode typechecking.
No CoreML inference, simulator UI suite, signed app, BLE radio, LiDAR, UWB,
physical PWM, servo/print, electrical or human tactile test passed here: all remain
unperformed. See `HARDWARE-BRINGUP.md` for the physical gates.

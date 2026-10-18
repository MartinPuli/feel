> Current hardware: six columns, GPIO32 unused. Active slots1–6 map to
> GPIO33,25,26,27,14,13. See [six-column wiring](docs/SIX-COLUMN-LAYOUT.md).
> Existing angle settings are preserved. Earlier seven-column instructions below
> are historical; update both phone and firmware for six-sector perception.

# FEEL V3 — advanced

This branch adds explicit voice commands, a saved local map, adaptive target taps and QR/barcode finding on top of V2. See [ADVANCED.md](docs/ADVANCED.md).

> **FS0307 120° revision:** current CAD and firmware use 0/40/80/120° band positions.
> See [design and validation](docs/FS0307-120-DESIGN.md). Old 175° shafts/calibration
> are superseded. Default seven-servo PWM is disabled pending measured limits.
> The [midpoint demo](docs/SINGLE-SERVO-IPHONE.md) has user-reported motion.
> The opt-in [single-servo live profile](docs/SINGLE-SERVO-LIVE.md) uses nominal120° production mapping on GPIO32.

V3 includes V2 session memory and current V1 camera-first UI, firmware and CAD from
`main` (`b780519`). See [version guide](docs/VERSIONS.md) and
[current integration checks](docs/V3-MAIN-INTEGRATION.md).

**V1 is maintained on `main`.** It includes the current firmware and CAD,
Lantern with its [camera-first interface](docs/V1-CAMERA-UI.md), Beacon, and V1 validation tools.
Use `main` for all current V1 work. V2 and V3 remain separate development branches.

A prototype that translates indoor depth and target direction into a **7-column ×
4-pin tactile puck**, using a LiDAR iPhone, BLE, an ESP32 and seven servos.

**Greenfield recreation from HANDOFF-v7.md.** No original iOS, firmware or CAD
source was available. Historical “as built” statements in that document are not
verification of this repository. The earlier preparation work is preserved on
`feel/v2-preparation`; it uses the old version numbering.

| Branch | Purpose |
|---|---|
| `main` | Current V1: iOS apps, perception, BLE, ESP32, CAD and production replay |
| `feel/v1-foundation` | Preserved V1 development history; continue new V1 work on `main` |
| `feel/v2-spatial-memory` | Remember / Recall / Return, created only after V1 validation |
| `feel/v3-advanced` | V2 plus explicit voice commands, saved maps, adaptive taps and QR/barcode finding |

For the final seven-servo configuration, start with [SEVEN-SERVO-PRODUCTION.md](docs/SEVEN-SERVO-PRODUCTION.md).

To test the current app and single-servo setup, follow [TEST-V1.md](docs/TEST-V1.md).

To set up the board on your Mac, start with [SETUP-MAC-ESP32.md](docs/SETUP-MAC-ESP32.md).

See [release status](docs/RELEASE-STATUS.md) for actual checks and blockers.
**One-servo motion has been observed; full travel, seven-servo mechanics and sensing accuracy remain unverified.**

See [version guide](docs/VERSIONS.md) for V1/V2/V3 features and branch selection.

## Run software checks

Requirements: Swift5.9+ (Swift6.1.3 used locally), C++11 compiler, Python3.10+,
OpenSCAD2021.01+, PlatformIO6.1.18. macOS/Xcode and XcodeGen are needed for the iOS
platform apps. Linux tests compile the same Swift core and C++ controller used by
the device adapters; Linux cannot compile Apple frameworks.

```sh
sh ios/scripts/test_portable.sh
sh firmware/test/run_host_tests.sh
sh validation/adapters/run_contract_tests.sh
# Open .artifacts/production/index.html for the recorded offline replay.
pio run -j 2 --project-dir firmware
sh cad/build.sh
python3 cad/tools/check_stl.py stl/*/*.stl
python3 cad/tools/cam_sim.py
python3 scripts/run_v1_checks.py
python3 scripts/run_advanced_checks.py  # V3 plus inherited V1/V2 contracts
```

Full runner exits0 for complete pass,1 for failure,2 for blocked/not-run checks.
The report separates available checks from the complete software gate.

On a Mac:

```sh
python3 scripts/fetch_model.py  # Apple CoreML model; pinned revision + SHA-256
bash scripts/check_ios.sh      # simulator tests + unsigned device builds
cd ios
xcodegen generate
open Lantern.xcodeproj
```

Then select your signing team and physical device in Xcode. Do not infer LiDAR,
BLE, NI, tactile usability or mechanical reliability from the simulator.

## Source map

- [Codebase guide](docs/CODEBASE.md): how the apps, firmware, CAD, voice, and checks fit together.
- [`ios/`](ios/README.md): Lantern/FEEL app, Beacon companion, pure Swift core/tests.
- [`firmware/`](firmware/README.md): shared C++ controller, ESP32 adapters, host CLI/tests.
- [`cad/`](cad/README.md): parametric OpenSCAD test rig, puck, cams, pins and forearm pack.
- [`protocol/`](protocol/vectors.json): exact wire cases; [`docs/PROTOCOL.md`](docs/PROTOCOL.md) gives policy.
- [`validation/production/`](validation/production/README.md): compiled cross-layer replay.
- `validation/feel_model.py`: historical independent reference model, not device code.

## Build and demonstrate honestly

Use [hardware bring-up](docs/HARDWARE-BRINGUP.md), [calibration](docs/CALIBRATION.md),
[demo](docs/DEMO.md), [Devpost draft](docs/DEVPOST.md), and [eligibility disclosure](docs/ELIGIBILITY.md).

Only one pin per column can be selected. Neutral is not proof of clear space.
Servo commands are not position measurements. The handoff's servo/horn dimensions
and supply/pulse endpoints require physical confirmation before final printing or
powered integration. Door candidates are heuristics; trained object detection is
provided through a separate model with its own limitations.

FEEL is an experimental perception interface, not a certified mobility aid or a
route planner. Test indoors with a spotter after the bench checklist passes.

## Where Chalk is used

FEEL's assistant has a `where_is` tool: "Where is the registration desk?" sends one camera
photo and the question through **Chalk's Model Gateway** (`openai/gpt-6.1-sol` by default)
to a vision model, places the answer in the room with LiDAR depth, and the puck taps toward
it until you arrive. **Chalk Evaluations** score the tool on labeled venue photos: pointing
accuracy, well-formed replies, and the false-found rate (claiming to see something absent).
Without Chalk settings, or when the gateway can't be reached, `where_is` falls back to the
phone's own Vision and Core ML detector (EXIT signs, doors, people, chairs, common objects).
Details, setup and the evaluation commands: [chalk/README.md](chalk/README.md).

# FEEL V2 — Spatial Memory

This isolated branch adds Remember, Recall, an explicit Return point and multiple
bookmarks. Start with [SPATIAL-MEMORY.md](docs/SPATIAL-MEMORY.md). The available
V2 software checks pass; Apple-platform and physical validation remain separate.

A prototype that translates indoor depth and target direction into a **7-column ×
4-pin tactile puck**, using a LiDAR iPhone, BLE, an ESP32 and seven servos.

**Greenfield recreation from HANDOFF-v7.md.** No original iOS, firmware or CAD
source was available. Historical “as built” statements in that document are not
verification of this repository. The earlier preparation work is preserved on
`feel/v2-preparation`; it uses the old version numbering.

| Branch | Purpose |
|---|---|
| `feel/v1-foundation` | Swift iOS + perception + BLE, ESP32, CAD, production replay |
| `feel/v2-spatial-memory` | Remember / Recall / Return, created only after V1 validation |
| `feel/v3-advanced` | Optional advanced work, only after V1 and V2 |

To set up the board on your Mac, start with [SETUP-MAC-ESP32.md](docs/SETUP-MAC-ESP32.md).

See [release status](docs/RELEASE-STATUS.md) for actual checks and blockers.
**No real hardware has been tested in this build environment.**

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

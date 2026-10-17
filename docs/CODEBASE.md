# FEEL codebase

FEEL turns indoor depth and a chosen target into a palm puck. The puck has seven columns and four pins in each column. One FS0307 servo and one camshaft drive each column, so only one pin in a column can be up at a time. An iPhone with LiDAR decides which pins to raise. An ESP32 in a forearm pack receives a nine-byte BLE packet about ten times a second and commands the servos.

`main` is the current V1 line: iOS apps, the shared Swift core, ESP32 firmware, OpenSCAD, the Chalk where-is path, and the validation tools. Older work stays on `feel/v1-foundation`, `feel/v2-spatial-memory`, and `feel/v3-advanced`. Do not merge those branches into V1 unless that is an explicit request.

This tree is a greenfield recreation from `HANDOFF-v7.md`. The handoff is a specification. Passing tests here do not prove that a printed cam, a real servo, LiDAR, BLE, or UWB behaved as the tests describe. Servo body and horn sizes in CAD are still unmeasured placeholders. Default seven-servo PWM stays off. The opt-in GPIO32 profile has user-reported motion. Full travel, seven-column mechanics, and sensing accuracy are still open. FEEL is an experimental interface. It is not a certified mobility aid and it does not plan a route.

The mechanical and firmware design uses the FS0307 nominal 120° map: band centers at 0°, 40°, 80°, and 120°, gaps at 20°, 60°, and 100°, pulses from 900 µs to 2100 µs. That map replaces the older 175° / 650 to 2500 µs notes. 120° is the selected design. Travel of the servo in hand is still unmeasured. See `docs/FS0307-120-DESIGN.md`.

## How a live frame becomes a pin

1. `LanternModel` starts live sensing after the camera permission check. `ARPerception` runs an ARKit session with scene depth.
2. Each frame keeps pose, intrinsics, a confidence-filtered depth grid, and any finder result from the same instant. Depth older than 250 ms, lost tracking, or a missing floor calibration becomes an all-zero packet.
3. `DepthProjector` keeps samples whose world height is 0.60 m to 2.10 m above the calibrated floor. It stores the nearest horizontal range in each of seven sectors from −45° to +45°. Camera +x is right, +y is up, and −z is forward. An exact sector boundary goes to the sector on its right. Bearings outside that field are dropped.
4. `TactileGeometry.band` maps a positive distance: under 0.9 m is band 1, then 1.6 m, 2.5 m, and 4.0 m for bands 2, 3, and 4. Missing, nonpositive, or farther than 4 m is band 0. Band 0 means no pin request. It does not mean the space is clear.
5. If a finder or a held where-is target is valid, `TactileEncoder` may raise that column and set the highlight byte so the firmware taps it. A closer obstacle already in that column stays. The tap is a direction cue.
6. `LanternModel` ticks every 100 ms, advances the sequence byte, and hands the packet to `BluetoothPuck`. Simulation uses the same encoder on a synthetic scene and never writes those packets to BLE.
7. The ESP32 copies the write into a queue. Only `loop` calls `feel::Controller`. A legal packet updates commanded angles. After 500 ms without an accepted packet, the controller drops every column into the nearest gap and clears the sequence baseline.
8. Pulse width is `900 + 10 * degrees` microseconds, clamped to 900 through 2100, so 60° is 1500 µs. Default builds leave the GPIOs low. The controller records the angle it commanded. It has no position sensor.

Column 0 is the wearer's left and column 6 is the right, wrist toward the wearer, band 1 at the wrist and band 4 toward the fingers. Confirm that mapping on a physical puck before trusting it.

## Repository map

| Path | What lives there |
|---|---|
| `ios/Lantern/` | FEEL iPhone app. Display name FEEL, target name Lantern. |
| `ios/Beacon/` | Second-phone app that shares a Nearby Interaction session. |
| `ios/Shared/FeelCore/` | Portable Swift package: packet, geometry, encoder, where-is parser, replay CLI. |
| `ios/Shared/Apple/` | UI theme and Multipeer / Nearby Interaction service. Apple frameworks only. |
| `ios/project.yml` | XcodeGen spec. Regenerate the Xcode project from this file. |
| `firmware/` | C++ controller, ESP32 BLE adapter, host simulator, PlatformIO envs. |
| `firmware/bench-single/` | Separate one-servo serial bench, not the nine-byte puck protocol. |
| `cad/` | OpenSCAD parameters, test column, puck, forearm pack, mesh and cam checks. |
| `protocol/` | Normative nine-byte vectors and the shared where-is prompt and cases. |
| `chalk/` | Python client and evaluation for Chalk's Model Gateway. |
| `services/voice-token/` | Small Node service that mints a short-lived OpenAI Realtime credential. |
| `validation/` | Historical Python reference model, plus production replay of the real Swift and C++ CLIs. |
| `scripts/` | Source checks, model fetch, iOS check wrapper, V1 check runner. |
| `docs/` | Bring-up, protocol, release evidence, and this guide. |

`HANDOFF-v7.md` and `AGENTS.md` describe intent and engineering rules. When they disagree with the code, the code is what runs. Record the disagreement instead of silently changing behavior.

## iOS

XcodeGen builds `Lantern.xcodeproj` from `ios/project.yml`. Deployment target is iOS 16. Marketing version is 1.0.0, build 14. Bundle ids are `org.feel.hackharvard.lantern` and `org.feel.hackharvard.beacon`. Edit `project.yml`, then run `xcodegen generate`. The generated project is disposable.

```sh
python3 scripts/fetch_model.py
cd ios && xcodegen generate
sh scripts/build.sh
FEEL_SIMULATOR_ID='<available UUID>' sh scripts/test.sh --ios
sh ios/scripts/test_portable.sh
```

`fetch_model.py` downloads the pinned Core ML detector and checks its SHA-256. `test_portable.sh` builds FeelCore and runs its XCTest suite without Apple frameworks. A simulator run does not exercise real LiDAR, UWB, or a BLE puck.

### Lantern

`LanternApp` owns one `LanternModel`. Backgrounding stops guidance and pauses the microphone. Returning to the foreground resumes voice unless the process was launched with `--uitesting`.

`LanternModel` is the main-queue coordinator. `RunMode` is `STOPPED`, `LIVE`, or `SIMULATION`. It owns `ARPerception`, `BluetoothPuck`, `NearbyPeerService` in the seeker role, and `RealtimeVoiceSession`. A 10 Hz timer calls `tick`, which encodes the latest frame or the simulation script and sends the packet. `stop` increments a generation counter, clears held targets, sends a neutral packet if a puck is connected, and pauses AR. Callbacks from an older generation are ignored. The same generation check drops finder results after the user changes mode.

`LanternView` is the camera-first screen: a live preview, a chevron drawer for the 7×4 pin display and status, and floating connection and settings panels. `PuckView` draws the packet the phone believes it sent. `VoiceControls` and `WhereIsSetup` are the assistant and Chalk setup sheets. Visual design tokens live in `FeelDesign.swift`.

Phone mount, from `ios/README.md`: landscape, rear camera facing forward, top edge of the phone to the wearer's left. The app requests `UIInterfaceOrientationLandscapeRight`. UIKit's interface name is opposite the physical rotation. Lens height is entered by the user, 0.60 m to 2.10 m. Floor Y is camera world Y minus that height. ARKit's world origin is never treated as the floor.

### Perception and finding

`ARPerception` is the ARKit session delegate. It samples depth, rejects low confidence, and calls `ObjectDetector` on a Vision queue. `ObjectDetector` loads `FEELDetector.mlmodelc` when the fetch script has installed it. Finder modes are obstacles, door candidate, EXIT sign, chair, person, and teammate.

| Mode | Detector |
|---|---|
| Obstacles | Depth sectors only. |
| EXIT sign | Vision text recognition for the word EXIT. |
| Door candidate | Vision rectangles with a door-like aspect ratio. A candidate is a heuristic. |
| Person | Core ML label `person`, otherwise Vision human rectangles. |
| Chair | Core ML label `chair`. Unavailable until the model is bundled. |
| Teammate | Nearby Interaction, below. No image detector. |

Detections are stored as world points in `CapturedTarget` and reprojected as the camera moves. They expire after 500 ms. A new session or a new finder selection drops queued results from the old epoch.

`NearbyPeerService` browses or advertises `_feel-beacon` over Multipeer Connectivity, exchanges a discovery token only after the other phone accepts, and reads `NISession.worldTransform` in the shared AR world. A missing direction is left missing. Beacon can show a distance while FEEL still has no usable direction. Lost, suspended, or stale direction clears both the displayed target and the world-space cache. One teammate is paired at a time.

### Where-is

`where_is` is for a thing the fixed finder list does not name, such as a registration desk. `WhereIsService` takes one JPEG from the current AR frame, long side at most 1024 px, quality 0.6. `ChalkGateway` posts it to `{host}/v1/router/chat/completions` with the gateway key and `X-Chalk-Env-Id`. The default model is `openai/gpt-6.1-sol`. The timeout is 12 seconds. The prompt and parser live in `FeelCore/WhereIs.swift` and must match `protocol/where-is-prompt.txt` and `protocol/where-is-cases.json`.

A found answer is a box in normalized top-left image coordinates. `WhereIsPlacement` reads the median LiDAR depth at the box center, unprojects it, and stores a `HeldTarget` in world coordinates. Later ticks re-express that point against the current pose. Arrival is horizontal distance under 0.5 m. More than 45° off center, or farther than 4 m, the pins stay down and the app speaks a coarse direction. A tracking reset ends the hold. A newer question cancels the previous request.

If Chalk is unset or the gateway fails, `LocalWhereIs` runs the on-device detector on the same photo. `LocalVocabulary` maps a short phrase onto EXIT, a door candidate, a person, or a COCO-style object label. Unknown phrases produce no tap. A malformed or unsure model reply produces no tap.

### Voice

`RealtimeVoiceSession` streams microphone audio to the OpenAI Realtime API. `VoiceTokenClient` asks `services/voice-token` for an ephemeral credential. The OpenAI API key stays on that server. The phone stores only the FEEL access token, in the Keychain via `KeychainStore`.

The model may call only the tools in `VoiceCommand`. `decode` rejects extra arguments, non-boolean JSON for flags, and heights outside 0.60 m to 2.10 m. `LanternModel.performVoiceCommand` applies the command and returns a status dictionary. The model is told to call `get_status` before describing the room. "Silence yourself" mutes speech and leaves the microphone on. "Stop listening" ends capture and needs a touch to resume. Backgrounding or locking the phone pauses capture.

`ProactiveVoicePolicy` decides when to speak an unsolicited notice: a new nearby obstacle, a target appearing or disappearing, sensing recovery. The user can disable those notices without disabling replies.

`VoicePhrasing` turns guidance and connection states into the sentences the app speaks. `VoiceAudioIO` handles the capture and playback formats.

### Bluetooth

`BluetoothPuck` scans, connects only to a peripheral the user selected, and writes the nine-byte command. It keeps a newest-only queue, drops stale queued writes, and checks that callbacks belong to the selected peripheral. It decodes the 15-byte status notification into `PuckStatus`. Status text distinguishes physical PWM disabled, PWM enabled and still physically unverified, and a latched output fault. A notification does not prove a pin moved.

UUIDs, shared by Swift and C++:

| Role | UUID |
|---|---|
| Service | `7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000` |
| Command, write | `7D2A0002-5C6B-4F9A-8E21-0BCE7F0A1000` |
| Status, read and notify | `7D2A0003-5C6B-4F9A-8E21-0BCE7F0A1000` |

The advertised name for the seven-column firmware is `FEEL Puck`. The single-servo live adapter advertises `FEEL Center Live`.

### Beacon

`BeaconApp` hosts `NearbyPeerService` in the beacon role. The screen shows status, an invitation that must be accepted, the connected peer name, and a measured distance when Nearby Interaction provides one. Backgrounding stops sharing. Beacon does not encode tactile packets and does not talk to the ESP32.

### FeelCore

The package has no Apple imports, so Linux can compile it. Products are the `FeelCore` library and the `feel-replay` executable.

| File | Responsibility |
|---|---|
| `Protocol.swift` | `FeelPacket` encode and decode, band and column math, `PuckStatus`, `PeripheralSelection`. |
| `Perception.swift` | Pose, intrinsics, sector projection, `TactileEncoder`, short-lived `CapturedTarget`. |
| `DepthGrid.swift` | Depth image and the median sample used to place a where-is box. |
| `WhereIs.swift` | Prompt, request body, strict JSON parse. No networking. |
| `HeldTarget.swift` | World-space hold, arrival radius, placement from a snapshot. |
| `LocalWhereIs.swift` | On-device vocabulary and the pure hold-or-speak decision. |
| `FeelReplay/main.swift` | One JSON command per stdin line, one JSON reply. |

`feel-replay` accepts `encode`, `decode`, `perceive`, and `replay`. `encode` rejects illegal bands and highlights. `perceive` runs `TactileEncoder` and returns the packet hex. Root production replay feeds those packets into the C++ controller. See `ios/README.md` for the JSON shapes.

## Firmware

The board adapter and the host simulator both link `firmware/src/controller.cpp`. Host tests exercise that controller. They do not move a servo.

```sh
sh firmware/test/run_host_tests.sh
sh firmware/build.sh
python3 -m platformio run -d firmware -e esp32 --target upload
```

Upload only with the matching board connected and servo power removed. PlatformIO is pinned to `platformio==6.1.18`, Espressif32 6.9.0, Arduino-ESP32 2.0.17, and NimBLE-Arduino 2.3.6. PWM is LEDC at 50 Hz, 14-bit, seven channels. There is no ESP32Servo dependency.

### Controller

`feel::Controller` is single-threaded. `decodePacket` requires exactly nine bytes, bands 0 to 4, and a highlight of 0 to 6 or 255. Any failure leaves outputs unchanged and does not refresh the watchdog. A highlight on a column whose band is 0 is legal on the wire. The controller treats that highlight as 255.

Sequence policy: the first valid packet after connect or timeout sets the baseline. Later packets must have a modulo-256 delta of 1 to 127. Delta 0 is a duplicate. Delta 128 to 255 is stale. Rejections do not refresh the watchdog.

Angles: bands 1 to 4 command 0°, 40°, 80°, 120°. Dropping a band commands the nearest gap, 20°, 60°, or 100°, and a tie takes the lower angle. Startup neutral is 20° on every column. A highlight dips 13° toward that gap for the first 100 ms of a 600 ms cycle. Repeating the same highlight at 10 Hz does not restart the tap. Changing column or band does.

Calibration offsets are finite and within 5° of zero. They are added to non-raw positions and clamped to 0 to 120°. `CAL save` writes a version-2 blob under the NVS key `offsets_120_v2`. The old `offsets_v1` key is never read. Raw `US` pulses bypass the offset and must sit inside 900 to 2100 µs.

A jump from band 1 to band 4 sweeps through the cams between them. The controller does not promise that neighboring pins stay down during that move.

`OutputGuard` refuses to enable PWM unless `FEEL_ENABLE_SERVO_OUTPUT`, `FEEL_VERIFIED_PULSE_MIN_US`, and `FEEL_VERIFIED_PULSE_MAX_US` are all set, ordered, and inside 900 to 2100 µs. Before any update it checks all seven commanded pulses. An out-of-range command detaches every channel and latches a fault until reboot.

### Board adapter

`firmware/src/main.cpp` is the Arduino sketch. NimBLE accepts one connection, no pairing. Callbacks enqueue connect, disconnect, and packet events. `loop` drains that queue, runs the controller, and then writes PWM. Queue entries older than 500 ms are dropped. Overflow discards pending commands, commands neutral, and disconnects.

Status is 15 bytes: version 1, connected, active, sequence valid, last sequence, effective highlight, bench armed, output state, then seven bands. Output state 0 is PWM disabled, 1 is PWM initialized with the range guard ready, 2 is a latched fault. Notifications go out about every 200 ms and never count as a keepalive.

Classic ESP32 GPIOs, columns 0 through 6: 32, 33, 25, 26, 27, 14, 13. The ESP32-S3 DevKitC-1 map is an assumption: 4, 5, 6, 7, 8, 9, 10. Do not copy the classic list onto an S3. ESP32-C3 and C6 are unsupported because this design wants seven independent PWM channels.

Serial is 115200 baud, one newline-terminated command per loop, 96-byte budget. `ARM` starts a 30-second bench lease and is rejected while BLE is connected. `B c b` sets one column. `HL` taps. `US` sends one raw pulse and neutrals the others. `KEEP` refreshes an active bench command and cannot revive a timed-out one. `STOP` neutrals and disarms immediately. `STATUS` and `HELP` print state. `firmware/tools/bench.py` holds a supervised position for a few seconds.

### Build environments

| Environment | What it does |
|---|---|
| `esp32` | Default classic board. PWM disabled. |
| `esp32s3` | Default S3 compile. PWM disabled. The confirmed boards are classic ESP32-WROOM modules. |
| `esp32-compilecheck`, `esp32s3-compilecheck` | Compile the enabled-output path with unmeasured 900/2100 fixtures. Upload is rejected. Never flash these binaries. |
| `esp32-single-demo` | GPIO32 only, nominal 1450 to 1550 µs midpoint demo. |
| `esp32-single-live` | GPIO32 follows production center-column pulses, nominal 900 to 2100 µs. Boot, all-zero packets, disconnect, and the 500 ms timeout detach the pin. Serial accepts `STATUS`, `STOP`, and `HELP` only. |
| `esp32-production` | Seven GPIOs, but the prebuild hook requires `firmware/production-measurements.local.json` with seven attested ranges that each cover 900 to 2100 µs. That file is gitignored and absent. The example file cannot enable output. |

`firmware/host/simulator.cpp` builds `feel-sim`. It reads `CONNECT`, `PACKET`, `TICK`, and the bench commands, and prints JSON with `mode: "SIMULATION"`. The clock and the servo outputs are fake. The decoder is the production one. There is no torque, lag, or radio model.

`firmware/bench-single/` is an earlier one-servo serial sketch with its own state machine. Use it only for that isolated bench. The puck protocol lives in `firmware/src`.

## Mechanical CAD

`cad/params.scad` holds the numbers. `cad/lib.scad` builds profiles and shared solids. `cad/test_column.scad` is the hand-cranked single column. `cad/puck.scad` is the seven-column puck. `cad/pack.scad` is the forearm tray. `cad/tools/cam_sim.py` runs the same cam polygon the STL export uses and checks that a selected pin lifts about 2 mm while the gaps and the 13° tap leave neighbors down. `cad/tools/check_stl.py` requires finite coordinates, nonzero volume, closed edges, one body, and bed contact at Z=0.

```sh
sh cad/build.sh --fast
sh cad/build.sh
python3 cad/tools/check_stl.py stl/*/*.stl
python3 cad/tools/cam_sim.py
python3 -m unittest discover -s cad/test -v
```

The array is seven columns on a 12 mm pitch. Pin rows sit at Y = −8, 4, 16, and 28 mm. The shaft axis is Y at Z = 17.5 mm. Lobe half-width is 12°. A 24° lobe at these band centers would lift the neighbor. Stroke is an ideal 2 mm. Three cam profiles, A, H, and G, change the flank shape. They are geometry variants, not measured holding force. Foam return, hole finish, and servo fit are physical tests P1 through P5 in `cad/README.md`. `sh cad/build.sh --print-ready` exits 2 until `measurements_confirmed` and `horn_fit_confirmed` are set in `params.scad`. Setting those flags does not certify the mechanism.

`cad/viewer/index.html` shows the exported triangles in the browser. Cams in that view are fixed at band 2.

## Wire contract

`protocol/vectors.json` is the byte-for-byte contract. `docs/PROTOCOL.md` states the policy in prose. Both Swift `FeelPacket` and C++ `decodePacket` / `encodePacket` are tested against those vectors by `validation/production/run.py`.

The packet is `[sequence, b0, b1, b2, b3, b4, b5, b6, highlight]`. There is no checksum, timestamp, session id, or authentication. A corrupted byte that is still a legal value will be obeyed. The 500 ms watchdog limits silence. It does not prove the depth frame was fresh. The phone has to do that before it encodes.

## Chalk

`chalk/feel_chalk/where_is.py` parses the same JSON contract as `WhereIs.swift`. `gateway.py` calls the Model Gateway with the standard library only. Settings come from `chalk/.env`, which is gitignored. `check_connection.py` checks reachability without sending a photo. `where_is_eval.py` uploads labeled venue photos and scores three things: the box center lands inside the labeled box or the model correctly says not found, the reply matches the JSON contract, and the model did not claim to see something absent. `images.py` re-encodes uploads the way the phone does.

```sh
cd chalk
python3 check_connection.py
python3 -m unittest discover -s tests -v
```

Evaluation photos stay in `chalk/data/`, also gitignored. The app sends a photo only after the user asks where something is.

## Voice token service

`services/voice-token/` is Node 22 with no packages and no database. `POST /session` with `Authorization: Bearer <FEEL_VOICE_ACCESS_TOKEN>` returns `{value, expires_at}`. The value is a short-lived OpenAI Realtime credential. The service never receives camera frames or conversation audio. The local server binds 127.0.0.1 on port 8081. The phone must reach it through HTTPS. `api/session.mjs` is the same handler for Vercel. In-memory rate limits reset when an instance cold-starts, so they are not an account-wide quota. Credentials belong in the host's secret store, never in the repo.

## Validation and checks

Two Python layers exist, and they are not the same thing.

`validation/feel_model.py` is an independent reference model written when the production sources were missing. `validation/run_scenarios.py` replays fixtures under `validation/fixtures/` with seed `20261016` and writes `.artifacts/simulation/`. It does not call Swift or C++. Treat it as a historical spec model.

`validation/production/run.py` starts the real `feel-replay` binary and the real `feel-sim` binary. It checks golden bytes, malformed packets, distance boundaries, bearings, stale depth, tracking loss, sequence wrap, disconnect, and the 500 ms boundary. Invalid packets must leave the controller outputs unchanged. The HTML trace is a view of that report. A motor drawing in the page uses an unmeasured 300°/s guess so a stalled command is visible. It is not a physics result.

```sh
sh validation/adapters/run_contract_tests.sh
python3 scripts/run_v1_checks.py
python3 scripts/check_sources.py
```

`scripts/run_v1_checks.py` is the aggregate runner. Exit 0 means the checks it could run passed. Exit 1 is a failure. Exit 2 means something was blocked or not run. `scripts/check_ios.sh` is the Mac simulator and unsigned device path.

GitHub Actions workflow `.github/workflows/validation.yml` runs on `main`, `feel/**`, and `codex/**`. One macOS job runs source checks, FeelCore tests, firmware host tests, and production replay. One Ubuntu job compiles the ESP32 environments and the host tests. One Ubuntu job exports CAD and runs the mesh and cam checks. A green workflow is a software result. It does not flash a board.

## What the tests cover

Software checks can fail a bad packet, a stale depth frame, a sequence replay, a cam polygon that lifts two pins, or a Swift encoder that disagrees with the C++ decoder. They cannot tell you whether a printed pin returns when the puck is upside down, whether seven servos stay inside the supply's current limit, whether the LiDAR range is accurate on a given floor, or whether a blind user can read the tap. Those results belong in `docs/RELEASE-STATUS.md` and `docs/TEST-REPORT.md` only after someone has actually run them.

Read next, depending on the job:

| Job | Document |
|---|---|
| Current pass and fail table | `docs/RELEASE-STATUS.md` |
| Byte policy | `docs/PROTOCOL.md` |
| iOS build and mount | `ios/README.md` |
| Flash, bench, PWM gate | `firmware/README.md` |
| Print and P1 through P5 | `cad/README.md` and `docs/HARDWARE-BRINGUP.md` |
| One servo on GPIO32 | `docs/SINGLE-SERVO-LIVE.md` |
| Seven servos after measurements | `docs/SEVEN-SERVO-PRODUCTION.md` |
| Where-is setup and evals | `chalk/README.md` |
| Voice credential server | `services/voice-token/README.md` |
| Known defects | `docs/KNOWN-ISSUES.md` |

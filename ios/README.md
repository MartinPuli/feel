# FEEL V2 iOS — Spatial Memory

This source recreates the intended system from the handoff. No original Swift project or model weights were recovered. Historical handoff test counts do not apply to this implementation. `Lantern` is the internal app target; the display name is FEEL. `Beacon` is the second-phone app. This V2 branch adds session-only Spatial Memory to the latest V1 on `main`, including its Geist interface and persistent Stop control.

## What is implemented

- SwiftUI run screen, accessible labels, visible live/simulation/uncertain states, stop action and a seven-column virtual puck.
- ARKit world tracking and native LiDAR `sceneDepth`, pixel confidence filtering, scaled intrinsics, floor-relative height rejection and nearest horizontal range per sector.
- Vision/CoreML adapter, built-in EXIT OCR, person detection and honestly labeled door candidates. Chair uses the separately downloaded genuine pretrained model.
- BLE discovery and explicit puck selection, nine-byte commands at 10 Hz, write backpressure, newest-only queue, stale-queue expiry, callback identity checks, serialized same-device reconnect, and the firmware's 15-byte status decoder.
- Beacon/FEEL encrypted Multipeer token exchange with explicit acceptance; Nearby Interaction shares FEEL's AR session and uses Apple's world transform for directional guidance. Missing direction is not replaced by a guess.
- Shared production Swift library, command-line replay and portable XCTest tests. The app and replay compile the same encoder, geometry and cache logic.

## Build on a Mac

Use Xcode 16 or later, iOS 16 or later, and XcodeGen. Select the installed full Xcode in `xcode-select` if command-line tools alone are active. No developer credentials are stored here.

```sh
# From the repository root:
python3 scripts/fetch_model.py
cd ios
xcodegen generate
xcodebuild -list -project Lantern.xcodeproj
xcrun simctl list devices available
sh scripts/build.sh

# Select an actual available simulator UUID from the preceding list:
FEEL_SIMULATOR_ID='<available UUID>' sh scripts/test.sh --ios
```

`build.sh` compiles both applications for an iOS simulator without signing. `test.sh --ios` runs shared core tests, then the Lantern app test scheme, including the simulation/stop UI test. It does not pretend a simulator has LiDAR, UWB or a BLE puck.

Open `Lantern.xcodeproj`, select your own signing team for each application, and use unique bundle identifiers if required. Run Lantern on the LiDAR iPhone and Beacon on a second compatible UWB iPhone. A free development account can be used where Xcode permits. Follow the device's Developer Mode/trust prompts. Device installation, permissions and signed builds require your Mac and phones.

The generated Xcode project is disposable; edit `project.yml`. The `FeelCore` dependency is a local Swift package, so core builds require no package downloads.

## Portable builds and production replay

Swift 5.9+ is sufficient for the package (validated here with Swift 6.1.3 Linux).

```sh
sh ios/scripts/test_portable.sh
swift build --package-path ios/Shared/FeelCore -c release
ios/Shared/FeelCore/.build/release/feel-replay stdio
```

Send one JSON object per line; each command immediately returns one JSON object. The tool never waits for stdin to close before replying.

```json
{"op":"encode","seq":1,"bands":[1,2,3,4,0,0,0],"highlight":3}
{"op":"decode","hex":"010102030400000003"}
{"op":"perceive","seq":2,"now":10,"frameTimestamp":9.9,"tracking":true,"distances":[0.7,1.2,null,2.0,3.5,null,null],"target":{"bearingDegrees":30,"distance":1.3,"timestamp":9.9}}
```

`encode` strictly validates bytes. `decode` returns `valid:false` and an error for invalid input. `perceive` uses the exact app encoder and returns `hex`, `seq`, `bands`, `highlight`, and `state`. Times are monotonic seconds; a missing range is JSON `null`. `floorCalibrated:false` tests the neutral uncalibrated state. `replay path.json` accepts a nonempty array of those commands with optional `expectedHex`; a mismatch is a nonzero process exit. Root production replay additionally passes the actual Swift packets into the actual C++ firmware controller.

`synth scene.json out.feelrec` renders a deterministic synthetic depth recording, and `session in.feelrec` replays a recording (synthetic or recorded in Lantern with **Record depth**) through the app's depth step and 10 Hz tick, printing one packet per tick. `simulation/run.py` drives both through the firmware controller and scores the pin grid against labels; see [simulation/README.md](../simulation/README.md).

For the restricted build host used in this session only, Swift's new driver and occasionally its test subprocess monitor crash because child `/proc/<pid>/stat` cannot be read. The official legacy-driver switch `SWIFT_USE_OLD_DRIVER=1` makes compilation possible. `test_portable.sh` builds, then executes XCTest directly. The host can still intermittently fail in its process monitor; standalone XCTest runs have completed cleanly. Record that environment failure separately from assertion results. A private verified `libncurses6` is also supplied by `LD_LIBRARY_PATH`. This is an environment workaround, not a source-code test skip; build/test failures still exit nonzero. A normal Mac or Linux installation needs none of those host-specific paths.

## Phone mounting and floor calibration

1. Keep the rear camera facing forward in **UIDevice landscape-left** orientation: the phone's top edge/camera end points to your left as you look at its screen. This is native ARKit camera orientation. The app requests `UIInterfaceOrientationLandscapeRight`; UIKit's interface naming is opposite the physical-device rotation.
2. Keep the phone's camera-up axis roughly vertical. The app neutralizes when excessive roll/orientation makes the fixed mount invalid. Face the same direction as the wearer; turning the phone separately changes the tactile reference frame.
3. Measure the lens height above the floor. Enter it in the app (0.60–2.10 m), start Live, wait for normal tracking and tap **Calibrate floor**. The baseline is `camera world y − measured lens height`; ARKit's arbitrary world origin is never assumed to be the floor. Recalibrate after an AR reset, interruption or change of mounting height/environment.
4. Start with a stationary cardboard obstacle at center, left and right. Confirm the intended column in the virtual puck before enabling any mechanical output. Log actual direction sign and range on the phone.

World points 0.60–2.10 m above the calibrated floor are considered. The upper bound is a documented engineering assumption absent from the reference. Distance bands use horizontal radial range (not optical z distance): positive distances below 0.9 m → band1, [0.9,1.6) →2, [1.6,2.5) →3, [2.5,4.0] →4. Positive distances below the handoff's nominal 0.3 m minimum conservatively remain near band1. Nonfinite/nonpositive/>4 m/unknown samples are neutral, not proof of clearance.

Seven equal horizontal sectors span −45°...+45°, including the endpoints; exact internal boundaries select the right sector. Camera +x points right, +y up and −z forward. Native depth and Vision buffers remain in the same capture orientation; Vision bottom-left box coordinates are converted to top-left depth coordinates.

Only medium/high-confidence depth contributes. The app samples every third depth pixel; thin objects may be missed. A fresh normal frame is required, and depth older than250 ms neutralizes all output. Target detections expire after500 ms. Detection image/depth/pose are captured together, stored in world coordinates and reprojected after camera motion. Session and finder epochs discard queued results from old sessions/selections. A closer obstacle remains encoded when a target shares its column. A tapping target indicates direction only.

## BLE and physical-output status

Choose the intended device under **Puck connection**; the app does not automatically connect to an arbitrary puck. Packets use the UUIDs in `FeelBLE`, matching the firmware. Connection/status notifications do not prove actuation.

Status decoding explicitly distinguishes **Physical PWM DISABLED**, **PWM enabled — unverified physically**, and **OUTPUT FAULT**. The current CAD/controller targets the user-selected FS0307 nominal 120° / 900–2100 µs design. Servo PWM remains disabled until actual pulse limits, power and single-column mechanics are verified. The old 175° design is superseded; do not reuse its shafts or saved calibration. Never send a servo sweep based only on virtual pins.

The nine-byte command has no application checksum or timestamp. A valid-looking changed byte/delayed packet cannot always be detected by this protocol. BLE transport behavior and real firmware timeout must be measured; host simulation is not radio validation.

## Teammate finding

Start Live on FEEL, calibrate the floor, choose **Teammate**, and select **Find Beacon phones**. On the other phone, open Beacon and press **Start sharing**. Select that named phone in FEEL and explicitly accept on Beacon. Only one teammate is paired at once; serialized discovery tokens use secure decoding and an encrypted Multipeer session. Keep both applications foreground.

FEEL enables camera assistance with its existing AR session. Only an available, current `NISession.worldTransform(for:)` in that same AR world yields a target. Raw NI direction is not treated as AR camera coordinates. Beacon can show distance without implying that FEEL has a usable direction. Lost/suspended/missing direction immediately clears both displayed and world-space target caches. Removal callbacks only affect the active discovery token. Suspension blocks updates; timeout/resumption rotates the NI session and discovery token, so delayed callbacks from the old session cannot restore guidance. Invalidated sessions require a fresh start.

Apple recommends portrait orientation for strongest NI performance; FEEL's fixed landscape prototype may reduce NI availability. Test the complete landscape mount with two real phones before promising this feature. Door/EXIT/person finding remains independent of the companion phone.

## Direction arrows (V sign)

**Settings → Direction arrows** (on by default) draws one tactile arrow toward the selected target when the wearer asks. It reuses the normal nine-byte packets at 10 Hz, with no firmware or protocol change. Source: `FeelCore/HandSign.swift`, `FloorGrid.swift`, `DirectionCues.swift`, `Lantern/Services/HandSignDetector.swift`; tests in `DirectionTests.swift`.

- **Request sign:** a V, with index and middle fingers straight and spread, ring and little fingers folded, held about 0.5 s.
  - Any rotation works: the check uses joint distances and angles only.
  - The hand must look closer than 0.55 m, estimated from palm size, so bystanders' hands don't count.
  - After firing, the sign must disappear for 0.8 s before it can fire again.
  - It is not checked while the puck's point-to-describe codes are in view. It runs on the pointing queue with the same image, so no extra ARKit frame is retained.
- **Floor map:**
  - Medium/high-confidence LiDAR points become 10 cm cells.
  - Anything 10 cm–2 m above the calibrated floor blocks a cell, including bags and chair legs below the 0.6 m sector window.
  - Floor hits mark cells free and wear away old obstacle hits, so people who move away clear.
  - Cells beyond 8 m are dropped.
  - The map resets on start, stop, calibration, finder change and AR interruption.
- **Route:**
  - About 2.5 times a second, but only while the target is in view right now, A* runs from the wearer to any open cell within 0.7 m of the target.
  - Cells within 0.3 m of an obstacle, and unknown cells, cost extra.
  - The arrow aims at the route point 1.2 m ahead, relative to the camera's facing direction.
- **Arrows** (fingers = forward):

  | Cue | Bearing | Pattern |
  |---|---|---|
  | Straight | ≤ 15° | a V growing to `1234321` |
  | Bear left/right | ≤ 50° | the finger row runs to the column |
  | Turn left/right | ≤ 135° | ↰/↱: the centre pin climbs, then runs sideways |
  | Turn around | > 135° | the middle columns step from fingers to wrist |
  | Arrived | target within 1 m | two pulses of the middle columns |

  Thresholds favour the previous cue by 5°.
- **Asking for a target:** make the V sign and say one word: "exit", "door", "chair", "person" or "teammate" (also "way out", "doorway", "seat", "someone").
  - Listening starts as soon as the sign is seen, so the word can be said while holding it. If the word isn't in yet when the hold completes, a quiet blip means "listening" and the window stays open for 2.5 s.
  - Recognition is on-device only (`Lantern/Services/KeywordListener.swift`). While the Grok assistant runs, its microphone is borrowed and its uplink muted for the window, so it neither hears nor answers the word.
  - With no word, the target already chosen (Settings or "find a door" to the assistant) is used.
- **Starting:** the target must appear with a route within 3 s.
  - If two or more of that kind are in view, at least 1 m apart, the assistant asks: "I see 2 exits. 1: left, about 3 meters. 2: right, about 5 meters. Which one?" The answer comes back through the `choose_target` tool, and guidance then follows only that one; it never jumps to the other.
  - Without a running assistant, the one most straight ahead is chosen.
- **No speech, only sounds** (`Lantern/Services/Chime.swift`, synthesized in memory):
  - A rising two-note chime when guidance starts, repeats or arrives.
  - A soft falling pair on failure: no word or target, target not seen, no route, target lost, or no answer within 15 s.
  - The quiet listening blip.
  - Later route changes are pins only.
- **When an arrow plays:**
  - On request, then only after a noticeable change that holds for 0.8 s, at least 1.5 s after the last arrow. Slight-turn drifts under two columns are ignored.
  - The sign again replays the current arrow (or switches target if a new word is said).
  - Guidance ends on arrival, or 3 s without the target in view.
- **Override:** an obstacle within 0.9 m holds the arrow back. It restarts if the obstacle clears within 2 s; otherwise it is dropped.
- **Simulation:** **Simulate V sign** plays arrows toward the synthetic target on screen. Simulation still sends nothing to the puck.
- **Limits:** the map covers only what the camera has seen in the current room. Objects under 10 cm, glass, mirrors, dark surfaces and moving people can be missed. A suggested direction, not a safe route.
- **Hardware:** untested on a real hand, phone or puck. Pin return speed decides whether arrows read as motion.

## Deterministic demo and limitations

**Simulation** runs a12-second loop through obstacle bands, a moving synthetic target and a2-second tracking-loss interval. It is conspicuously labeled and never transmits simulated movement to BLE. Stop clears state, sends neutral if a puck is connected, pauses AR and stops peer ranging. Backgrounding the app also stops guidance; the board independently neutralizes on its timeout.

Current integration checks run on macOS. See [V2 main integration](../docs/V2-MAIN-INTEGRATION.md) for executed results. Simulator and unsigned builds do not establish LiDAR/BLE/UWB or physical performance.

## Primary references consulted

- [ARCamera transform and native axes](https://developer.apple.com/documentation/arkit/arcamera/transform)
- [ARKit scene-depth example](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth)
- [Camera intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics)
- [Vision CoreML request](https://developer.apple.com/documentation/vision/vncoremlrequest)
- [Nearby Interaction token exchange](https://developer.apple.com/documentation/nearbyinteraction/discovering-peers-with-multipeer-connectivity)
- [Sharing an AR session with Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction/nisession/setarsession(_:))
- [Nearby-object world transform](https://developer.apple.com/documentation/nearbyinteraction/nisession/worldtransform(for:))
- [NI orientation guidance](https://developer.apple.com/design/human-interface-guidelines/nearby-interactions)
- [Swift compiler driver fallback](https://github.com/swiftlang/swift/blob/main/docs/DebuggingTheCompiler.md)

## V2 spatial memory branch

The isolated V2 branch adds session-only Remember, My Places, Recall, explicit Set
return point / Return, and Stop guidance using production `SpatialMemoryManager`.
The **Memory simulation** scene exercises the same encoder with synthetic pose
controls and no simulated BLE movement. Stopping/resetting/interruption clears
places; transient tracking loss neutralizes guidance and can recover in the same
world. See [SPATIAL-MEMORY.md](../docs/SPATIAL-MEMORY.md) for coordinate conventions,
arrival assumptions, stateful CLI schema, lifecycle rules, and remaining validation.

`FeelCore` includes 20 spatial-memory regression tests. `LanternTests` adds three
coordinator tests and `LanternUITests` adds the explicit simulation flow; these
Apple-target tests require Xcode; current results are recorded in the integration report.

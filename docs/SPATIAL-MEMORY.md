# FEEL V2 spatial memory

V2 is a greenfield extension of the recreated V1 software, developed on the isolated
`feel/v2-spatial-memory` branch. It does not reproduce unavailable original source.
V1 is maintained on `main`; this branch integrates its current `7da10f7` baseline.
The app preserves V1's Geist design and persistent Stop, with My Places below
the tactile view. This feature stores places only in RAM for one
continuous AR session. There is no persistent map, cross-session relocalization,
voice command interface, route planning, or claim of obstacle-free navigation.

## Use

In **Live sensing**, mount the phone in the same fixed native landscape-left
orientation as V1: rear camera forward, top edge to the user's left, phone upright.
Wait for normal tracking and calibrate the floor from measured camera height.

1. Enter a **Place name** and press **Remember** to save the current phone position.
2. Move within the same continuous sensing session.
3. Choose a place in **My Places → Saved place**, then press **Recall**.
4. **Stop guidance** removes the place highlight while obstacle sensing continues.

Remember saves the phone's location; it does not detect or attach a bookmark to an
object. Names are user supplied. Selecting another place stops previous guidance;
Recall activates the chosen place. Rename and Delete operate on the selected place.
Deleting an active place stops its guidance. Remembering a new place selects it and
stops the previous place guidance. Choosing an object finder also stops memory
guidance; Recall/Return switches off the object finder.

**Set return point** explicitly captures the current phone position. **Return**
guides to that point independently of the selected named place. Setting a return
point never happens automatically at app launch. Replacing an active return point
stops its guidance until Return is pressed again. All controls have visible text
and VoiceOver labels; errors remain visible in the My Places panel.

The deterministic **Memory simulation** button works without LiDAR. Name and
Remember the origin, press **Move back 1 m** twice, then Recall. The virtual puck
highlights the centre column and also preserves a synthetic nearby obstacle in
column 3. Turn left/right, move, toggle tracking, and reset the simulated session.
The existing **Simulation** button retains the V1 sweeping-target replay. Both
scenes are explicitly labeled and send no simulated movement to BLE. Entering or
leaving simulation may send the ordinary neutral stop command to a connected puck.

## Coordinate and output contract

`SpatialMemoryManager` in `FeelCore` is used by the app and the stateful replay CLI.
A bookmark is an immutable ID, name, and AR world position. Each sampled pose carries
the identifier of its world-coordinate session, its timestamp, and tracking status.
All app mutations and packet ticks execute on the main queue.

- A pose must have finite values and an orthonormal, right-handed basis. It must
  match the current session, have normal tracking, and be no more than **250 ms**
  old. Future timestamps and invalid mounting orientation are rejected. The fixed
  mount requires `up.y > 0.7` and `abs(right.y) < 0.35`, as in V1.
- The exact inverse camera transform projects the world bookmark into native
  camera coordinates. Bearing is `atan2(local.x, -local.z)`; negative is left.
  Tactile range is `hypot(local.x, local.z)`. These are the same bearing and range
  used by V1 depth and object-target projection. A 20°/40° pitched-camera regression
  checks that one target occupies the same tactile column in all three paths.
- The separate `horizontalDistance` is `hypot(worldDelta.x, worldDelta.z)` in the
  gravity-aligned world plane. UI and CLI distinguish this from tactile range.
  They differ when the camera is pitched or saved/current phone heights differ.
  Neither value is a route length. Keep the prescribed upright forward mount.
- Arrival is **horizontalDistance <= 0.35 m**, with **absolute vertical difference
  <= 0.75 m**, both inclusive. These are prototype assumptions, not measured user
  tolerances. Arrival removes the target highlight and preserves sensed obstacles.
  A larger height difference reports `differentLevel`; it never suggests stairs
  or attempts vertical guidance. The arrival radius is deliberately larger than
  zero to avoid unstable direction at the saved position.
- The seven sectors cover **-45° through +45°**, inclusive. Internal boundaries
  choose the sector to the right, following the existing encoder. A target outside
  this field is `outsideFieldOfView`; a target with nonnegative camera z is `behind`
  (including exactly beside the phone). No angle is clamped into a false edge pin.
- In-field tactile range above **4 m** is `beyondRange`; actual range is retained
  in the response/UI, and no far-band target is fabricated. Offscreen/behind state
  takes precedence over range. Range at exactly 4 m still uses band 4.
- Valid memory targets enter the existing nine-byte `TactileEncoder`. A closer
  obstacle in the highlighted column retains its nearer band. Other obstacle
  columns remain unchanged. Highlight identifies bearing, not a clear route.
- Arrived, offscreen, behind, different-level and beyond-range targets suppress
  the target highlight but preserve obstacle output. Tracking, stale/invalid pose,
  session mismatch, or missing session neutralize the whole memory packet. Floor
  calibration and fresh depth remain required by the V1 encoder. The UI labels
  geometric guidance as paused while that output gate is closed.

The command remains `[seq, b0, b1, b2, b3, b4, b5, b6, hl]`. There is no firmware
protocol change. Nothing in this feature asserts that the physical servos are
working or changes the default disabled physical PWM output.

## Session lifecycle

Every AR run with `.resetTracking` creates a new UUID and announces it before
publishing frames. Frames carry that world ID plus the existing start and finder
epochs. The coordinator rejects queued frames from earlier worlds or selections.

An interruption, explicit stop, app backgrounding, failure, reset, or switch between
live/simulation clears all bookmarks, selection, active guidance and return point.
The same event also stops Nearby Interaction so an old NI world target cannot be
used in a new coordinate frame. Restart requires saving places again, recalibrating
the floor, and explicitly restarting teammate finding if desired.

Ordinary limited tracking or missing depth produces neutral output and keeps the
places/intent. Guidance can resume only with a fresh normally tracked frame in the
same world. Relocalization across an interruption is deliberately disabled, matching
V1's shared-AR Nearby Interaction configuration. A session ID cannot be reused in
one manager lifetime; a failed duplicate begin leaves existing state unchanged.

This policy follows Apple's distinction between a continuous world frame and a
reset/interrupted session; it does not assume a recovered frame has the old origin:
[resetTracking](https://developer.apple.com/documentation/arkit/arsession/runoptions/resettracking),
[sessionShouldAttemptRelocalization](https://developer.apple.com/documentation/arkit/arsessionobserver/sessionshouldattemptrelocalization(_:)),
[tracking state after interruption](https://developer.apple.com/documentation/arkit/artrackingstatereason/artrackingstatereasonrelocalizing).

Names are trimmed, contain 1–40 Swift characters and no control characters, and
must be unique ignoring case/diacritics in this session. IDs contain 1–64 ASCII
letters, digits, `_` or `-` and are unique; `$return` is reserved for active return
guidance. Up to 64 named places are allowed per session. Invalid mutations do not
partially change state. Names/coordinates are never written to disk or sent to a
service by this implementation.

## Stateful CLI

Build using `sh ios/scripts/test_portable.sh`, then run:

```sh
ios/Shared/FeelCore/.build/debug/feel-replay stdio
ios/Shared/FeelCore/.build/debug/feel-replay replay ios/Fixtures/spatial-memory.json
```

Stdio consumes one JSON object per line, immediately emits one JSON response per
line, and keeps one production manager until the process exits. The old `encode`,
`decode`, and `perceive` operations are unchanged. `replay` processes a JSON array
in order and exits nonzero on a failed command or `expectedHex` mismatch.

A full pose is required for capture and guidance:

```json
{"position":[0,0,2],"right":[1,0,0],"up":[0,1,0],"back":[0,0,1]}
```

The four vectors contain exactly three numbers. `position` is camera world
position; `right/up/back` are the columns of its world rotation. Identity looks
along world -Z. For capture/guidance, **context** means `session`, `pose`, `now`,
`frameTimestamp`, and `tracking`. Times use the same monotonic clock in seconds.

| Operation | Required fields beyond `op` | Action |
|---|---|---|
| `memoryBegin` | `session` | Clear old world and begin a fresh unique ID |
| `memoryEnd` | none | Clear and end the current world |
| `memoryState` | none | Read snapshot |
| `memoryRemember` | context, `id`, `name` | Capture current position; select it |
| `memorySelect` | `id` | Select a place and stop active guidance |
| `memoryRename` | `id`, `name` | Rename one place |
| `memoryDelete` | `id` | Remove one place |
| `memoryRecall` | optional `id` | Activate specified or selected place |
| `memorySetReturn` | context | Capture/replace the return point |
| `memoryReturn` | none | Activate the explicit return point |
| `memoryStop` | none | Stop guidance, keeping session places |
| `memoryGuide` | context, `seq`, `distances` | Produce actual nine-byte packet |

`memoryGuide.distances` is seven nullable depth-sector ranges. Optional
`floorCalibrated` defaults to true for synthetic input; the app always supplies
actual calibration state. `seq` must be an integer byte. Callers advance it using
the unchanged sequence contract. Recall/Return set intent; they cannot produce a
packet without a separate fresh valid guidance sample.

Successful memory responses have `valid:true` and a `memory` object with `session`,
`bookmarks:[{id,name,position:{x,y,z}}]`, `selectedID`, `activeID` and `returnPoint`.
Absent optional fields are omitted, not filled with invented coordinates. Active
return uses `activeID:"$return"`.

`memoryGuide` also returns `hex`, `seq`, `bands`, `highlight`, encoder `state`,
`memoryState`, and available `distance`, `horizontalDistance`, `bearingDegrees`,
`targetName`. Encoder `state` is authoritative for tactile validity; memory state
reports destination geometry/pose. Errors return `valid:false,error` and no packet.
Malformed JSON cannot mutate state. No mutation operation sends a packet itself.

Memory states: `idle`, `guiding`, `arrived`, `outsideFieldOfView`, `behind`,
`beyondRange`, `differentLevel`, `trackingLost`, `stalePose`, `invalidPose`,
`sessionMismatch`, `sessionUnavailable`.

## Verification and remaining work

The portable suite includes 20 memory tests alongside the V1 core tests: translations,
90°/180° turns, exact sector/range/arrival boundaries, pitched-camera agreement,
closer obstacles, tracking loss/recovery, invalid/future/stale poses, reflected
bases, atomic mutations, names/IDs, capacity, selection/deletion, explicit Return,
and reset isolation. The CLI fixture checks the actual packet after Remember →
Move → Recall; root integration replays the actual Swift bytes through the firmware
controller. Three additional app coordinator tests and a UI Remember/Move/Recall/
tracking-loss scenario are included for the Apple-platform test target.

Current macOS integration validation, including the full portable suite, spatial
replay, iOS simulator tests and unsigned builds, is recorded in
[V2-MAIN-INTEGRATION.md](V2-MAIN-INTEGRATION.md). Historical Linux/hosted evidence
remains under `docs/evidence/v2/`; it predates this main integration.

Physical work remains: verify phone-to-user alignment and bearing sign, LiDAR/AR
drift over movement, tracking recovery, real BLE timing, real servo output, and
user interpretation of arrival/range/offscreen status. Test in a clear supervised
area using the normal mobility aid; this feature does not compute a safe path.

# FEEL V1 phone ↔ puck contract

This is the **new greenfield contract**, not a recovered original. Handoff facts
are retained; details absent from v7 are explicit implementation decisions below.

## Six-column layout

The app emits b0=0 and never highlights slot0. The raw codec still accepts old
nine-byte frames for compatibility; updated firmware never attaches GPIO32.
The six sectors are [-45,-30), [-30,-15), [-15,0), [0,15), [15,30), [30,45]
degrees. Straight ahead lies on the middle boundary and selects slot4; explicit
straight-arrow cues may use the two middle slots3/4. Angle mapping is unchanged.
See [layout and wiring](SIX-COLUMN-LAYOUT.md).

## BLE and bytes

| Item | Value |
|---|---|
| Service | `7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000` |
| Command characteristic | `7D2A0002-5C6B-4F9A-8E21-0BCE7F0A1000` |
| Status characteristic | `7D2A0003-5C6B-4F9A-8E21-0BCE7F0A1000` |
| Command | Exactly 9 binary bytes, `[sequence, b0,b1,b2,b3,b4,b5,b6, highlight]` |
| Cadence | 10 Hz; the writer must discard old sensor results rather than queue them |
| Bands | `0` down/unknown; `1..4` wrist → fingers |
| Highlight | `0..6` column, `255` none; empty highlighted column is wire-legal, controller suppresses the tap |

Wire slot 0 is reserved and has no physical output. Slots 1–6 are the six columns from user's left to right, with the wrist end toward the user. Verify
this physically before use. BLE identifiers are newly assigned, not known to
interoperate with any previous app. This prototype has no account or cloud path.
The command characteristic accepts writes; status is diagnostic and cannot prove
a pin's position. See firmware README for its exact payload and board selection.

`protocol/vectors.json` contains the normative wire cases. Packet parsing is
atomic: invalid length, band, or highlight rejects the entire packet without
refreshing the watchdog or changing outputs. Legal-value corruption cannot be
detected by this nine-byte format. BLE transport protections are not an
application timestamp, authentication scheme, or end-to-end checksum.

## Sequence, time and lost input

- First packet after connect or timeout establishes a sequence baseline.
- Thereafter modulo-256 deltas `1..127` are accepted. `0` is duplicate; `128..255`
  is old/ambiguous. Neither rejection refreshes the watchdog.
- At **age ≥500 ms** since the last accepted receipt, all requested bands become
  zero, highlight stops and the sequence baseline clears. Disconnect clears
  output immediately. Firmware uses unsigned elapsed arithmetic across millis wrap.
- Reconnection starts neutral and waits for a fresh packet. Old writes must not
  be replayed from a phone-side queue. A delayed otherwise-valid frame can still
  pass: the payload has no sender timestamp or boot/session identity.
- Zero bands mean *no active pin request*. They do **not** distinguish clear space,
  invalid depth, stopped app, lost tracking, timeout, or disconnected phone. The
  phone announces/displays these states separately. Do not read neutral as safety.

## Perception and target choices

New assumptions: fixed landscape-left mount, rear camera facing forward, camera
X right and forward −Z. Six equal sectors in slots 1–6 cover −45° through +45°. Endpoints
are included; an internal boundary goes to the sector on its right. Do not clamp
targets outside that field into an edge column.

| Measured positive distance | Band |
|---|---:|
| `0 < d < 0.9 m` | 1 (below nominal 0.3 m saturates near) |
| `0.9 ≤ d < 1.6 m` | 2 |
| `1.6 ≤ d < 2.5 m` | 3 |
| `2.5 ≤ d ≤ 4.0 m` | 4 |
| Missing, nonfinite, nonpositive, or beyond 4 m | 0 |

Tracking must be normal and depth at most 250 ms old, with no future timestamps.
Target estimates expire after 500 ms. This is a conservative prototype policy,
not a sensor accuracy claim. Floor filtering requires an accepted reference: a stable classified floor or
a manual measured-height override; world origin is not automatically the floor. Low-confidence and
missing depth never establish free space. Target guidance uses the same packet,
retaining nearer obstacle requests; the app explains if the requested target is
unavailable. See `ios/README.md` for detector, floor, and mount conventions.

## Cam commands

FS0307 assumed 175° design (user decision October 17, 2026): band centres `0°, 58°, 116°, 174°`; down gaps `29°, 87°, 145°`. This is not measured travel.
When a pin disappears, command the nearest gap to its previous band (tie to lower
gap), startup 29°. Highlight dips **13° toward that gap** and returns. Firmware
implements a nominal 100 ms dip in a 600 ms cycle; these times are unmeasured
prototype defaults. Calibration offsets apply per column within documented limits.

## Tap rhythms (October 17, 2026)

A pin that stays up stops being felt within seconds; a change is felt at once. So the puck keeps
pins felt by motion:

- Presence tap (new, phone-timed, `ios/Shared/FeelCore/Sources/FeelCore/TapRhythm.swift`): an
  obstacle pin whose band has not changed for 1.0 s drops to its gap for one packet every 1.0 s,
  all steady pins together.
- Target taps (unchanged): one target column is tapped by the firmware highlight (13° toward the
  gap for 100 ms of every 600 ms, gated by the tactile profile), a span by the encoder (every span
  column dropped for one packet in six). Both beat faster than the presence tap, so what points
  at something stands out.
- Arrows (`DirectionCue`) keep their own 100 ms frames and are the fastest motion on the puck.

Servo budget: an FS0307 turns 60° in about 0.10 s unloaded, so the 29° drop to the gap is about
50 ms each way and up to twice that under the cam; a dropped packet is back up within about 200 ms,
and no period may be shorter than three packets. None of this is measured on hardware yet.

Neutral commands remain neutral until a fresh accepted packet raises a band. The nine-byte ABI
does not distinguish a presence-tap drop from tracking loss or Stop, so firmware must never infer
a tap and restore an old band after packet loss. The 500 ms watchdog remains unchanged. A lost
raise packet can extend a tap's neutral interval; this is preferable to resurrecting stale guidance.
See `simulation/scenarios/packet-loss-failsafe.json` and
`simulation/scenarios/tracking-loss-packet-blackout.json`. This revision is not flashed.

A requested angle is not a measured angle. A continuous servo transition between
distant bands necessarily crosses intermediate cam lobes; do not claim no
transient pin activation. There are no position, force, temperature, or jam sensors.
Physical return, timing, force, travel, and mapping must be measured on the crank
rig and one powered column before expanding to seven.

## Bench control

115200 baud, newline-terminated ASCII. Refer to `firmware/README.md` for `ARM`,
`B`, `HL`, `CAL`, and `US`, the bench timeout, save behavior, and output enable.
Never copy raw pulse endpoints into hardware without checking the actual servo.
The controller maps 0–175° to an experimental 650–2500 µs envelope (87.5° → 1575 µs).
Raw commands outside this envelope are rejected; calibration cannot expand it.
These are design values, not measured safe endpoints for an individual servo.
Physical outputs stay disabled until the measured-range opt-in is configured.
Bench use is separate from normal BLE control. V1–V4 continue to send the same nine-byte band-selection packet; the firmware owns the angle mapping. Old 120° calibration records must not be reused.

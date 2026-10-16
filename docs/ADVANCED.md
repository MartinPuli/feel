# FEEL V3 — advanced software

V3 extends the recreated V1 foundation and V2 spatial memory in the isolated
`feel/v3-advanced` branch. These are new source files, not recovered original code.
The nine-byte wire protocol, seven servo columns, and firmware watchdog are unchanged.
Physical speech, AR relocalization, LiDAR, BLE, UWB and tactile usability remain unverified.
See the release report for the latest actual build and test evidence.

## Explicit commands and readback

Open **Voice, saved map and feedback**. Select English or Spanish, then type a command
and choose **Run command**, or choose **Start speaking**, speak one command, and choose
**Finish speaking**. A speech attempt ends after ten seconds; it waits at most three
more seconds for a final result. Partial transcripts only appear on screen. **Cancel
speech**, **Stop**, backgrounding, audio interruption and a new attempt invalidate old
authorization and recognition callbacks before releasing the microphone.

Speech uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition=true`, after explicit
speech and microphone permission. Unsupported or unavailable on-device recognition
reports an error and leaves typed controls usable. There is no server-recognition
fallback, wake word or background listener. Readback uses `AVSpeechSynthesizer` only
after **Read result**; it does not start listening. Input and readback are limited to
160 Unicode scalars, including combining marks. A longer result remains visible but
readback rejects it rather than silently speaking a truncated list of places.

| Action | English | Spanish |
|---|---|---|
| Remember current position | `remember Desk` | `recuerda Mesa` |
| Recall named place | `recall Desk` | `recupera Mesa` |
| Return to explicit return point | `return` | `vuelve` |
| Stop sensing and neutralize | `stop` | `para` |
| List current places | `list places` | `lista lugares` |
| Find a mode | `find barcode` | `busca código` |

English modes: `obstacles`, `door`, `exit`, `chair`, `person`, `teammate`, `barcode`.
Spanish modes: `obstáculos`, `puerta`, `salida`, `silla`, `persona`, `compañero`, `código`.
Keyword case and accents are folded; bookmark names retain their entered spelling.
Names use the V2 limit of 1–40 characters. The parser accepts a complete single command,
not arbitrary conversation: polite prefixes, terminal punctuation, command separators,
line breaks and composite commands are rejected. Ordinary names such as `Bus stop`
remain names. Recognition punctuation insertion is disabled.

Commands use the same coordinator actions as the buttons. They cannot silently start
Live or bypass fresh-pose checks. **Set return point** remains an explicit on-screen
action. A voice `stop` stops all sensing; **Stop guidance** only stops the selected
place. Only explicit typed input and final speech callbacks reach the parser. OCR,
CoreML labels, nearby peer names and QR payloads never enter it.

## One persistent local map

1. Start **Live sensing** on a LiDAR device. Explore the area until ARKit reports an
   extending or mapped world; calibrate the measured camera height. Remember places
   and optionally set a return point.
2. Choose **Save map**. This captures an ARWorldMap and the bookmark snapshot from the
   same continuous world session. It replaces the one previous local saved map.
3. Later, start Live in the same physical area and choose **Load map**. This stops the
   previous session and NI ranging, creates a new session ID and runs ARKit with
   `initialWorldMap`. Move slowly in the previously explored area.
4. Guidance remains neutral until the restore gate observes relocalizing tracking,
   the saved marker anchor, and fresh valid normal tracking for at least 0.5 seconds.
   Any observed invalid tracking/pose/identity or inter-observation gap over 250 ms
   restarts that settling interval. Frame age must be 0–250 ms. A backwards/invalid
   clock or more than 60 seconds elapsed fails closed, even if no more frames arrive.
5. Restored places and the return point become available without an active or selected
   target. Recalibrate the floor, select a place and explicitly choose Recall or Return.
   Fresh normal depth and the normal V1/V2 range/orientation gates still apply.

The marker uses a generated map UUID, a distinct ARAnchor UUID, and the name
`FEEL.map.<map UUID>`. The envelope pairs both identities with the exact secure archive
bytes and bookmark coordinates. The native loader securely unarchives only ARWorldMap
and requires exactly one correctly named marker with the recorded anchor ID. Normal
tracking alone, a marker alone, or possession of saved coordinates cannot activate the
restore. A new Load, Stop, interruption or restart rejects stale asynchronous work.

The archive has schema version 1, at most 64 places, finite coordinates bounded to
±10,000 m on each axis, at most 16 MiB of map bytes and 24 MiB of JSON. Unknown fields,
unsupported versions, invalid IDs, duplicate IDs/names and malformed map data are
rejected before current memory changes. It never persists the selected/active target,
old session ID, floor calibration, audio or camera snapshots. File storage is one
atomic write in Application Support/FEEL/saved-world.json, with complete iOS file
protection and the directory excluded from backup. There is no automatic cloud sync.

**Delete saved map** removes the file. It does not erase places already active in the
current live session; Stop clears those. Save/Load are disabled in Simulation, which
has no real AR map. Stored spatial data may reveal room layout and named locations;
delete it when no longer wanted.

Nearby Interaction camera assistance requires an AR configuration without an initial
world map. Teammate finding is therefore disabled for the entire restored-map session,
including after successful relocalization. Choose **Live sensing** to start a fresh
compatible world; this clears current session places. The saved map file is retained
unless explicitly deleted. No cross-map transform or route planner is implemented.

## Adaptive target tap cadence

Profiles alter only the effective highlight byte. Every sequence number and every
obstacle/target band remains byte-for-byte unchanged. Packets continue at 10 Hz, keeping
the firmware sequence checks and 500 ms watchdog meaningful. Neutral tracking-loss
packets are still neutral. The firmware still produces its existing commanded 100 ms
dip every 600 ms while highlighted; this feature makes no claim about physical force.

| Profile | Command policy |
|---|---|
| Standard | Preserve the valid effective highlight continuously. |
| Reduced | Begin with 1.8 s of highlight 255, then 0.6 s with the target highlighted; repeat every 2.4 s. |
| Automatic | Enter Reduced immediately when any band equals 1; return to Standard only after 2.4 continuous seconds with no band 1. |

Changing session, profile, target column or highlighted band starts a new quiet epoch.
Target loss/reacquisition also restarts quiet. Unrelated column and sequence changes do
not. The app additionally resets on mode changes and explicit bookmark/finder changes,
including two bookmarks occupying the same column. Invalid or backwards time suppresses
the highlight and resets history. Automatic hysteresis prevents near/far flicker from
resetting every packet into a continuous firmware tap. Timing is sampled at packet
cadence, not guaranteed actuator timing. A low-density highlight does not imply the
area is clear; the obstacle bands carry the same estimates as before.

## Additional perception

**QR / barcode** runs Apple's `VNDetectBarcodesRequest` on the same native camera image
orientation as the other Vision finders. Accepted observations require confidence
at least 0.5 and pass their box center through the captured frame's depth/intrinsics and
camera-to-world transform. The target is reprojected against later phone poses and has
the existing 500 ms target expiry. Missing/confidence-poor depth, out-of-field targets,
tracking loss and stale frames suppress direction normally.

Payloads are bounded display-only labels (at most 64 Unicode scalars including `Code:`),
with control/format characters removed and whitespace folded. The app does not open
URLs, execute commands, authenticate codes, or infer a safe path from their contents.
Printed-code detection distance and latency must be measured on the real mounted phone.

Simulator builds select the documented barcode request revision 2 when the runtime
reports it supported; otherwise they retain the framework default. Device builds retain
the default revision. All builds use normal compute selection. The public revision 2
constant is available in the pinned SDK and iOS 16 target, though deprecated in iOS 18.

This policy follows a retained diagnostic on the hosted iOS 26.2 simulator (build 23C54):
supported revisions were 1–4, with default 4. Revisions 1 and 2 decoded the generated
`FEEL test shelf` QR at confidence 1.0 through both CGImage and the same CVPixelBuffer,
with `usesCPUOnly` both false and true. Revisions 3 and 4 returned no observations for
all those combinations; mirrored orientation also did not help revision 4. This isolates
revision-dependent behavior on that runtime, not a general device defect. The failed
production assertion remains in the test; diagnostic successes never substitute for it.
Neither the confidence threshold nor expected payload/bounds were relaxed. The retained
fixture and independent decoder metadata are in `docs/evidence/v3/qr-fixture.png` and
`qr-independent-decode.json`. Camera and printed-code performance still need device tests.

## Portable replay API

`feel-replay stdio` accepts one JSON command per line and immediately returns one JSON
reply. Existing `encode`, `decode`, `perceive` and `memory*` operations are unchanged.
Replies include `valid:false,error` on invalid input. Stateful V3 operations use the
actual production parser, archive/gate and adaptive controller.

| Operation | Required input | Reply additions |
|---|---|---|
| `voiceParse` | `text`, `language`: `en`/`es`, `final` | `intent`: action plus name/mode when relevant |
| `adaptive` | `seq`, seven `bands`, `highlight`, `profile`, `session`, `now` | Actual packet `hex`, `seq`, `bands`, `highlight` |
| `adaptiveReset` | None | Resets cadence history |
| `archiveExport` | `mapID`, `anchorID`, `mapDataBase64` | `archive` containing current bookmarks and return point |
| `archiveImport` | `archive`, new `session`, `now` | Empty `memory`, `restoreState:awaitingRelocalization` |
| `archiveObserve` | `session`, `mapID`, optional `anchorID`, `now`, `frameTimestamp`, `tracking`, `relocalizing`, full `pose` | `memory`, `restoreState` |
| `archiveCancel` | None | Clears gate and memory; `restoreState:idle` |

Map and anchor IDs are distinct UUIDs; session and place IDs use 1–64 ASCII letters,
digits, hyphens or underscores. Pose vectors `position`, `right`, `up`, `back` each have
three numbers, matching the V2 API. `memoryBegin`/`memoryEnd` cancel pending restore.
Ready memory is inactive until a separate `memoryRecall` or `memoryReturn`. Gate states
are `idle`, `awaitingRelocalization`, `ready`, `failed`.

```json
{"op":"voiceParse","text":"recuerda Mesa","language":"es","final":true}
{"op":"adaptive","seq":42,"bands":[1,0,0,3,0,0,0],"highlight":3,"profile":"reduced","session":"demo","now":0}
```

The portable archive intentionally treats AR bytes as opaque fixture data. Its tests
prove bounded validation, identity/timing gates and packet behavior; they do not pretend
to perform ARKit localization. Native tests additionally exercise secure-map rejection,
atomic local storage, command coordination and a real Vision request over a CoreImage
generated QR pixel buffer. Speech lifecycle tests do not start a microphone. UI tests
exercise explicit typed commands in labeled Simulation.

## Validation and remaining physical work

At implementation handoff, the portable package built and all 90 XCTest tests passed
locally; all 29 Swift files passed syntax parsing. Parent cross-layer V3 replay passed
1,441 assertions over 156 firmware states after the long-observation-gap fix. Native
test/build outcomes are recorded separately in the current release report; syntax
parsing on Linux is not an Apple framework build.

Before a real demonstration, test denied/unavailable permissions, offline English and
Spanish final recognition, cancel/background during authorization and recording,
readback without microphone feedback, map save/relaunch/load in the same and a different
room, interruption during capture/restore, marker mismatch, slow tracking recovery,
barcode labels that look like commands, and reduced/automatic commands on calibrated
hardware. Keep the fixed V1/V2 native landscape mount and ordinary mobility aid. No
physical validation result is inferred from these software tests.

## Primary Apple references consulted

- [ARWorldMap secure serialization](https://developer.apple.com/documentation/arkit/arworldmap)
- [Initial world map and relocalizing-to-normal tracking](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/initialworldmap)
- [Saving and loading world data](https://developer.apple.com/documentation/arkit/saving-and-loading-world-data)
- [Nearby Interaction shared AR session requirements](https://developer.apple.com/documentation/nearbyinteraction/nisession/setarsession(_:))
- [On-device speech recognition request](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [Speech recognizer on-device support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Speech punctuation control](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/addspunctuation)
- [Speech synthesis](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [Audio ducking category compatibility](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/duckothers)
- [Vision barcode detection](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest)
- [Vision supported compute stage devices](https://developer.apple.com/documentation/vision/vnrequest/supportedcomputestagedevices)
- [Vision compute device selection](https://developer.apple.com/documentation/vision/vnrequest/setcomputedevice(_:for:))
- [Vision CPU-only execution](https://developer.apple.com/documentation/vision/vnrequest/usescpuonly)
- [Vision barcode revision 2](https://developer.apple.com/documentation/vision/vndetectbarcodesrequestrevision2)
- [Vision request revision](https://developer.apple.com/documentation/vision/vnrequest/revision)

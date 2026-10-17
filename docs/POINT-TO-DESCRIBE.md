# Point-to-describe and target spans

Two additions to the Lantern app. Neither changes the firmware or the 9-byte protocol. **Neither has run on a real iPhone, puck or hand yet.**

## Target spans

A detected door, chair or person now covers every column its detection box spans, not just the column at its centre.

- The app measures the box's edges at the target's depth and stores the width in metres, so the span stays correct as you walk closer or farther.
- A neighbouring column joins the span only if the target covers at least 3° of it.
- **One column:** unchanged. The firmware taps it.
- **Several columns:** the phone taps them together. All span columns drop for one packet in every six (100 ms down every 600 ms, the same rhythm as the firmware tap).
- A closer obstacle in a span column still wins, as before.
- The on-screen puck rings every span column. VoiceOver reads "Target columns 3 to 5".

## Point-to-describe

The user asks about a pin without speaking:

1. Hold the puck's back toward the phone, palm toward the camera, thumb up. Either hand works.
2. After half a second the phone says "Pointing". The pins now **freeze** on the scene from just before the hand came up.
3. Point at a cell with the other hand's taped fingertip and hold still for 0.4 s. The phone describes that cell, for example "Slightly left: Possible door, 2.1 meters. Nearest reading 1.2 meters."
4. Move to another cell to hear about it. Lower the puck to return to live sensing.

**Rules:**
- The frozen scene expires 3 s after it was captured.
- It is refused if the phone turned more than 10° since then, or lost tracking for more than a second.
- An empty column is never called clear: the phone says "Nothing measured within 4 meters. Not confirmed clear."
- Speech is local (VoiceOver if it's running, otherwise the phone's own voice), so it isn't throttled like the assistant's announcements.

### Setup

1. **Print the back sheet.** [cad/production/markers/puck-back.svg](../cad/production/markers/puck-back.svg) holds four copies on US Letter. Print at 100% / Actual size and check the 50 mm bar.
2. **Cut on the dashed line and stick it on the chassis bottom, printed side out.**
   - The codes go at the wrist end (the cable-slot end); the rounded corners go at the finger end.
   - The bare strip left at the wrist end keeps the zip-tie slots clear.
   - Four loops of tape under the corners are enough.
   - The sheet fits only the production chassis in CAD.md.
3. **Tape the pointing fingertip** with black, blue or green tape. Red, orange and yellow look too much like skin to be detected.
   - Without tape, the app falls back to Apple's hand tracking, which is less accurate.

The earlier four-corner sticker sheet is gone: its finger-end stickers would have covered pin cells.

### Accuracy test (do this before demoing)

In Live mode, the line under the status shows what the detector sees, for example `Pointing: codes 3/3 · ready · tip 24, 41 mm · C1 B3 · tape · pins frozen`. Each printed cell is labelled with the same name.

1. Point at each of about five cells 20 times (corners and centre).
2. Count how often the readout names the cell you touched. Write down the lighting and how far the puck was from the phone.
3. If columns are reliable but bands aren't, have the description lean on the column.

### Tunables

All of these live in [`Pointing.swift`](../ios/Shared/FeelCore/Sources/FeelCore/Pointing.swift):

| What | Where | Default |
|---|---|---|
| How long the pose must be held | `PointingController.armSeconds` | 0.5 s |
| How long to hold still on a cell | `PointingController.dwellSeconds` | 0.4 s |
| How old the frozen scene can get | `PointingController.maxReferenceAge` | 3 s |
| Allowed turn since the scene | `PointingController.maxHeadingChangeDegrees` | 10° |
| Allowed tilt | `PointingGate.maxSideRatio` | 1.3 |
| Allowed rotation from thumb-up | `PointingGate.rotationToleranceDegrees` | 35° |
| Minimum size in the image (about 50 cm away) | `PointingGate.minWidthFraction` | 0.12 |
| Accepted fingertip blob size | `FingertipMarker.minArea` / `maxArea` | 20 / 900 mm² |

The layout numbers in `PuckBackLayout` and in [`make_back_sheet.py`](../cad/production/markers/make_back_sheet.py) must change together.

### What has been verified (Oct 17 2026, on the Mac and in the simulator)

| Check | Result |
|---|---|
| FeelCore unit tests (`swift test`): homography, layout, gate, marker colours, cache, state machine, descriptions, spans | 89 / 89 pass |
| The real detector on 11 synthetic camera frames (`ios/scripts/pointing_harness.sh`, Mac Vision) | 11 / 11 pass; fingertip within 0.5 mm of the cell centre. Covers both hands, black and blue tape, one code visible, and ARKit's YCbCr buffer format |
| The printed sheet (rendered SVG) read by Vision and fitted with the app's own layout | 12 / 12 codes decode; printed geometry within 0.6 mm of the layout |
| App build and unit tests on the iPhone 17 Pro simulator | Pass. The detector test is skipped there because the simulator can't run Vision's barcode reader; the Mac harness covers it |
| A real iPhone, real print, real hand, real lighting | **Not run** |

**Unknowns that only a device test can settle:**
- whether ARKit keeps tracking with the puck held about 35 cm from the lens (if it doesn't, every request is refused as "tracking lost");
- whether a blind user can find the pose without help;
- whether the 3 s window is long enough in practice;
- how shadows and glare affect tape detection;
- how the phone's speech mixes with the assistant's.

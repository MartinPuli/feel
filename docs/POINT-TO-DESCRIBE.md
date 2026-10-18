# Point-to-describe and target spans

Two additions to the Lantern app. Neither changes the firmware or the 9-byte protocol. **Neither has run on a real iPhone, puck or hand yet.**

## Target spans

A detected door, chair or person now covers every column its detection box spans, not just the column at its centre.

- The app measures the box's edges at the target's depth and stores the width in metres, so the span stays correct as you walk closer or farther.
- A neighbouring column joins the span only if the target covers at least 3° of it.
- **One column:** unchanged. The firmware taps it.
- **Several columns:** the phone taps them together. All span columns drop for one packet in every six (100 ms down every 600 ms, the same rhythm as the firmware tap).
- **Steady obstacle pins** drop for one packet every second once they have stayed the same for a second (FeelCore `TapRhythm`), so they stay felt; target columns keep the faster taps above.
- A closer obstacle in a span column still wins, as before.
- The on-screen puck rings every span column. VoiceOver reads "Target columns 3 to 5".

## Point-to-describe

The user asks about a pin without speaking:

1. Hold the puck's back toward the phone, palm toward the camera, thumb up. Either hand works.
2. After half a second the phone says "Pointing". The pins now **freeze** on the scene from just before the hand came up.
3. Point at a cell with the other hand's taped fingertip and hold still for 0.4 s. The phone says one thing: the target's name if it's in that cell ("Possible door.", "Chair.", "Person."), "Obstacle." if only a depth reading is there, or "Nothing measured." A longer form with direction and distances exists in code (`PointingDescriber.describeDetailed`) but isn't used.
4. Move to another cell to hear about it. Lower the puck to return to live sensing.

### Two fingers: ask for a route

Lay two taped fingers **along one column** (wrist to fingers) and hold for 0.6 s. The phone sets a route goal in that direction and says so, for example "Route set to possible door, left, 2.5 meters. Lower the puck to start." When you lower the puck, the direction arrows guide you there, with a success chime when they start.

- **Where the route goes:**
  - If the selected target was in that column, the route goes to the target.
  - Otherwise it goes in that column's direction and stops 0.5 m short of the obstacle reading.
- **Too close to route to:** if the goal would be inside the guide's 1 m arrival distance (plus 0.3 m), there's no route and no speech. The phone plays a chime, and when you lower the puck it taps that column for 3 s. If the live pin there is down, it raises the cached band so the tap can be felt. The tap gives way to direction arrows and to any band-1 obstacle in another column.
- **When the phone refuses:**
  - Nothing measured in that column: "Pick a column with a raised pin". It won't route into the unknown.
  - Arrows are turned off in settings.
- The goal is a fixed point in the room, saved with where the phone was facing. It stays right after you turn or walk.
- **Guidance ends when:**
  - you arrive within 1 m;
  - routes stop for 3 s;
  - no route is found within 2 s of lowering the puck (failure tone);
  - a V-sign request starts.
- **Fingers across the grid don't count.** Two fingers side by side span about 1.5 columns, so they give no column. The readout says "lay them along one column".
- **Hand-tracking fallback is one finger only.** Two fingers need tape.

**Rules:**
- The frozen scene expires 3 s after it was captured.
- It is refused if the phone turned more than 10° since then, or lost tracking for more than a second.
- An empty column is never called clear: the phone says "Nothing measured."
- Speech is local (VoiceOver if it's running, otherwise the phone's own voice), so it isn't throttled like the assistant's announcements.

### Setup

1. **Print the back sheet.** [cad/production/markers/puck-back.svg](../cad/production/markers/puck-back.svg) holds four copies on US Letter. Print at 100% / Actual size and check the 50 mm bar.
2. **Cut on the dashed line and stick it on the chassis bottom, printed side out.**
   - The codes go at the wrist end (the cable-slot end); the rounded corners go at the finger end.
   - The bare strip left at the wrist end keeps the zip-tie slots clear.
   - Four loops of tape under the corners are enough.
   - The sheet fits only the production chassis in docs/CAD.md.
3. **Tape the pointing fingertips** with a short band (about 1 cm) of black, blue or green tape. Red, orange and yellow look too much like skin to be detected.
   - **Use black on the index finger and blue on the middle finger.** Different colours stay apart even when the fingers touch.
   - Two same-colour bands pressed together are split by the blob's length. Don't wrap tape lengthwise along a finger, or one finger can look like two.
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
| How long two fingers must hold a column | `PointingController.twoFingerSeconds` | 0.6 s |
| Two separate tips count as a pair at | `FingerCounter.pairDistance` | 8–40 mm |
| Merged same-colour blob counts as two at | `FingerCounter.mergedMinLength` / `mergedMinAspect` | 22 mm / 1.6 |
| Sideways offset allowed for "along a column" | `PointingObservation.columnAlignment` | 7 mm |
| Route stops short of an obstacle by | `PointingRouter.standOff` | 0.5 m |

The layout numbers in `PuckBackLayout` and in [`make_back_sheet.py`](../cad/production/markers/make_back_sheet.py) must change together.

### What has been verified (Oct 17 2026, on the Mac and in the simulator)

| Check | Result |
|---|---|
| FeelCore unit tests (`swift test`), including finger counting, column choice, route goals and refusals | 148 / 148 pass (all FeelCore, including the direction-arrow tests) |
| The real detector on 15 synthetic camera frames (`ios/scripts/pointing_harness.sh`, Mac Vision) | 15 / 15 pass; one fingertip within 0.5 mm of the cell centre. Covers both hands, black and blue tape, one code visible, ARKit's YCbCr buffer format, black + blue fingers, two black fingers apart and pressed together, and fingers straddling columns (correctly no column) |
| The printed sheet (rendered SVG) read by Vision and fitted with the app's own layout | 12 / 12 codes decode; printed geometry within 0.6 mm of the layout |
| App build and unit tests on the iPhone 17 Pro simulator | Pass. The detector test is skipped there because the simulator can't run Vision's barcode reader; the Mac harness covers it |
| A real iPhone, real print, real hand, real lighting | **Not run** |

**Unknowns that only a device test can settle:**
- whether ARKit keeps tracking with the puck held about 35 cm from the lens (if it doesn't, every request is refused as "tracking lost");
- whether a blind user can find the pose without help;
- whether the 3 s window is long enough in practice;
- how shadows and glare affect tape detection;
- how the phone's speech mixes with the assistant's;
- whether a blind user can lay two fingers along a column by feel;
- whether the route planner's floor map, built from what the camera has seen so far, reaches far enough for a route started 3 s after the scene.

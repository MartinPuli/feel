# Grid walk: test the guidance without a puck

Can someone move through a space using only the 7 × 4 grid? Grid walk shows the commanded pins full screen with no camera image, records every walk, and puts the walk on `/replay` next to the camera footage.

## Setup (about 10 minutes)

1. **Install the current Lantern build** on the LiDAR iPhone from Xcode (signed). Builds older than this change have no Grid walk or Record controls.
2. **Pick the space**: a hallway or room with a few chairs or boxes, no stairs, no glass walls, and nothing at head height you can't see. A **spotter** walks beside the tester, one hand ready. This is a supervised indoor test, not mobility guidance.
3. **Hold the phone** in landscape with the top edge to your left, upright, at chest height, rear camera facing forward. Measure the lens height from the floor and set it in Settings → Floor calibration.
4. Open **Grid walk** (the grid button in the top bar). Stand still and tap **Calibrate floor** when asked.
5. Optional: Settings → Record for replay → **Include camera video** (on by default). Trials record automatically either way.

## Running a trial

1. Choose a start and a goal (for example, the far door). The tester looks **only at the screen**. A cap brim or holding the phone close to the face blocks the rest of the view.
2. Tap **Start trial** on the right rail. The timer starts and depth and camera recording begin.
3. Walk slowly. Reading the grid:
   - Columns run left to right (L3 … C … R3). Rows run from **near** at the bottom (under 0.9 m, orange) to **far** at the top (2.5–4 m).
   - A blue ring means the chosen target is in that column.
   - A grey **NO GUIDANCE** screen means tracking or depth dropped: **stop** until the grid returns. All pins down does not mean the way is clear.
4. Tap **Bump** (left rail) on any contact, **Unsure** when hesitating, **Arrived** (right rail) at the goal, or **End** to abandon the trial.
5. Repeat the same course a few times, and once with the camera preview visible as a baseline.

## Reviewing and making videos

1. Copy the walk's files off the phone (`.feelrec`, `.mp4`, `.video.json`, `.events.json`) into `simulation/recordings/`, either through Files › On My iPhone › FEEL › Recordings or with `xcrun devicectl … copy from` (see [simulation/README.md](../simulation/README.md)).
2. Run `python3 simulation/run.py`. New walks appear automatically as `UNLABELLED` sessions.
3. Run `cd web && npm run dev`, then open http://127.0.0.1:3000/replay. Choose the walk.
   - Bumps and arrivals are marked on the timeline.
   - **Show 2 s before** jumps to what the grid showed right before each bump.
4. **Export video** records a 1920 × 1080 MP4 of the replay: camera on the left, pin grid over LiDAR on the right, timeline below. It records in real time, so keep the tab visible until it finishes.
5. For a live, on-phone clip, use iOS Screen Recording (Control Center) while in Grid walk. To show the grid and the room together on one phone, use the normal camera view with the drawer open.

## What it does and does not show

- It shows whether the **commanded grid** is enough to move through a space, plus the timing, flicker and dropouts a tester actually experiences.
- It does not show what the **pins feel like**. Reading a screen is faster and more precise than reading 28 pins with a palm; the bench feel test is still needed.
- Known limits from the simulator still apply:
  - Doorways under a 2.03 m door head read as blocked.
  - The outer columns see only a 1.4° sliver of the camera image.
  - A single stray LiDAR pixel can raise a pin.

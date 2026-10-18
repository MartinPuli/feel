# FEEL website

Static site with no dependencies. `/replay` plays back a session:
- **Left:** the camera recording. This is the iPhone's video for phone recordings, or a rendered view for simulated scenes.
- **Right, stacked:** the 6 × 4 physical pin grid the firmware commanded, above the LiDAR depth frame that drove it. Wire slot 0 is reserved.
- **Below:** a timeline of every column against the labels.

Choose any session, simulated or recorded, from the menu. `?session=<name>` links straight to one. Under the recording, a **top view** plots the LiDAR points from above with the six physical column sectors (simulated sessions also outline the true objects). At each labelled moment, the pin grid shows expected pins and pink-rings any mismatch; the table names the exact physical column, wire slot, expected band, and actual band. Grid-walk trial marks (bump, unsure, arrived) appear on the timeline. **Export video** records a 1920 × 1080 MP4 of the replay for demo videos. See [docs/GRID-WALK.md](../docs/GRID-WALK.md) for live field tests.

```sh
python3 simulation/run.py     # scores every scenario and writes the replay data to simulation/out/web
python3 simulation/unit_tests.py # runs Swift tests and writes their summary for /replay
python3 simulation/pin_diagnostics.py # checks each active pin's app packet and firmware command path
cd web && npm run dev         # http://127.0.0.1:3000/replay
npm test                      # server path containment and byte-range tests
```

The dev server binds 127.0.0.1 only. It serves `public/` and maps `/replay/data/*` to `simulation/out/web/`, with byte ranges so video can seek. Space plays and pauses; the arrow keys step one 10 Hz tick.

## Phone sessions

In Lantern, turn on **Record depth**. **Include camera video** is on by default. The phone writes three files to Files › On My iPhone › FEEL › Recordings:
- `feel-<time>.feelrec`
- `feel-<time>.mp4` (960 × 720 H.264, 15 fps, no audio)
- `feel-<time>.video.json`, which ties video time 0 to the ARKit clock

Trials started in **Grid walk** also write `feel-<time>.events.json`. Copy them all into `simulation/recordings/` and run `simulation/run.py`. New walks appear automatically as `UNLABELLED` sessions; add a scenario in `simulation/scenarios/` to label one.

## Deploying

`npm run build` writes `dist/`: the site plus every **simulated** session. **Phone recordings are left out** unless their scenario sets `"publish": true`, because the camera video shows real places and people. The build prints how many it withheld.

The replay data is generated on this machine (Vercel can't run the Swift and C++ replay), so deploy the built folder from here rather than from Git:

```sh
cd web && npm run build && vercel deploy        # preview; add --prod for production
```

`vercel.json` serves `dist/` with no install or build step, with clean URLs and short caching on replay data. Set the Vercel project's root directory to `web`. This deploy path has not been run yet. Check the first preview before promoting it. If the site gets a different home later, `dist/` is plain static files and can be hosted anywhere.

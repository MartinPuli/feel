# FEEL website

Static site with no dependencies. `/replay` plays back a session:
- **Left:** the camera recording. This is the iPhone's video for phone recordings, or a rendered view for simulated scenes.
- **Right, stacked:** the 7 × 4 pin grid the firmware commanded, above the LiDAR depth frame that drove it.
- **Below:** a timeline of every column against the labels.

Choose any session, simulated or recorded, from the menu. `?session=<name>` links straight to one.

```sh
python3 simulation/run.py     # scores every scenario and writes the replay data to simulation/out/web
cd web && npm run dev         # http://127.0.0.1:3000/replay
npm test                      # server path containment and byte-range tests
```

The dev server binds 127.0.0.1 only. It serves `public/` and maps `/replay/data/*` to `simulation/out/web/`, with byte ranges so video can seek. Space plays and pauses; the arrow keys step one 10 Hz tick.

## Phone sessions

In Lantern, turn on **Record depth**. **Include camera video** is on by default. The phone writes three files to Files › On My iPhone › FEEL › Recordings:
- `feel-<time>.feelrec`
- `feel-<time>.mp4` (960 × 720 H.264, 15 fps, no audio)
- `feel-<time>.video.json`, which ties video time 0 to the ARKit clock

Copy all three into `simulation/recordings/` (see [simulation/README.md](../simulation/README.md)). Add a scenario that points at the `.feelrec`, then run `simulation/run.py`. The page finds the video beside the recording automatically.

## Deploying

`npm run build` writes `dist/`: the site plus every **simulated** session. **Phone recordings are left out** unless their scenario sets `"publish": true`, because the camera video shows real places and people. The build prints how many it withheld.

The replay data is generated on this machine (Vercel can't run the Swift and C++ replay), so deploy the built folder from here rather than from Git:

```sh
cd web && npm run build && vercel deploy        # preview; add --prod for production
```

`vercel.json` serves `dist/` with no install or build step, with clean URLs and short caching on replay data. Set the Vercel project's root directory to `web`. This deploy path has not been run yet. Check the first preview before promoting it. If the site gets a different home later, `dist/` is plain static files and can be hosted anywhere.

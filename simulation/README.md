# Replay harness: score the pin grid against labelled depth over time

Feeds the same depth recordings through the production pipeline again and again, then checks what the pins were commanded to do against labels you wrote:

```
.feelrec frames ──► DepthFrameProcessor (FeelCore, same code as the app)
                ──► LanternModel's 10 Hz tick → TactileEncoder → 9-byte packet   (feel-replay session)
                ──► production C++ controller: decoder, watchdog, tap            (firmware/build/feel-sim)
                ──► score against labelled windows → timeline, summary, report.html
```

```sh
python3 simulation/run.py                    # build, run every scenario, write simulation/out/report.html
python3 simulation/run.py --repeat 3         # also require identical output on every run
python3 simulation/run.py --watch            # rebuild and rerun whenever code, scenarios or recordings change
python3 simulation/run.py --update-baselines # accept the current timelines as the regression baseline
python3 simulation/run.py simulation/scenarios/find-door.json   # one scenario
```

Then `cd web && npm run dev` and open http://127.0.0.1:3000/replay. Choose any session, simulated or recorded, and watch the camera recording beside the commanded pin grid and the LiDAR depth, all in sync (see [web/README.md](../web/README.md)). `--no-web` skips writing that data. The standalone `simulation/out/report.html` still works offline: it has the same heatmap and scrubber, without the camera view.

Exit status is non-zero if a scenario fails or output is nondeterministic. Scenarios with `knownIssue` report `KNOWN` instead of failing. A changed baseline is reported, not failed. Reserved wire slot b0 must remain zero and cannot be highlighted in either phone or firmware output; this invariant fails the run even for a known or unlabelled scenario. The retained baselines predate the six-column label migration and have not been overwritten. See [six-column validation](SIX-COLUMN-VALIDATION.md).

The Swift tests are in `ios/Shared/FeelCore/Tests/FeelSimTests`. They need full Xcode for XCTest: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## What is and is not modelled

| Real | Modelled or absent |
|---|---|
| Depth step, encoder, packet bytes, sequence numbers, staleness and tracking gates | Tick timing: 10 Hz, first tick 50 ms after the first frame, frames usable 20 ms after capture |
| Firmware decoder, 500 ms watchdog, effective highlight and tap | Servo motion, torque, friction, power sag, and how it **feels** |
| Recorded detections (from the phone) are replayed exactly | The detector is never re-run. Synthetic detections use ARPerception's cadence (≥ 0.35 s, one in flight) with a configurable latency |
| | Point-to-describe freezing, direction arrows, teammate (UWB) targets, BLE radio |

Synthetic scenes are ideal geometry: a floor at y = 0, boxes and vertical cylinders, iPhone wide-camera intrinsics (±33.5° horizontal view), and optional Gaussian noise and random outliers. They are not a model of real LiDAR behaviour on glass, black surfaces or edges. That is what phone recordings are for.

## Record a real walk on the iPhone

1. In Lantern, open the live controls and turn on **Record for replay → Record depth**. Recording stops when sensing stops. It saves depth, confidence, pose, floor height and the cached detection. **Include camera video** (on by default) also writes an H.264 `.mp4` and a `.video.json` timing file for the `/replay` page. Together that's about 3 MB/s, and the depth recording is capped at 1.5 GB (about ten minutes). Nothing leaves the phone until you share it.
2. Walk the course. Note roughly when things happen (for example "door on the right at about 6 s"), or film the walk on a second phone for labelling.
3. Copy the files off the phone (all three per session: `.feelrec`, `.mp4`, `.video.json`), either from **Files → On My iPhone → FEEL → Recordings** (AirDrop to the Mac) or with:
   ```sh
   xcrun devicectl device copy from --device <name|udid> --domain-type appDataContainer \
     --domain-identifier org.feel.hackharvard.lantern --source Documents/Recordings --destination simulation/recordings
   ```
   Everything in `simulation/recordings/` except this README is git-ignored. Do not commit personal sensor recordings or camera video.
4. Run once with no labels and watch it on `/replay`, then write labels in seconds from the start of the recording (the page's clock):
   ```json
   {
     "title": "Hallway to room 101",
     "recording": "../recordings/feel-2026-10-17T15-02-11Z.feelrec",
     "expect": [
       {"from": 4.0, "to": 6.5, "columns": [5, 6], "bands": [2, 3], "label": "doorframe on the right"},
       {"from": 8.0, "to": 9.0, "columns": "all", "band": 0, "label": "open lobby"},
       {"from": 6.0, "to": 7.5, "highlight": 5, "label": "door taps column 5"}
     ],
     "pass": {"minAccuracy": 0.9}
   }
   ```
   Save it in `simulation/scenarios/`. A scenario whose recording is missing is skipped, not failed.

## Scenario format

- `scene` (synthetic) or `recording` (a path relative to the scenario file).
  - Scene fields: `duration`, `path` keyframes `{t, x, z, yaw}` (yaw 0 faces −z, positive turns right), `cameraHeight` (default 1.2), `pitch`, `objects` (`box` with `min`/`max`, or `cylinder` with `center` [x, z], `radius`, `height`; optional `velocity` [vx, vz], `from`, `to`), `target` (`position`, `label`, `halfWidth`, `from`, `to`, `period`, `latency`), `sensor` (`noise`, `outlierRate`, `outlierConfidence`, `seed`), `trackingLost` and `frameGaps` (`[[from, to]]`), `floorCalibrated`.
- `expect`: windows `{from, to}` with any of the following:
  - `columns` (unique wire slots 1–6, or `"all"` for all six physical columns; b0 is reserved) plus `band` or `bands` (allowed values; 0 means the pin is down). A one-tick drop between two ticks of the same raised band is a tap (the phone's `TapRhythm` drops steady pins once a second; the encoder drops a target span once per six packets) and satisfies the check; on the firmware side a tap held only by lost packets counts too.
  - `taps`: `{"column", "min", "max"}`, taps per second of that column across the window. `tapsPerColumnSecond` is reported per scenario, and taps do not count as flicker.
  - `highlight` (a column, or `null` for none)
  - `state` (the phone's guidance state)
  - `source: "phone"` checks the packet the phone sent instead of what the firmware applied
  - `grace` skips the first seconds of the window
- `faults.packetLoss`: `[{from, to, rate}]` with `faults.seed`. A dropped packet becomes a firmware `TICK`, so the watchdog runs.
- `replay`: `tickOffset`, `latency`, `tail` (seconds).
- `pass`: `minAccuracy` (default 0.95, applied to **every** window on its own) and optional `maxFlicker`.
- `knownIssue`: text. A perception expectation failure is then reported as `KNOWN` and does not fail the run. Reserved-slot violations always fail.

The synthetic labels were derived from geometry before running, not fitted to the output. For a wall at distance D, a column's range is D divided by the cosine of its innermost bearing. Each window leaves out ±0.35 s around every predicted transition.

## Metrics

- **Label agreement**: share of (tick × column) checks inside labelled windows that match.
- **Phantom / missed**: checks where a labelled-clear column showed a pin, or a labelled obstacle column showed none.
- **Live band changes per column per second**: flicker between consecutive live ticks. Going neutral on a fault does not count.
- **Modelled frame age**: how old the depth frame behind each live command was. This follows from the simulated tick phase; it is not a phone measurement.
- **Deterministic / baseline**: identical output across `--repeat` runs, and a diff against `simulation/baselines/`.

## Findings from the shipped synthetic scenarios (October 17)

These are software findings on idealised scenes. None of them has been confirmed on the phone.

1. **Narrow doorways read as blocked.** A 1 m opening at 2 m spans ±14°, narrower than the central two 15° sectors; each sector includes a jamb. The original scene remains a known limitation (`doorway-open`), while a separate 1.2 m opening passes (`doorway-wide-open`). **Lintels also count as obstacles.** The obstacle height window is 0.6–2.1 m. A standard 2.03 m door head is inside it, so the centre of an open door shows band 3 at 2 m (`doorway-with-lintel`).
2. **The tap can drop out when detection is slow.** A detection counts for 0.5 s. A new one starts at most every ~0.4 s at 10 Hz. With 0.2 s inference, the tap misses about a quarter of ticks (`find-door-slow-detector`); with 0.1 s it is steady (`find-door`).
3. **One stray pixel raises a pin.** Each column takes the single nearest medium- or high-confidence sample. At an outlier rate of 2 in 10,000 pixels, an empty room flickers at about 1.56 changes per physical column per second (`lidar-outliers`).
4. **The outer columns are nearly blind.** The camera sees ±33.5° but wire slots 1 and 6 span 30–45°, so they see only about a 3.5° sliver. A person beyond about 1.4 m to the side at 1.5 m distance is invisible (`person-crossing`).

## Pin command diagnostics

`python3 simulation/pin_diagnostics.py` runs all 24 physical slot/band combinations through the production Swift encoder and C++ controller. It checks packet bytes, decoded bands, configured angles and pulses; the JSON explicitly marks physical movement unverified. `python3 simulation/unit_tests.py` runs FeelCore XCTest and these diagnostics, then exports both reports for `/replay`. These additive tools were integrated from `replay-pin-diagnostics` (`6d41c62`); their angle expectations match the current controller configuration and do not change it.

Run scorer boundary tests with `python3 -m unittest discover -s simulation/tests -v`.

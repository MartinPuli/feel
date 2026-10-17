> Historical team planning notes, preserved from main. Hardware and implementation
> claims below are not release-test evidence. For the current V1, use
> [release status](docs/RELEASE-STATUS.md) and [test instructions](docs/TEST-V1.md).

# Pin Puck — HANDOFF (full project state, Fri Oct 16 2026, ~5 PM)

## 1. One paragraph

Pin Puck is a HackHarvard 2026 (Fri Oct 16 – Sun Oct 18, Devpost due Sun 8 AM) build: a palm-held tactile display for blind travellers that shows obstacles between waist and head height. An iPhone 14 Pro on the chest scans with LiDAR; a 7-column × 4-row array of pins in the palm shows direction (column) and distance (row, wrist = near, fingers = far). One pin per column is up at a time. A found target (door, EXIT sign, a friend's phone via UWB) makes its pin tap. Each column is one FEETECH FS0307 micro servo turning a printed camshaft; foam strips are the return springs. Electronics live in a forearm pack. Everything is 3D-printed PLA plus ~$60 of parts.

## 2. People and places

| Who | Role | Where |
|---|---|---|
| Ethan Chen (product, iOS app, CAD owner via Claude) | decisions, testing, this repo | Brown, Providence → Harvard Fri 4 PM |
| Martín | mechanics, assembly, Micro Center run | Cambridge |
| Benjamin | firmware, electronics | Cambridge |
| Isabella | printing the full puck | MIT makerspace, **Prusa MK4S** (250 × 210 bed) |

Venue closes overnight. Micro Center Cambridge opens 10 AM. Perkins School / Carroll Center for blind-user testing if any time appears (there won't be).

## 3. Where things stand right now

**Mechanics**
- Test column v1 (): proved the cam/pin mechanism moves and holds, but a 2.0 mm stroke under the palm was **not identifiable**, fingertips felt "a bit of pressure". Stroke was also ~1 mm short from shaft sag.
- Test column v2 (): new stroke, real servo. Assembled this afternoon with a **glued** servo-to-shaft joint (see §6) because the horn pocket was unassemblable (bug, now fixed in files). Pin stack goes on tonight; servo-driven Gate 1 test tonight at Harvard once the ESP32 exists.
- Full puck: **Isabella is printing** from `stl/pinpuck-for-mit.zip` (7 STLs + `docs/ISABELLA-PRINT.md`, three plates, ~11 h). 
- Foam: Ethan is cutting 21 + spares strips of 2 mm EVA, 11 × 49 mm, 4 holes at 13 mm pitch, holes by heat.

**Firmware** (`firmware/`): complete and host-tested, not yet run on hardware (no ESP32 until Micro Center today). PlatformIO or `firmware.ino`.

**iOS** (`ios/`): Lantern app (LiDAR radar, column mapping, BLE link, highlight detection via CoreML yolov8n-oiv7 + Vision text for "EXIT", NearbyInteraction for the Beacon companion). Builds in Xcode via XcodeGen `project.yml`. Not yet tested against a real puck.

**Electronics**: Martín's Micro Center haul (Oct 16): 2 × ESP32-WROOM USB-C boards (not C3/S3), USB-C cable, 3 × 400-pt breadboards, perfboards + male headers, multimeter, Hakko flush cutters, Weller 30 W iron, 10 × 25 V 1000 µF caps, CA gel, 8 × barrel-to-screw adapters, drill bit set (check 11/64" and 13/64"), optional 5 V 4 A supply, buttons. **Still needed:** ~120 M-M jumpers, USB-A → 5.5 × 2.1 barrel cable (or bare-end USB-A cable), USB-A → C cable as backup, M3 × 8 / M3 × 12 screws (hardware store; #4 × 1/2" sheet-metal screws also work).

**Repo**: 65 uncommitted paths on top of one commit `d98f128 base`. Nothing has been committed since; commit before handing over.

## 4. The design, numbers that matter (all in `cad/params.scad`)

**Layout**: 7 columns × 12 mm pitch, 4 rows × 13 mm pitch, row 0 (band 1, wrist) at y = 14.5 from the servo horn plane. Puck 88.5 wide × 92.5 long × ~31 tall. Face is a 3 mm spherical crown; pins are cut to length so each sits 0.5 mm proud of the local surface at rest. No knuckle scallops, no ridges (tested, rejected).

**Cam** (`cad/tools/cam_sim.py 2.6 2.85 5 24 0.5 25`): base r 2.6, lift 2.85, flat ±5°, cosine ramp 24°, **stroke 2.55 mm**, foot clearance 0.3, pin foot = 25° cone with 0.5 mm tip. Bands at **0 / 58 / 117 / 175°**, all-down null gaps at 29 / 87.5 / 146°. Park at gap 3–4 (146°). Tap = dip 20° toward the home gap. Hold window ±7°, null rise 0.06 mm, neighbour lift during tap 0, pressure angle 66°. Max cam radius 5.45 → 1.1 mm between neighbouring cams.

**Pin stack (z, from the palm surface down)**: face plate 4.5 (crowned), foam slot **5.5** (three 2.0–2.3 mm strips, 0.5–1.4 mm preload), collar 1.2 (Ø 6), guide plate 6, 0.7 gap, cam. Pin Ø 4.0, length 20.95 nominal (crown adds per pin), palm tip r 2.1 dome, printed holes Ø 4.3 reamed to 11/64" (4.37). Foam holes Ø 5, by heat only (cold drilling tears EVA and the hole grips the pin).

**Servo FS0307, measured Oct 16 (Ethan, calipers)**: body 9.0 wide (8.5–9.0) × 20.0 long × **17.0** back-to-body-top; round tower Ø 8 to **21.0** from the back (= horn mounting plane, CAD y = 0); collar Ø ~5.3, ~2 mm; ears 27.0 tip-to-tip, 1.0 thick, ear front face **14.0** from the back (centre at y = −7.5); horn top **26.5** from the back (y1 = 5.5); horn hub **Ø 5.0**, arm 3.0 wide, ~1.3 thick (assumed). Unmeasured still: spline OD (3.9 assumed), output-axis offset from the case end (4.8 assumed), first arm hole radius (3.6).

**Coupling** (shaft end, "C1"): Ø 11 disc, hub bore Ø 5.6 (hub + 0.3/side), arm channel 3.5 wide running the **full pocket depth** (horn enters arm-first), hub bottoms at y = 5.5, screw-head recess Ø 4.8 × 1.5. Horn: single-arm from the bag, arm cut to 4.5 mm from centre, centre screw in. Servo lower ear clipped off; upper ear stops on the bulkhead.

**Chassis**: wall 2, floor 1.6; servo pocket Ø 9.4 wide with 3.5 mm slide room behind a 6.5 mm bulkhead; bulkhead cut is a **closed tunnel** (body + 0.8 tall) so the ear can't pass; pocket behind it open on top. Far wall has blind U-slots for the Ø 4 journals. Lead slot 36 × 9 in the wrist wall at floor level. Strap ears for a 22 mm One-Wrap palm strap. Crank hole only on the n = 1 test frame.

**Forearm pack** (`cad/pack.scad`, `stl/puck/pack_tray.stl`): tray for a 400-point breadboard (82.5 × 54.5) + ESP32 + barrel adapter bay, two One-Wrap loops, lead slot 26 × 10.

**Colours**: transparent face and shafts, black everything else; any colour if unavailable.

## 5. Firmware and protocol (unchanged since v5; `docs/PROTOCOL.md`)

- BLE 9-byte packet at 10 Hz: `[seq, b0..b6, hl]`, band 0 = none, 1..4 = wrist..fingers (0.3–0.9, 0.9–1.6, 1.6–2.5, 2.5–4 m), `hl` = column to tap or 0xFF. Puck failsafe to all-down after 500 ms without packets. Status notify at 1 Hz.
- ESP32 (classic WROOM-32): servo GPIOs cols 0–6 = **32, 33, 25, 26, 27, 14, 13** (8th = 23). S3 variant: 4, 5, 6, 7, 15, 16, 17, 18. BOOT button long-press = PARADE. Onboard LED GPIO 2.
- ESP32Servo direct, 50 Hz, **650–2500 µs = 0–175°**, detach 400 ms after settle, ≤ 3 servos moving at once, FIFO queue. `TAP_DIP_DEG 20`, tap half-period 180 ms.
- Serial commands: `B c n` band, `HL c` highlight, `NULL`, `TEST`, `PARADE`, `US c µs`, `CAL c o deg` (±45, NVS `lantern5g`), `CAL SHOW/SAVE`, `TAP`, `MUTE`, `D`, `H`, `HELP`.
- Tests: `firmware/test/run_host_tests.sh` (protocol + render, Unity shim + mocks). Pass.
- **TODO (decided, not done):** a pulse mode for raised obstacle pins (slow dip, ~1 Hz) because the palm detects motion far better than static height; the highlight tap becomes a faster double tap. Judge Saturday morning with a servo, ship as a switch.

## 6. What went wrong before and how it was fixed (read this before changing CAD)

| Problem | Cause | Fix |
|---|---|---|
| One-piece hand crank couldn't be installed | key 10 mm and knob 14 mm vs 4.8 mm wall hole | two-piece `crank_rod` (D-section, inserted from inside) + `crank_knob` |
| 2 mm stroke not felt | stroke too small; shaft sag ate ~1 mm; resting pins already touching | stroke 2.55 (thinner core), tighter journal fit, 3-strip foam |
| Pins jammed | printed holes rough/undersize; lid floating | ream all holes 11/64"; align lid by feel then tape; screws later |
| Foam gripped pins | cold-drilled EVA holes close up | holes by heat, Ø 5, test every hole |
| Servo slid through the bulkhead into the trough | slot open on top, ear no wider than body | closed tunnel in the bulkhead |
| Horn would not enter shaft pocket (and test coupling) | arm slot only at the pocket bottom under a narrower bore; horn enters arm-first | arm channel full depth, bore +0.3/side; horn-insertion sweep now clean |
| Test frame v2 has no lead slot | generated with crank hole | drill two 11/64" holes at floor level; puck chassis has the slot |

**Today's test column is glued:** horn arm cut off, bore in the old `shaft_A` drilled out, hub hot-glued into it; servo + shaft lowered into the frame as one unit, foam wedge behind the servo. The unit lifts out whole; nothing is glued to the frame. The puck parts do not need glue.

**Lesson that caused two of these:** a pocket drawn as the negative of a part is not assemblable unless the part can travel in from the open end. Check insertion order before printing any coupling or keyed joint.

## 7. Tonight / tomorrow plan

**Fri evening (Harvard):**
1. ESP32 + one servo + column v2: wire black GND, red 5 V rail (1000 µF across it), white GPIO 32. Flash, `TEST`, `PARADE`, `CAL 0 ...` to centre band 1.
2. Gate 1 checks: one pin per band, all down at gaps, thumb can't move a raised pin, `TAP` dips without lifting the neighbour.
3. **Feel test, done properly:** someone else types bands; tester palm on, eyes closed, call the pin, 10 trials; repeat with fingertip; repeat with slow `PARADE`. These three scores decide the pulse mode.
4. Build the servo header board: 7 × 3-pin male headers on perfboard with common 5 V and GND rails, signal wires to the GPIOs.
5. Collect Isabella's plates as they finish; ream 56 holes, snap and sand 28 + 8 pins, foam in, lid on with screws if they exist.

**Sat:** 11 AM gate = full puck with 7 servos live from the phone. Then the app on the real thing, demo course, numbers for the pitch (`docs/PITCH.md`): time to first correct column untrained, hallway speed and collisions with/without, latency.

**Sun 8 AM:** Devpost.

## 8. Risks, honestly

1. **Perceptibility.** 2.55 mm static may still be marginal under the palm. Pulse mode is the mitigation; the alternative is a fingertip-oriented hold.
2. **Horn pocket fit** on the new shafts is modelled, not yet printed; worst case scrape the bore as today.
3. **Servo in the closed tunnel** is modelled from measurements, not yet tried; worst case file the tunnel.
4. **Power:** 7 FS0307 on a 5 V/3 A bank output with ≤ 3 moving at once should hold; brownouts show up as `BROWNOUT` in the serial reset reason.
5. **Time.** Printing ends late Friday night; assembly of 28 pins + 7 shafts is 2–3 hours of hand work.

## 9. Repo map

```
HANDOFF-v8.md            
docs/                    BUILD-HANDOFF (v5 spec + decisions), PROTOCOL, OVERVIEW, PITCH (verified numbers), SHOPPING-LIST,
                         PRINT-HANDOFF (test column), BRUNO-3H, BRUNO-PRINT, ISABELLA-PRINT (current full-puck print guide)
cad/params.scad          every number; cad/lib.scad all geometry; puck.scad / test_column.scad / pack.scad / viewer.scad
cad/build.sh             exports stl/test and stl/puck (zsh note: don't put the openscad command in a variable)
cad/tools/               cam_sim.py (cam design), check_stl.py (watertight/bed check), stl2bin.py, bin2js.py
cad/guide/               steps.scad (crank rig), steps_servo.scad (servo rig + glued workaround), servo/step*.png
cad/viewer/              Three.js layer viewer
stl/puck/                chassis, face, guide, shaft (×7), pins (36 on a sprue), foam_template, pack_tray
stl/test/                frame, strip, guide, shaft_A/H/G, crank_rod, crank_knob, dummy_servo, pins_tip21/15,
                         coupling_C1/C2/C3, hole_coupon, pitch_coupon, foam_template
stl/*.zip                pinpuck-for-mit.zip (Isabella, current), pinpuck-for-bruno.zip (same STLs, Bambu guide),
                         pinpuck-bruno-3h.zip (test column v2), pinpuck-test-column.zip, crank-and-dummy.zip
firmware/                src/ (protocol.h, config.h, cams, render, serial, ble, main), test/, README
ios/                     Lantern app, Shared/ (PeerLink, NearbyPeer), Beacon/ companion, project.yml, README
research/                handheld-tactile-landscape (sources for the pitch), palm-pin-perception, pin-display-hardware,
                         shepherd, peel-hackmit-2026-teardown
```

Published pages (private to Ethan's account): 3D layer viewer, test-column setup guide, FS0307 measuring guide, Column Gate 1 guide (with today's glued route).

## 10. How to regenerate anything

```
sh cad/build.sh all                       # all STLs + previews (needs OpenSCAD 2024+ with Manifold)
python3 cad/tools/check_stl.py stl/puck/*.stl stl/test/*.stl
python3 cad/tools/cam_sim.py              # cam numbers for the current design and variants
cd firmware && sh test/run_host_tests.sh  # firmware host tests
cd ios && xcodegen generate               # then open Lantern.xcodeproj
```

Change a number in `cad/params.scad`, rebuild, run the checker, and re-run the overlap sweep (`cad/guide/steps_servo.scad` renders are the quickest visual sanity check). Any change to the horn or servo numbers must be followed by the horn-insertion test: intersect `shaft()` with a modelled horn at insertion depths 0–3.5 mm and expect zero volume.

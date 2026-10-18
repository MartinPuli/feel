# HANDOFF v7 — the whole project, as built (Thu Oct 15, updated 3:50 AM)

*Replaces nothing: v5 (`docs/BUILD-HANDOFF.md`) is still the spec and v6 (`HANDOFF-v6.md`) the logistics. This file says what exists in the repo right now, what was decided since v6, what is verified and what isn't, and what happens Thursday. Where it disagrees with v5/v6, v7 wins. Everything Ethan said in the Oct 14–15 sessions is in `notes/08-oct14-ethan-inputs.md`.*

## 1. One line

A palm puck with 7 columns × 4 pins (12 mm pitch, 2 mm stroke), one FS0307 servo and one printed camshaft per column, driven by an ESP32 in a forearm pack over Bluetooth from an iPhone 14 Pro Max whose LiDAR finds the nearest waist-to-head obstacle in each direction; one pin taps to point at a found door, EXIT sign, or teammate's phone.

## 2. Status by workstream

| Workstream | State | Verified | Not verified |
|---|---|---|---|
| **CAD** (`cad/`, `stl/`) | Complete, parametric OpenSCAD. 16 test-column parts, 7 puck parts, forearm pack tray | Every STL watertight, one body, on the bed; no collisions at any servo angle; every pin 0.5 mm proud of the domed face; cam simulated | Everything that depends on the real servo/horn (UNMEASURED values); the physics (P1–P5) |
| **Firmware** (`firmware/`) | Rewritten for v5 + the gap-cam layout. Arduino IDE and PlatformIO | Builds for ESP32 and ESP32-S3; 28 protocol + 33 simulation host tests pass for 6/7/8 columns; tests shown to catch 30 deliberate bugs | Never run on a board or a servo |
| **iOS app** (`ios/`, Lantern) | Rewritten for v5: 7 columns, 0.6 m floor cutoff, Door/Exit/Chair/Person/Sarah finding, 9-byte packet | Builds for device; 53 unit tests pass in the simulator; the CoreML detector runs on a sample photo | Never run on a phone: LiDAR, detector speed, BLE, UWB to Sarah, the angle's sign |
| **Companion app** (`ios/Beacon`) | One screen, NI + Multipeer token exchange | Builds | Never run |
| **Docs** | `docs/PROTOCOL.md` (the phone↔puck contract), `cad/README.md` (print, finish, assemble, test), `firmware/README.md`, `ios/README.md`, `docs/BUILD-HANDOFF.md` §13 (corrections to v5) | Firmware, app and docs agree on the packet and the angles | |
| **Research** | `research/handheld-tactile-landscape.md` (Oct 15): 23 devices compared, head-height evidence, user preferences, hackathon precedents, 12 takeaways | The headline statistic checked against the paper | |
| **3D viewer** | https://claude.ai/artifact/39Qf69rmPrHk2vQaBTDHjk (private; share from its menu). Layer toggles, explode slider, "as printed" colours, the forearm pack | | Phone layout |

**Nothing is committed.** 55 changed/new paths. First thing Thursday: `git checkout -b v5 && git add -A && git commit`.

## 3. Decisions since v6

| Decision | Was | Now | Why |
|---|---|---|---|
| Cam layout | one null at 175°, lobes 48° apart (v5 as corrected) | **bands at 0 / 58 / 117 / 175°, an all-pins-down gap half-way between each pair**; a disappearing pin drops into its own gap; a tap dips 21° toward it | Simulated (`cad/tools/cam_sim.py`): with one end null, a tap lifted the next pin ~2.9 mm and pins didn't clear |
| Pin foot | 2 mm round dome | 30° cone with a 0.6 mm tip | A blunt foot makes every lobe act ~15° wider |
| Stroke | 3 mm | **2 mm**, tap dip 1 mm | 3 mm pushes the pin sideways at 70°+ in its holes (jamming); 2 mm gives 62° |
| Electronics | inside the puck (v6 §11) | **forearm pack** (`cad/pack.scad`, `stl/puck/pack_tray.stl`): half-size breadboard with the ESP32 in it, barrel adapter, 1000 µF, two velcro straps; 7 servo leads reach it through the puck's wrist slot | No room in an 89 mm puck; a bay would make it 141 mm long |
| Servo lower ear | pocket in the floor | **cut off flush before assembly** (`keep_lower_tab = false`) | Does nothing; the face plate locks the servo by its upper ear |
| Face plate | flat | **3 mm spherical dome** under the strap; each pin cut to its own length; pin plate prints in puck order with column labels | Palm hollow is 5–8 mm; a flat plate leaves centre pins pressing on nothing |
| Body | 6 mm corners | 9 mm corners, 3 mm bottom chamfer, **3 mm rounded finger edge** | Forearm comfort; fingers curl over the far edge |
| Finger scallops | — | **Built, off** (`finger_scallops = 0`) | They locate one hand size; on others a ridge lands under a finger. Owner-fitted version only |
| Side stops / face texture | — | **No** | Stops fit one hand width; texture is noise around the pins (the research is clear on this) |
| Strain relief | — | Two zip-tie slots in the floor inside the wrist slot | A tug on the lead bundle can't reach the servo plugs |
| Second strap | — | Built, off (`second_strap = true`) | Turn on only if Thursday's hallway walk shows the puck sliding or rotating |
| Filament | black + white | **black body and pins, transparent face plate and shafts** (no white on hand; white pins at the event if available), **white** craft foam under the frosted plate | What Bruno has |
| Pin tips | — | smooth domes, two radii to test (2.1 / 1.5), spin-sanded 400 → 1000 grit; no heat polish | Layer lines are a texture; PLA slumps near 60 °C |
| Landmark | a different tip on the centre column (v6 §7) | **a 0.8 mm ridge on the face plate** in line with the centre column, plus a notch at the finger edge | A pin only marks centre while it's up; tips keep one meaning |
| Puck size | 92 × 112 × 38 (v4) | **88.6 × 88.8 × 35 mm** (38 at the dome's centre), 101 across the strap ears | |
| Breadboard | full ×2 (v6 §3) | **half-size (400-point)**; a full one is 165 mm | Fits a forearm; the ESP32 leaves 4 free holes beside its GPIO pins |
| Screws | — | 8 × M3 × 12 (Home Depot); or hot-glue the face | Not in the bag |
| Reaming | 32 holes | **56** on the puck (face + guide plate both guide the pins); 8 tonight | |

## 4. The build, in order

### Tonight / Thursday midday: the hand-cranked test column
Print from `stl/test/` (`cad/README.md` has settings and the two-plate split). Transparent: `frame`, `strip`, `shaft_A/H/G`. Black: `pins_tip21`, `pins_tip15`, `guide`, `crank`, `dummy_servo`, `foam_template`, `hole_coupon`, `pitch_coupon` (optional). Not yet: `coupling_C1/C2/C3` (after measuring the horn).

Finish: ream 8 holes with the 11/64" bit in the drill (one-second pulses), snip pins off the sprue and spin-sand the tips, dry-lube, cut two foam strips per column (3 + 2 mm) from the template. Assemble per `cad/README.md` "Assemble the crank rig".

Tests (pass criteria in `cad/README.md`): **P1** selection, **P2** return (rig on its side and upside down), **P3** hold under a thumb, **P4** 100 cycles no sticking, **P5** tap dips without lifting the neighbour; plus the 11/12 mm pitch coupon and the tip-radius compare eyes closed. Pick a shaft (A default; H holds harder; G pushes gentler) and write it down.

### Thursday: measure, then one column with a real servo
When the servos arrive: **G1** swing test (`US c 650` → `US c 2500`, expect ~175°) on all 8. Then caliper the servo and horn (table in `cad/README.md` "Thursday: measure"), update `params.scad`, `sh cad/build.sh`, print the three couplings, pick the one that doesn't slip, reprint the shaft, mount the servo in tonight's frame, drive it from serial: `B 0 1..4`, `HL 0`, `CAL 0 o`, `CAL save`. That's one column end to end.

### Friday after 4 PM: the puck
Print `stl/puck/` (chassis, face, guide, 8 shafts, the pin plate, the pack tray; `foam_template`). Cut each servo's lower ear. Assembly order in `cad/README.md` "The full puck". Calibrate one offset per column, check the bands and the gaps, save.

## 5. How to run each part

- **CAD:** edit `cad/params.scad`, `sh cad/build.sh` (seconds). `python3 cad/tools/check_stl.py stl/*/*.stl` verifies the files. `python3 cad/tools/cam_sim.py` before changing the cam. `sh cad/viewer/build.sh` re-exports the web preview layers.
- **Firmware:** Arduino IDE, board "ESP32 Dev Module", libraries ESP32Servo + NimBLE-Arduino (already installed on Ethan's Mac). Columns 0–6 on GPIO 32, 33, 25, 26, 27, 14, 13. Serial 115200, line ending Newline. Bench commands in `docs/PROTOCOL.md`. Host tests: `sh firmware/test/run_host_tests.sh`.
- **iOS:** `cd ios && xcodegen generate`, open `Lantern.xcodeproj`, free Apple ID, run Lantern on the 14 Pro Max and Beacon on the second phone; trust the developer profile on each. Tests: `xcodebuild -scheme Lantern -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Protocol:** `[seq, b0…b6, hl]`, 9 bytes at 10 Hz. Band 0 none, 1 wrist … 4 fingers (0.3–0.9, 0.9–1.6, 1.6–2.5, 2.5–4 m). `hl` = tapping column or 0xFF. Puck failsafe 500 ms.

## 6. Thursday timeline (v6 §9, updated)

| When | What | Who |
|---|---|---|
| 6–9 AM | Home Depot (dry lube, calipers, 400/1000 grit, M3 × 12 ×8, tape, zip ties), Michaels (white craft foam 2 + 3 mm), CVS (25 mm elastic + velcro, black or white) | Ethan |
| Morning | Commit the repo. Xcode: Lantern on the 14 Pro Max, Beacon on the second phone. Walk a hallway with the Run screen. Point at a door and an EXIT sign. **G3** NI test from Debug (Isabella holds the second phone): angle present across ±45° at ≥ 5 Hz; note the sign | Ethan + Isabella |
| Morning | Arduino IDE + blink on whatever ESP32 is available; OpenSCAD on Martin's laptop | Benjamin, Martin |
| Midday | Test column: ream, assemble, P1–P5, pitch and tip tests; choose shaft | Ethan (+ Bruno's printer) |
| ~4 PM | Servos: G1 on all 8, calipers, couplings, one column on a servo | Benjamin + Ethan |
| Night | Decide: printer plan for Friday night (v6 §1 options a/b/c), crown height, foam (one or two strips), shaft variant. Pack bags | All |

## 7. Measurements still needed (update `cad/params.scad`, then rebuild)

| Part | Measure | Sets |
|---|---|---|
| FS0307 | body 3 dims; spline axis to the nearest case end; tab span, thickness, distance behind the spline face; spline height and diameter | chassis thickness, pockets, the face-plate lock, coupling C3 |
| Horn | hub diameter; hub bottom and top above the case; arm thickness and width; first hole radius | couplings C1/C2 and the shaft pocket |
| Hole coupon | which printed hole slides, before and after reaming | `hole_d` |
| Pack parts | the half-size breadboard, the ESP32 board, the barrel adapter | `pack.scad` bays (currently nominal) |

## 8. Open decisions and risks

- **Printer in Cambridge Friday night** (v6 §1): still the biggest schedule risk. Without one, nothing prints between Fri 4 PM and Sat 8 AM.
- **P2 (foam return) and P4 (no jamming)** are the two tests that can kill the mechanism; both run tonight. Fallbacks are in `cad/README.md`.
- **G3** decides whether "find Sarah" exists. Door/EXIT finding needs no second phone.
- **Crown height:** 3 mm is conservative; 4–5 if centre pins feel weak.
- **Hand occupancy** is the structural limit: fingers stay free (lever handles, push bars work; knobs and real grips don't). Pitch the palm puck as the perception prototype and the back-of-hand/forearm form as the product.
- **Outdoor sensing:** 86% of head-level collisions are outdoors (branches, poles); iPhone LiDAR degrades in sun and thin branches are its worst case. The demo is indoors; say so.
- **A blind user before Sunday:** Perkins School for the Blind (Watertown, 10 min from Harvard) and the Carroll Center (Newton) are nearby; one 20-minute session Saturday is worth more than any feature. Email Thursday.
- **Thickness:** 35 mm. A single foam strip (if P2 allows) and a thinner guide plate get ~31.
- **Rules:** ask at registration about pre-written CAD/code; disclose either way (v6 §10).

## 9. What the research changed (Oct 15, `research/handheld-tactile-landscape.md`)

**Pitch, not CAD.** Nothing in the landscape argues for a different puck: palm position cues read well untrained (Animotus), passive displays beat ones you stop to read (3DOD), simple codes are learned in minutes and compound ones aren't (military belts), and the chest-sensor-to-hand-haptics body plan already cut collisions 37% in a randomized trial (Pundlik 2021). The puck is the right shape for all four.

What changed:
- **The headline number was wrong.** "41% monthly head-level collisions" is a misquote; the paper says 13% monthly and that only 2% of blind respondents had *never* hit their head. `docs/PITCH.md` is rewritten with the verified figures; v5 §3 and §9 are corrected in §13 of the handoff.
- **Cite Pundlik 2021 as the ancestor**, Shepherd as the contrast.
- **Lead the highlight beat with "find Sarah"**, then the door. Apple's Magnifier has found doors since iOS 16; the novelty is the target in the same tactile frame as the obstacles, and finding a person by their phone.
- **Measure walking speed with and without the puck.** That's the number 3DOD lost on and the one judges will trust.
- **Say "first one you wear," never "first pin display."**
- The "Halo" name collision is real (HackHarvard 2025 Infosys track winner); "Lantern" is also gone. Working name: Pin Puck.

**Honest assessment (Oct 15, 3:30 AM).** Fully working, the palm puck is a convincing demo and not yet a useful product: it occupies the free hand, its sensor is weakest outdoors where most head-level collisions happen, and nobody has felt pins while walking. What's real: the problem, the lineage (a randomized trial with the same body plan), minute-zero usability, and "find Sarah" (no precedent found). Pitch it as a perception prototype with a product path (back-of-hand or forearm, dedicated depth sensor), report walking speed with and without, and get one blind user's reaction.

## 10. Repo map

```
HANDOFF-v6.md, HANDOFF-v7.md      logistics; this file
docs/BUILD-HANDOFF.md             v5 spec + §13 corrections
docs/PROTOCOL.md                  phone ↔ puck, bench commands
docs/SHOPPING-LIST.md             superseded by v6 §3; reasons kept
cad/params.scad                   every number
cad/lib.scad, puck.scad, test_column.scad, pack.scad, viewer.scad
cad/README.md                     print, finish, assemble, test, measure
cad/tools/                        cam_sim.py, check_stl.py, stl2bin.py, bin2js.py
cad/viewer/                       the web preview (index.html + mesh_*.js)
stl/test/, stl/puck/              what to print
firmware/                         ESP32 (Arduino + PlatformIO), tests, README
ios/Lantern, ios/Beacon, ios/Shared, ios/README.md
notes/08-oct14-ethan-inputs.md    everything Ethan said, verbatim
research/                         perception, hardware, Shepherd, landscape (pending)
```

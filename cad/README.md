# FEEL V1 — greenfield mechanical prototype

This is a **new implementation of the v7 specification**, not recovered or reproduced original CAD. All generated STL results are geometry checks. No part has been printed, fitted to a real servo, or tested on a hand by this build. Start with the manual single-column rig. Do not print the full powered mechanism as an established design.

## Current 175° working assumption — October 17

The user selected **175° assumed usable travel**, not measured calibration. Reference
cam bands are now 0°/58°/117°/175°, gaps 29°/87.5°/146°, and taps
13°/45°/130°/162°. The 12° lobe half-width and all physical dimensions are retained;
no measured fit or mechanical performance is implied. Firmware maps this assumed
angle range linearly to 650–2500 µs. PWM remains gated separately.

**Existing exported STL files, viewer payloads and older evidence are stale** for
this angular layout. Rebuild before printing; never combine the prior 120° shafts
with the new mapping. The full geometry/contact rerun currently needs OpenSCAD,
which was unavailable in this session. Measurement and horn-fit flags remain false.
The separate `cad/production/` tree is not automatically certified by this change.

## Build and inspect

Requires Python 3.10+ and OpenSCAD. The 120° redesign is validated with official OpenSCAD 2026.10.15 (Apple Silicon); the earlier 175° baseline used 2021.01. No third-party Python package is needed for builds, mesh checks or cam checks.

```sh
sh cad/build.sh --fast
sh cad/build.sh
python3 cad/tools/check_stl.py stl/test/*.stl stl/puck/*.stl --json cad/evidence/mesh-checks.json
python3 cad/tools/cam_sim.py --step 0.1 --json cad/evidence/cam-simulation.json --csv cad/evidence/cam-lifts.csv
python3 -m unittest discover -s cad/test -v
openscad -o /tmp/feel-fit.csg cad/tools/fit_probe.scad
```

`--fast` builds four representative test parts under `stl/fast/`, separate from the full-build manifest. The full build exports 16 test-column STL files and 8 puck/pack STL files. `--part puck/face` exports one part; regenerate the full manifest after changing a full-build part. Every export is checked for finite coordinates, nonzero signed volume, closed consistently oriented edges, one connected body, and bed contact at Z=0. The build fails on OpenSCAD warnings. A closed mesh does **not** prove support-free printing, fit, strength, comfort, or safe operation.

`sh cad/build.sh --print-ready` deliberately exits 2 while `measurements_confirmed` or `horn_fit_confirmed` is false in `params.scad`. These flags are a reminder to record real measurements and a successful fit; changing them does not certify the mechanism. Normal builds are allowed to make the test rig and inspection meshes before these measurements. `stl/manifest.json` records exact file hashes and validation results.

Open `cad/test_column.scad`, `cad/puck.scad`, or `cad/viewer.scad` in OpenSCAD. The default is an **illustrative static assembly** at band 2, not a collision proof or dynamic physical simulation. The STL build selects printable parts instead. Use `cad/tools/render_preview.py` after a full build for an actual-mesh PNG review (optional NumPy and Matplotlib).

`sh cad/viewer/build.sh` packages the actual validated STL triangles for `cad/viewer/index.html`. Open that HTML directly in a WebGL browser: drag to rotate, scroll to zoom, toggle components and explode the plates. No CDN/network service is needed. The pin plate/tray are optional separate printed-layout layers; cams are fixed at band 2. The build validates its mesh inputs; JavaScript syntax is checked separately. The 120° mesh payload was repackaged and JavaScript syntax checked. The earlier baseline had a browser interaction check; it has not been repeated for this mesh revision. Neither check establishes physical fit or tactile behavior.

## Geometry and assumptions

| Item | Implemented value / assumption |
|---|---|
| Array | Seven columns, four pins each, 12 mm pitch; column 0 is left when worn in the documented orientation |
| Actuation | One camshaft and one servo per column; only one of its four pins is selected at a time |
| Pin indexing | Band 1 wrist → band 4 fingers; rows Y = −8, 4, 16, 28 mm |
| Shaft axis | Along Y at Z=17.5 mm; positive control rotation matches the specified band angles |
| Cam angles | Bands 0°, 58°, 117°, 175°; down gaps 29°, 87.5°, 146° |
| Tap angles | Nearest gap, lower gap on a tie: 13°, 45°, 130°, 162° |
| Profile | Actual sampled radial polygon; base radius 3.8 mm, peak 5.8 mm, 12° half-width, 1° polygon step |
| Stroke / tips | 2 mm ideal lift; 0.6 mm flat foot; “30° cone” interpreted as half-angle from axis, 60° included |
| Variants | A exponent 2.2; H 2.5 flatter crest; G 1.6 gentler flank. Names are geometric intent, not measured holding force |
| Envelope | 88.6 × 88.8 × 35 mm at flat face, spherical crown 38 mm; 101 mm across strap ears |
| Surface | 3 mm spherical cap over 43.5 mm radius, smooth tip options 2.1 / 1.5 mm; centre ridge and finger-edge notch |
| Guides | 28 face holes + 28 lower guide holes; nominal finished hole 4.366 mm (11/64 inch) |
| Rest / selected | Pin top 1.5 mm below local face at rest; 0.5 mm above it at full lift |
| New layout decisions | Pin grid shifted toward fingers to clear the nominal wrist-side servo bodies; split shaft bearings closed by lower guide; removable servo spacer comb |
| Inactive options | Finger scallops, lower servo tab, second strap disabled. v7's “off” prose wins over its contradictory `second_strap=true` example |

The contact simulation exports the **same vertices used to make the cams** via OpenSCAD. It computes where the polygon contacts the finite-width conical follower, including points inside polygon edges. It does not just equate radial radius to pin lift. It tests band isolation, all three neutral gaps, the actual firmware tap angles, and a 0.1° sampled sweep. The previous 120° A/H/G contact run retained 2 mm selection and gave approximately 1.059 / 0.985 / 1.249 mm tap drops in this ideal model. It contains no friction, elastic deflection, foam, backlash, tolerance, motor torque or sensory model. Sampling is not a continuous collision proof.

`fit_probe.scad` checks selected nominal envelopes (servo case versus floor/inner rounded walls, cone versus lower guide, collar versus guide/face, adjacent cam bounding circles) and emits each pin's length. It is **not** a full assembly collision detector. Current ideal cone-to-guide clearance is **0.282 mm**; verify that the cone never rubs the guide, and adjust `guide_z`, `guide_t` and collar clearance together if needed. The **1.2 mm lower guide** and relocated 0.5 mm collar are greenfield assumptions; guide stiffness and the 0.1 mm collar clearance need physical checking. They provide **4.0 → 2.0 mm** foam space through a stroke. A 3+2 mm stack therefore compresses **20% at rest and 60% at full lift**: it is a material-dependent test candidate, not an approved return spring. A single 2 mm strip leaves a dead zone and cannot provide return to rest upside-down. Foam load/return remains a physical release blocker.

## Historical 120° FS0307 cam redesign (superseded angles)

The previous revision used four band centers at 0°/40°/80°/120°, three neutral gaps at 20°/60°/100°, and a 13° tap toward the nearest gap (lower gap wins a tie). The radial lobe half-width is reduced from 24° to **12°**; base radius 3.8 mm, full 2 mm lift, the 0.6 mm follower foot and 30° cone remain unchanged. The ideal contact model includes the cone and the interiors of polygon edges. Keeping the old 24° lobe with these centers would lift **both** adjacent pins by over 0.8 mm at a nominal neutral gap. A 14° lobe also fails the strict neutral limit for A/H. The narrower 12° profile clears the gaps without reducing stroke. No contact or isolation acceptance threshold was relaxed.

The geometric tradeoff is steeper, narrower flanks: higher side loading, required torque, wear and sensitivity to print finishing are possible. These are unmeasured; repeat manual P1–P5 and unloaded servo characterization before powered integration. A/H/G remain experimental profiles, not ranked force/performance results.

The [manufacturer FS0307 page](https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html) lists 120° at 900–2100 µs. Those were the prior nominal firmware mapping, **not measured safe endpoints for the received servo**. The actual unit's voltage variant, usable travel, unloaded safe pulse range and loaded behavior remain unverified. Keep physical PWM disabled until measured limits are recorded; do not mix old 120° exported cams with the current 175° mapping. If the received unit cannot provide the required usable travel, revise the design from measured limits before coupling it.

Published 20 × 8.3 × 17.3 mm overall dimensions and 20T spline do not specify every mating surface. The case-only axial depth of 13.3 mm, axis offset, ear and horn values in `params.scad` are **UNMEASURED placeholders**. The nominal body envelope is checked, but the real body can differ.

## What to print first

Use the slicer's layer preview. Suggested starting point: 0.12–0.16 mm layers, 3–4 perimeters, 100% infill for shafts/pins/couplings, 20–30% for frame/body/tray. These are untested starting settings. Print a hole coupon before the complete rig. Transparent face/shaft and dark pins/body follow v7, but filament color has no mechanical significance.

| Test part | Quantity | Purpose / preparation |
|---|---:|---|
| `frame`, `guide`, `strip` | 1 each | Manual column and two pin guides. Guide STL is flipped so its plate is on the bed and bearing closures point up |
| `shaft_A`, `shaft_H`, `shaft_G` | 1 each | Compare cam profiles; label bags A/H/G. Shafts export axially upright; narrow journals need a brim and cam undersides may need slicer supports |
| `pins_tip21`, `pins_tip15` | 1 each | Four pins on removable foot tabs/sprues. Keep the two sets separate |
| `crank` | 1 | Fits rear D-shaft; slide on gently, never force a small printed shaft |
| `dummy_servo` | 1 | Checks the declared nominal envelope only; not a substitute for measuring the real case |
| `foam_template` | 1 | Trace separate 3 mm and 2 mm foam strips; holes surround the stems above collars |
| `hole_coupon`, `pitch_coupon` | 1 each | 4.1–4.6 mm holes; compare 11/12 mm pitch before committing to puck |
| `coupling_C1/C2` | after measuring | Two horn-capture clearances; slots receive a real horn, tie holes permit retention experiments |
| `coupling_C3` | after measuring | **Smooth-bore sizing coupon**, not a recreated 20T spline; do not rely on it to transmit servo torque |

All STLs have bed contact; that alone does not make their overhangs printable. Shafts have horizontally projecting cam lobes when exported upright. Use a sacrificial brim and removable supports, or choose a slicer orientation/support arrangement that preserves the four profiles; inspect the lobe surfaces after removal. Never accept supports inside a finished pin-guide hole. Do not scale an STL to “fit” because it changes pitch and stroke; edit the parameters and rebuild.

## Assemble the crank rig

1. Print and inspect the coupon. Test the 4.2 mm stem in each hole. Record the printed hole that slides freely without visible wobble. If reaming, clamp the part and use a sharp 11/64 inch bit by hand first; a powered drill can grab or melt PLA. Remove burrs from both faces. Finish **8 holes** in the rig, **56** in the puck.
2. Snip each pin's small foot tab from the sprue without clipping the 0.6 mm foot. Preserve tip shape. Sand tips with 400 then 1000 grit; remove dust. Avoid heating/polishing PLA. Apply only a small amount of plastic-compatible dry lubricant, kept off skin contact areas.
3. Lay shaft A in the two semicircular seats in the frame. Its D-shaped end points toward the wrist/servo side. The four axial cams must align with the four holes. Do not reverse the shaft. The longer support end points toward the fingers.
4. Flip the guide from its printing orientation. Place it with its bearing closures facing down; those closures form the top halves of the shaft bearings. Check free shaft rotation before adding pins. Never squeeze a journal to overcome a print defect.
5. Insert the four equal-length **test** pins through the lower guide from above. Conical feet rest on their cams; collars remain above the guide. Test pins are for the flat strip, not the domed puck.
6. Trace/cut the foam template. Put foam **above the collars**, under the top strip. The proposed 3+2 mm stack must compress from 5 mm to 4 mm at rest and to 2 mm at full stroke. Measure its load and return before using a servo; dense craft foam may be unsuitable. A single 2 mm strip does not fill the 4 mm rest cavity and is not a return solution. If the stack binds, use a characterized softer material or redesign the elastic return and repeat P1–P5. The collars compress foam as the pins rise; foam must push them down in any orientation.
7. Lower the flat top strip over all four stems and fasten the four corners gently. Confirm the frame is square and holes align; do not overtighten PLA. Attach the crank to the rear D end. Turn by hand through the full useful arc while watching each pin.
8. Record P1–P5 below for each candidate shaft/foam combination. Stop if the force rises or a pin sticks. Reaming/sanding addresses friction; a forceful servo is not a fix for a jam.

## P1–P5: real measurements to record

These are proposed acceptance criteria for the new design, **not historical pass results**. Use a ruler/caliper and a video with the shaft index visible. Start with a sighted stationary adult using the rig on a table.

| Test | Action | Proposed pass criterion |
|---|---|---|
| P1 selection | Turn to all four bands and three gaps, ten times | Only selected pin rises; selected stroke 2.0 ±0.3 mm; every gap returns all pins to rest; no unintended pin above face |
| P2 return | Repeat each band → nearest gap upright, on each side, upside down | Every pin returns in each orientation without a finger assisting it, within 0.5 s; log any slow/stuck event |
| P3 thumb hold | Lightly rest a thumb across the display and hand-turn each selection | Still distinguishable and manually movable without pain, sudden force increase or sticking; **not** a quantified torque test |
| P4 endurance | 100 full band1→gap→band2→gap→band3→gap→band4→gap cycles | Zero sticks, broken tabs, loose couplings or permanent changes; remeasure stroke |
| P5 tapping | Peak → 13° toward its nearest gap → peak at each band | About 1 mm dip; no neighboring pin rises above face; test at intended tap timing only after slow motion passes |

If P2 fails, first remove friction and check alignment, then test foam density/thickness or redesign a positive return mechanism. If P4 fails, stop full-puck printing. Record shaft variant, foam thickness/density, filament, layer height, measured holes, tip choice, a video filename and tester/date. There is no justified full-puck release until these are observed on a physical column.

## Measure before powered integration

Copy measured values into `params.scad`; keep a photograph/drawing and units. Do not mark a value measured from this README.

| Parameter(s) | What to measure | Current status |
|---|---|---|
| `servo_case_w`, `servo_case_z`, `servo_case_depth` | Bare case in its intended upright orientation, excluding horn/spline | UNMEASURED |
| `servo_axis_from_top`, `servo_face_y` | Axis position relative to top/end and installed fore/aft face | UNMEASURED |
| `servo_tab_span`, `servo_tab_t`, `servo_tab_from_face` | Both ear envelope and distances from spline face | UNMEASURED |
| `servo_spline_d`, `servo_spline_h` | Outer spline size/height; confirm teeth and actual horn fit | UNMEASURED |
| `horn_hub_d`, `horn_hub_h`, `horn_arm_w`, `horn_arm_t`, `horn_hole_radius` | Supplied horn and hole positions; retain the manufacturer horn/screw | UNMEASURED |
| `hole_d`, `bearing_clearance`, `fit_clearance` | Printed coupon and journals after finishing | UNMEASURED |
| `pack_breadboard_*`, `pack_adapter_*`, `pack_cap_d` | Actual board, connectors, capacitor and ESP32 protrusions | UNMEASURED |
| Electrical endpoint record | Actual unit voltage rating, safe pulse range, measured angle range under no load | UNMEASURED |

Use C1/C2 to capture the supplied horn without forcing a plastic spline. Their slot and tie holes are prototypes; verify axial retention and torsion before loading a pin. C3 is intentionally a smooth sizing coupon because a reliable tiny spline cannot be inferred from “20T.” Do not glue a motor or cut an ear as the first fit experiment. v7 proposes cutting the lower ear; that is irreversible and must be reviewed on the actual unit after checking the fit. The CAD's lower ear is disabled by default.

## Full puck and forearm pack

Only after the manual and powered single-column gates:

1. Rebuild from measured parameters; inspect all slicer layers and nominal fit probes. Print chassis, face, lower guide, **8 copies** of the chosen shaft (7 + spare), one 28-pin sprue, a foam template, servo-retainer comb and pack tray. The default puck shaft is `shaft_A`; if H/G won the real tests, the corresponding test-column shaft has the same journals and length and can be printed for all seven columns.
2. Preserve the pin plate's column labels C0–C6 and row order. Cut only one pin at a time, transfer to its matching position, and mark the source plate. Puck pin lengths vary with the dome; never swap them with flat-rig pins. `fit_probe.scad` emits the length table.
3. Fit the seven measured servos in wrist bays. Route leads toward the wrist slot and use the two floor tie pairs for strain relief. Do not pinch a lead under a shaft or force the face onto an ear. The removable retainer comb fits between upper ears and the face only after its height is measured.
4. Centre/calibrate the real servos with no cams/load first. Install horns and captured couplings at a known gap. Lay each shaft in its bearings and confirm its band-1 lobe aligns with the wrist pin. Fit the lower guide to close the bearings.
5. Install pins and tested foam as in the rig; fit the domed face with eight M3 ×12 screws into the pilot bosses, gently. Confirm screw length on the actual print. Screws may need a different length after measured changes; do not drive through the floor.
6. Thread 25 mm elastic/Velcro through side ears. The finger-edge notch and wrist centre ridge identify orientation. Evaluate whether a second strap is needed; never constrict circulation. Fit and comfort are pending user testing.
7. Mount the breadboard/ESP32 in the forearm tray, with barrel adapter and capacitor in the end bay, retained by ties. The tray is open and has no battery pocket. Attach two straps and strain-relieve the cable bundle. See `docs/HARDWARE-BRINGUP.md` for electrical steps; never feed seven servos through ESP32 GPIO or undersized breadboard rails.
8. Exercise one column at a time, then all seven. Repeat P1–P5 and timeout/power-loss checks. Only then do supervised indoor perception tasks. The app's simulation does not establish physical touch, torque, return or mobility performance.

## References and limits

- [OpenSCAD official documentation](https://openscad.org/documentation.html), including its command-line export manual. This build uses ordinary CSG, polygons, extrusion and binary STL; it does not need nightly-only features.
- [FEETECH FS0307 current manufacturer page](https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html), consulted during this rebuild. The v7 travel mismatch is addressed by this 120° geometry; actual unit travel and safe endpoints remain physical measurements.

Remaining physical unknowns: real servo angle/voltage variant, coupling retention, print tolerance, 0.282 mm cone-guide / 0.1 mm collar-guide nominal margins, thin-guide stiffness, foam load/return at 20–60% compression, side force/jamming, shaft bending, sustained current, skin comfort, hand size and tactile recognition. No software or mesh test clears these.

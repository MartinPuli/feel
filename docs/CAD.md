# Pin Puck production CAD: complete specification and rebuild prompt

*Oct 16 2026, matches the files sent to print that evening. Self-contained: an engineer or an AI can regenerate every production STL from this page alone. Units mm, angles degrees. Where a number is derived, the formula is given so a parameter change propagates.*

---

## Prompt (paste this, then the specification below it)

> Recreate the Pin Puck production CAD as parametric OpenSCAD (one `params.scad`, one `lib.scad` with one module per part, one `puck.scad` that exports a part by `-D part="…"`). Follow the specification exactly: same coordinate frames, same parameter names and values, same construction order where it is given, same print orientations. Do not improve, simplify or re-proportion anything. After generating, export every STL listed under "Deliverables" with the Manifold backend and verify each one: single watertight body, bounding box within 0.1 mm of the stated size, lowest face on z = 0. Then run the three assembly checks under "Verification". Report every check with its measured number. If anything in the specification is ambiguous, say so rather than guessing, and state the assumption you made.

---

## 1. Coordinate frames

**Puck frame** (used for chassis, plates, pins placement, pack):
- **x** across the columns. User's left is negative. Column `c` of `n` is at `col_x(c) = (c − (n−1)/2) · col_pitch`.
- **y** along the shafts. **y = 0 is the servo's horn mounting plane** (top of the servo's round tower). Pins lie toward +y (fingers). The servo body is at negative y.
- **z** toward the palm. **z = 0 is the palm face of the top plate** at its edge (the crown rises above it). Everything else is negative.

**Shaft frame** (used for shafts and the horn): the part stands along **+Z**, with Z = puck y, X = puck −x, Y = puck z. A shaft is placed into the puck by the affine map `(X, Y, Z) → (−X + col_x, Z, Y + z_rod)`. A servo angle `a` is a rotation of `+a` about Z in the shaft frame (counter-clockwise seen from the horn). A lobe "pointing +Y" in the shaft frame points toward the palm.

## 2. Parameters (`params.scad`)

### Layout
```
cols = 7            col_pitch = 12
rows = 4            row_pitch = 13          y_row0 = 14.5
row_y(r) = y_row0 + r·row_pitch            → 14.5, 27.5, 40.5, 53.5
```

### Servo, FEETECH FS0307, measured
```
servo_w = 9.0           across columns (x)
servo_len = 20.0        vertical (z); the output end faces DOWN (toward the floor)
servo_body_h = 17.0     case back → flat body top (y)
servo_h = 21.0          case back → tower top = horn plane (y);  servo_back_y = −servo_h = −21
servo_tower_d = 8.0     round tower on the body top, up to y = 0
servo_shaft_off = 4.8   output axis above the body's lower end (z)
servo_tab_span = 27.0   ear tip to ear tip (z)
servo_tab_t = 1.0       ear thickness (y)
servo_tab_y = −(servo_h − 14.0) − servo_tab_t/2 = −7.5    ear centre plane (ear front face at y = −7.0)
servo_fit = 0.2         per side, bulkhead tunnel
servo_slide = 3.5       room behind the servo so it can slide back while the shaft drops in
```
Servo body model (for clearance checks): box `servo_w × servo_body_h × servo_len` with its back at y = −21, bottom at `z_rod − servo_shaft_off`, centred on x; plus a cylinder d 8 along +y from the body top to y = 0 on the output axis; plus the upper ear: box `servo_w × servo_tab_t`, from z = body bottom + 0.5 up to `z_rod − 4.8 + 10 + 13.5`, centred on y = −7.5. (The lower ear is clipped off in assembly and not modelled.)

### Horn (single-arm nylon horn, measured) and its coupling pocket
```
horn_hub_d = 5.0    horn_y0 = 2.0 (hub underside above y=0)    horn_y1 = 5.5 (horn top above y=0)
horn_arm_w = 3.0    horn_arm_t = 1.3    horn_trim_r = 4.5 (arm cut square 4.5 from centre)
horn_head_d = 4.8   horn_head_h = 1.5   (recess for the centre screw head)
hub_fit = 0.3  arm_fit = 0.25  (per side)
coupling_d = 11     coupling_y0 = horn_y0 = 2.0     coupling_len = 5.2
farj_d = 4.0        bearing_fit = 0.2
```

### Cam
```
band_angle = [0, 58, 117, 175]          gap_angle(i) = midpoint of band i, i+1  → 29, 87.5, 146
cam_flat = 5    cam_ramp = 24           (flat + ramp = 29 = half the band spacing)
stroke = 2.55   foot_clear = 0.3        lift = stroke + foot_clear = 2.85
cam_base_r = 2.6                        cam_max_r = cam_base_r + lift = 5.45
lobe_w = 5      cone_h = 2.0            core_r = cam_base_r = 2.6
foot_tip_r = 0.5   foot_cone = 25 (half-angle)
cam_step = 0.5 (degrees per polygon vertex)
```
Three-lobe variant for a 120° servo: `shaft3_rows = [0, 2, 3]`, `shaft3_angles = [0, 55, 110]`, `shaft3_flat = 5`, `shaft3_ramp = 22.5`.
Four-lobe variant for a 120° servo (added Oct 17): `shaft4_angles = [0, 40, 80, 120]`, `shaft4_flat = 5`, `shaft4_ramp = 15` (flat + ramp = 20 = half the 40° spacing). Steeper ramps: hold window ±6.2° instead of ±7°, tap dip 1.57 mm at the firmware's 13° tap. Two ID dots. Gaps at 20, 60, 100: matches the current firmware angles.

Lobe profile function, `s(d)` with `a = |wrap180(d)|`: `1` if `a ≤ flat`; `0` if `a ≥ flat + ramp`; else `0.5·(1 + cos(180·(a − flat)/ramp))`. Lobe radius at angle t: `r(t) = cam_base_r + lift·s(t)`.

### Pin stack (z)
```
face_t = 4.5    foam_t = 5.5    collar_d = 6.0    collar_h = 1.2    guide_t = 6.0    guide_gap = 0.7
hole_d = 4.3    pin_d = 4.0     rest_proud = 0.5  tip_r = 2.1       tip_flat = 0.25
foam_hole = 4.5                 foam_strip_w = col_pitch − 1 = 11
z_guide_top = −(face_t + foam_t + collar_h) = −11.2
z_guide_bot = z_guide_top − guide_t = −17.2
z_rod = z_guide_bot − cam_max_r − guide_gap = −23.35          (shaft axis)
foot_rest = z_rod + cam_base_r + foot_clear = −20.45          (pin foot tip, pin down)
pin_len = rest_proud − foot_rest = 20.95
collar_z = z_guide_top − foot_rest = 9.25                     (collar underside, from the foot tip)
```

### Chassis
```
wall = 2.0    floor_t = 1.6    cam_gap = 0.8
z_floor_top = z_rod − cam_max_r − cam_gap = −29.6
servo_body_bot = z_rod − servo_shaft_off = −28.15
z_bottom = min(z_floor_top − floor_t, servo_body_bot − 0.8) = −31.2
bulk_y = [servo_tab_y + servo_tab_t/2, −0.5] = [−7.0, −0.5]       (bulkhead occupies this y range)
wrist_in_y = servo_back_y − servo_slide − 1.0 = −25.5
wrist_t = 5.0          wrist_out_y = wrist_in_y − wrist_t = −30.5
far_in_y = y_row0 + 3·row_pitch + lobe_w/2 + 1.0 = 57.0
far_t = 5.0            far_out_y = 62.0          far_pocket = 3.5
ledge = 1.5            corner_r = 9              bottom_chamfer = 3
screw_pilot = 2.6      screw_clear = 3.4         screw_cb_d = 6.2    screw_cb_h = 2.0    screw_in = 3.0
strap_w = 27           lead_slot_w = 36          lead_slot_h = 9     lead_tie = true
face_crown = 3.0       finger_round = 3.0        ridge_h = 0.8       finger_scallops = 0
half_w(n) = col_x(n−1) + cam_max_r + cam_gap + wall  → 44.25 for n = 7   (puck width 88.5, length 92.5)
crown_yc = y_row0 + 1.5·row_pitch = 34.0
crown_R = (half_w² + max(far_out_y − crown_yc, crown_yc − wrist_out_y)²) / (2·face_crown) = 1019.7
crown_z(x, y) = face_crown − (crown_R − sqrt(crown_R² − x² − (y − crown_yc)²))     (0 for n < 3)
screw points: x = ±(half_w − screw_in) = ±41.25 ; y = (wrist_out_y + wrist_in_y)/2 = −28 and (far_in_y + far_out_y)/2 = 59.5
pin_sprue_t = 1.0
```

### Forearm pack
```
bb_l = 82.5  bb_w = 54.5  bb_h = 8.5        (half-size breadboard)
adp_l = 30   adp_w = 14.5 adp_h = 15        (barrel-jack screw-terminal adapter)
pack_fit = 0.6   pack_wall = 2.0   pack_floor = 2.0   pack_rim = 14
pack_loop_w = 27   pack_loop_gap = 3.5   pack_loop_t = 2.5
pack_in_l = bb_l + 2·pack_fit + adp_w + 2·pack_fit + pack_wall = 101.4     pack_in_w = bb_w + 2·pack_fit = 55.7
pack_out_l = 105.4     pack_out_w = 59.7
pack_gap_y = 18        pack_y1 = wrist_out_y − pack_gap_y = −48.5     pack_y0 = pack_y1 − pack_out_l = −153.9
pack_z0 = z_bottom = −31.2             lead_slot_pack = [26, 10]
```

### Resolution
`$fa = 4`, `$fs = 0.25`, crown sphere `$fn = 900`.

## 3. Parts

Helper: `rrect(w, l, r)` = a 2-D rectangle `w` wide (centred on x) running y = 0 … l, with corner radius r. `uslot(r, l, h=40)` = a cylinder of radius r along +y of length l plus a box 2r wide, l long, h tall above it (a U-shaped cut open toward +z).

### 3.1 Chassis (`chassis_print`: translate by `−z_bottom` so the bottom sits on z = 0)
With `hw = half_w`, `iw = hw − wall = 42.25`, `L = far_out_y − wrist_out_y = 92.5`, `ztop = −face_t = −4.5`:

1. **Outer body**: hull of (a) `rrect(2hw − 2·bottom_chamfer, L − 2·bottom_chamfer, corner_r − bottom_chamfer)` extruded 0.01 at `y = wrist_out_y + 3`, `z = z_bottom`, and (b) `rrect(2hw, L, corner_r)` at `y = wrist_out_y`, extruded from `z_bottom + 3` to `ztop`.
2. **Cavity**: subtract a box x ∈ [−iw, iw], y ∈ [wrist_in_y, far_in_y], z from `z_floor_top` up through the top.
3. **Bulkhead**: add a box x ∈ [−iw−0.01, iw+0.01], y ∈ [bulk_y[0], bulk_y[1]], z ∈ [z_floor_top, ztop].
4. **Front ledge**: add a box x ∈ [−iw, iw], y ∈ [bulk_y[1], bulk_y[1] + 1.6], z ∈ [z_guide_bot − ledge, z_guide_bot].
5. **Side ledges**: along both side walls from y = bulk_y[1] to far_in_y, a 45° triangular prism: top face at `z_guide_bot`, protruding `ledge` = 1.5 inward from the wall, 1.5 tall, underside sloped.
6. **Strap ears**, mirrored on both sides, at `ym = (row_y(0) + row_y(3))/2 = 34`, `ey = strap_w + 4 = 31`: hull of a box [hw − 0.5 … hw + 6, ym − 15.5 … ym + 15.5, −20 … −12] and a box [hw − 0.5 … hw, same y, −26.5 … −25.5]; minus a slot box [hw + 0.8 … hw + 4.3, ym − 13.5 … ym + 13.5, −40 … 0].
7. **Servo cuts**, per column at `x = col_x(c)`:
   - Tunnel through the bulkhead: box x ∈ [x − 4.7, x + 4.7], y ∈ [bulk_y[0] − 0.1, bulk_y[1] + 1.8] (= −7.1 … 1.3), z ∈ [servo_body_bot − 0.2, servo_body_bot − 0.2 + servo_len + 0.8] (= −28.35 … −7.55). Closed on top: the ear stops on the bulkhead's −y face.
   - Pocket behind the bulkhead, open to the top: box x ∈ [x − 5.2, x + 5.2], y ∈ [wrist_in_y − 0.1, bulk_y[0] + 0.1], z from −28.35 up 60.
8. **Far journal slots**, per column: `uslot(farj_d/2 + bearing_fit = 2.2, far_pocket + 0.1 = 3.6)` at (col_x, far_in_y − 0.1, z_rod), i.e. a blind slot into the far wall leaving 1.5 mm of skin outside.
9. **Screw pilots**: cylinders d `screw_pilot` from `ztop − 12` to ztop + 0.1 at the four screw points.
10. **Lead slot**: box x ∈ [−18, 18], y ∈ [wrist_out_y − 0.1, wrist_in_y + 0.1], z ∈ [z_floor_top, z_floor_top + 9].
11. **Zip-tie slots**: two boxes 3 (x) × 1.8 (y) through the floor at x = ±10 − 1.5 … ±10 + 1.5, y ∈ [wrist_in_y + 1.5, wrist_in_y + 3.3], z from z_bottom − 1 to z_floor_top + 1.

Result for n = 7: 100.5 (with ears) × 92.5 × 26.7 mm.

### 3.1b Lenient chassis (`chassis_loose`, added Oct 17)
Same as 3.1 except: the bulkhead tunnel is **open on top** (z up through ztop) so the servo drops in with its tower already through the wall instead of sliding forward; tunnel and pocket use `loose_fit = 0.5` per side (tunnel 10.0 wide, pocket 11.4) so a 0.6 mm nozzle print still fits a 9.0 servo; the wire slot in the wrist wall spans all seven pockets (`2·(col_x(6) + 5.2 + 0.5) − 2·3.0` = 79.8 wide). The ear no longer locates against the bulkhead: servos are aligned to their shafts and glued at the ears. Collision sweep and servo clearance pass identically to 3.1. Built after a hand fit showed the as-specified tunnel (0.2 per side, closed top) could not be assembled.

### 3.2 Guide plate (`guide_plate_print`: translate by `−z_guide_bot`)
Box x ∈ ±(half_w − wall − 0.2) = ±42.05, y ∈ [0.3, far_in_y − 0.2 = 56.8], z ∈ [z_guide_bot, z_guide_top]; minus 28 through-holes d `hole_d` at (col_x(c), row_y(r)). Size 84.1 × 56.5 × 6.0.

### 3.3 Face plate (`face_plate_print`: translate by `+face_t`, palm side up)
With `hw = half_w`, `L = 92.5`, `r = corner_r`, `cr = face_crown`:
1. Blank: hull of `rrect(2hw, L, r)` at y = wrist_out_y extruded from `−face_t` by `face_t + cr − 0.8`, and `rrect(2hw − 1.6, L − 1.6, r − 0.8)` at y = wrist_out_y + 0.8 extruded from `−face_t` by `face_t + cr`. (A 0.8 mm edge round.)
2. Intersect with a sphere of radius `crown_R` centred at (0, crown_yc, cr − crown_R): the top becomes a dome 3 mm high at the pin field centre, exactly z = 0 at the farthest corner.
3. Intersect with the union of (a) a box covering everything up to y = far_out_y − finger_round and (b) the hull of a cylinder radius `finger_round` along x at (y = far_out_y − finger_round, z = crown_z(0, far_out_y − finger_round) − finger_round) and a thin box at the bottom edge: this rounds the finger edge with a 3 mm radius tangent to the top.
4. Add the **ridge**: hull of two spheres r 0.8 at (0, y_row0 − 12.5 = 2.0, crown_z) and (0, y_row0 − 7 = 7.5, crown_z) (ridge_h = 0.8 so the scale is 1).
5. Subtract 28 holes d `hole_d` at (col_x(c), row_y(r)), through.
6. Subtract the **ear pocket**: box x ∈ ±(hw − wall), y ∈ [servo_tab_y − servo_tab_t/2 − 0.3, + servo_tab_t + 0.6] = [−8.3, −6.7], from the underside up 1.5.
7. Subtract four **screw holes**: d `screw_clear` through, with a counterbore d `screw_cb_d`, depth `screw_cb_h` from the local top surface (top at crown_z(x, y) of each point).
8. Subtract a **notch** at the finger edge: cylinder r 2.2 through at (0, far_out_y).
Size 88.5 × 92.5 × 7.9 (4.5 + 3 crown + ridge).

### 3.4 Shaft (`shaft_print`: translate by `−coupling_y0`, so it stands on its disc, coupling down)
In the shaft frame (Z along the shaft):
1. **Coupling disc**: cylinder d `coupling_d` from Z = coupling_y0 (2.0) to coupling_y0 + coupling_len (7.2).
2. **Core**: cylinder r `core_r` from Z = 7.19 to `far_in_y − 0.2` = 56.8.
3. **Lobes**, one per entry k of `band_angle` on row `k` (4-lobe) or of `shaft3_angles` on `shaft3_rows` (3-lobe): the 2-D polygon with vertices `r(t)·(−sin t, cos t)` for t = 0, 0.5, … 359.5 (points +Y at t = 0), extruded `lobe_w` = 5 from `Z0 = row_y(row) − 2.5`; plus a hull between that polygon (0.01 thick at Z0 − 0.01) and a circle r `core_r` at Z0 − cone_h (print chamfer under the lobe). The whole lobe is rotated by `−band_angle[k]` about Z.
4. **Far journal**: cylinder d `farj_d` from Z = far_in_y − 0.21 to far_in_y + far_pocket − 0.3 (= 56.79 … 60.2).
5. **ID dots**: nd spheres r 0.7 on the disc's +Z face at Z = 7.0, radius 4.0, at angles 180 + (i − (nd−1)/2)·32 about Z. nd = 1 for `shaft`, 3 for `shaft3`.
6. Subtract the **coupling pocket** (horn enters from the Z = 2.0 face, arm first):
   - hub bore d `horn_hub_d + 2·hub_fit` = 5.6 from Z = 1.99 to `horn_y1` = 5.5;
   - arm channel, full depth Z = 1.99 … 5.5: the 2-D union of a rectangle `2·(horn_trim_r + arm_fit)` = 9.5 long (along X) × `horn_arm_w + 2·arm_fit` = 3.5 wide, centred, and a circle d `horn_hub_d + 2·arm_fit` = 5.5;
   - screw-head recess d `horn_head_d` = 4.8 from Z = 5.49 by `horn_head_h` = 1.5;
   - keying notch for the hand crank: box X ∈ [4.5, 6.5], Y ∈ ±(0.7 + arm_fit), Z = 1.99 … 5.5;
   - entry chamfer: cone from d 6.4 at Z = 1.99 to d 5.6 at Z = 2.39.
7. Subtract the **band-1 groove**: a 1.3 × 1.3 square bar rotated 45° about Z, centred at (0, coupling_d/2, 4.6), length 9.2 along Z: a V along the rim on the +Y side.
Size 11.0 × 10.9 × 58.2. `shaft3` is identical except for the lobes.

### 3.4b Reinforced coupling (Oct 17, default on; `reinforce = false` restores 3.4 exactly)
Printed shafts snapped at the disc-to-stem junction within two cam rotations. As specified, the screw-head recess (d 4.8 × 1.5 from Z 5.5) leaves a 0.2 mm floor under a 4.8 mm bore, and the stem (d 5.2) joins the disc through that film at a sharp step, on a layer line. Three changes, none altering length, horn pocket depth, journal, lobes or any chassis fit: screw-head recess d 4.6 × 1.5 (head is 4.2 × 1.3: 0.2 clearance, a 0.3 ring of wall at the stem root instead of none); keying notch ends at X 6.0 instead of 6.5 (rim wall 1.25 instead of 0.75); a cone fillet d 8.0 → 5.2 over Z 7.19 … 9.19 behind the disc (first lobe starts at 12.0). Horn insertion clear at 0, 0.5, 1, 2, 3, 3.4 mm; collision sweep unchanged. Volume 1574 mm³ vs 1546. Print standing, 100% infill, 4 walls, and hotter/slower than the PLA default; PETG preferred.

### 3.5 Pins (`pins_plate_puck`, prints as one plate)
Single pin, foot tip at the origin, length `L = pin_len + crown_z(x, y)` of its position:
1. Foot: hull of a sphere r `foot_tip_r` at z = 0.5 and a disc d `pin_d` at `zct = foot_tip_r − foot_tip_r/sin(foot_cone) + (pin_d/2)/tan(foot_cone)` = 3.606.
2. Shaft: cylinder d `pin_d` from zct to L − tip_h, `tip_h = max(tip_r, 2.2)` = 2.2.
3. Palm tip: hull of a disc d pin_d at L − tip_h and a sphere r `tip_r` at L − tip_r.
4. Collar: cylinder d `collar_d`, height `collar_h`, from z = `collar_z` = 9.25.
5. Intersect with z ∈ [0, L − tip_flat] (flattens the tip by 0.25 so it stands for printing) and with the union of a d 4 cylinder of length L and the collar cylinder.

Plate: 28 pins in puck order plus 8 spares (column 3, bands 2 and 3 alternating) on a 9 mm grid, 7 per row, 6 rows; sprue plate 63 × 58 × 1.0 from (−4.5, −8.5); each pin inverted (rotate 180° about x) with its flattened tip on the sprue at z = 1.0, at (c·9, r·9) for pin (c, r), spares in rows 4 and 5. Column digits (text size 3, 0.6 raised) along y = −6.7 under each column; the word "spares" above the last row. Size 63 × 58 × 24.7.

### 3.6 Foam template (`foam_template_print`)
Plate `foam_strip_w` = 11 × 49 × 1.2, from y = row_y(0) − 5 = 9.5 to 58.5; holes d `foam_hole` at the four row_y; a r 1.5 mark hole at y = 9.5 (the wrist end). Print with its near end at y = 0.

### 3.7 Pack tray (`pack_tray_print`: translate so pack_y0 → 0 and pack_z0 → 0)
1. Body: `rrect(pack_out_w, pack_out_l, 4)` at y = pack_y0, extruded `pack_floor + pack_rim` = 16 from z = pack_z0.
2. Subtract the breadboard bay: x ∈ ±pack_in_w/2, y ∈ [pack_y0 + 2, pack_y0 + 2 + bb_l + 1.2], from z = pack_z0 + 2 up 40; and the adapter bay: same x, y ∈ [pack_y1 − 2 − adp_w − 1.2, pack_y1 − 2], same z.
3. Subtract the lead notch toward the puck: box x ∈ ±13, y ∈ [pack_y1 − 2.1, pack_y1 + 0.1], from z = pack_z0 + 16 − 10 up 11; and a barrel-cable notch at the far end: x ∈ ±6, y ∈ [pack_y0 − 0.1, pack_y0 + 2.1], from z = pack_z0 + 16 − 9 up 10.
4. Subtract two zip-tie slots 3 × 4 through the floor at x = ±15 − 1.5, y = pack_y1 − 2 − adp_w/2 − 2.
5. Subtract 12 drain holes d 8 through the floor at x = −15, 0, 15 and y = pack_y0 + 14 + 17·i, i = 0…3.
6. Add four strap loops, two per long side at y = pack_y0 + 14 and pack_y1 − 14 − pack_loop_w: a box `(pack_loop_gap + pack_loop_t) × pack_loop_w × 16` on the outside of the wall, minus a slot `pack_loop_gap` deep from z = 1.6 to 16 − 1.6 so a strap passes between the bar and the wall.
Size 71.7 × 105.4 × 16.0.

## 4. Deliverables (print orientation is the modelled orientation after the stated translate; never rotate)

| File | Qty | Size (mm) | Layer | Infill | Brim |
|---|---|---|---|---|---|
| chassis.stl | 1 | 100.5 × 92.5 × 26.7 | 0.20 | 15% | no |
| chassis_loose.stl | 1 (alternative, hand assembly / 0.6 nozzle) | same | 0.20–0.30 | 15% | no |
| guide.stl | 1 | 84.1 × 56.5 × 6.0 | 0.20 | 15% | no |
| face.stl | 1 | 88.5 × 92.5 × 7.9 | 0.20, ironing on | 15% | no |
| shaft.stl | 7 | 11.0 × 10.9 × 58.2 | 0.10–0.15 | 100%, 4 walls | 3 mm |
| shaft3.stl | 7 (alternative) | same | same | same | same |
| shaft4.stl | 7 (alternative, 120° servo, all four rows) | same | same | same | same |
| pins.stl | 1 plate | 63 × 58 × 24.7 | 0.10–0.15 | 100%, 4 walls | 3 mm |
| foam_template.stl | 1 | 11 × 49 × 1.2 | 0.20 | any | no |
| pack_tray.stl | 1 | 71.7 × 105.4 × 16.0 | 0.20 | 15% | no |

No supports on anything. Holes are printed undersize on purpose and reamed to 11/64" (4.37 mm).

## 5. Verification (run before releasing files)

1. **Mesh**: every STL is one watertight body, volume positive, min z = 0, bounding box within 0.1 mm of the table above.
2. **Collision sweep**: in the puck frame with all parts in place and the shaft rotated to each of −5, 0, 29, 58, 87.5, 117, 146, 175, 180 degrees, the intersection volume of shaft×chassis, shaft×servo body, shaft×guide plate, shaft×neighbouring shaft, servo×chassis, servo×guide plate, servo×neighbouring servo must be zero.
3. **Horn insertion**: model the horn (hub cylinder d 5.0 from Z 2.0 to 5.5; arm box X 0…4.5, Y ±1.5, Z 4.2…5.5; screw head d 4.2 from Z 5.5 by 1.3) and intersect it with the shaft at insertion offsets 0, 1, 2, 3, 3.4 mm along −Z. Volume must be zero at every offset (coincident faces at full insertion are allowed).
4. **Cam numbers** (simulate a pointed foot on the rotating lobe): stroke 2.55 ± 0.05, rise at a null gap ≤ 0.15, neighbour rise during a 20° tap ≤ 0, flat hold window ≥ ±7°.

## 6. Things that are deliberate, do not "fix"

- The arm channel of the coupling pocket runs the full pocket depth: the horn enters arm first.
- The bulkhead cut is a closed tunnel; the pocket behind it is open on top.
- Pin holes 4.3 in a 4.0 pin, hub bore 5.6 on a 5.0 hub, journal slot 4.4 on a 4.0 journal: all printed-PLA allowances.
- The pin tip is flattened by 0.25 mm and pins print upside down on a 1 mm sprue.
- Resting pins stand 0.5 mm proud; a raised pin 3.05 mm. The face is a 3 mm dome and every pin's length includes the dome height at its own position.
- Row 1 (second from the wrist) has no lobe on `shaft3`; its pins stay in place and never rise.

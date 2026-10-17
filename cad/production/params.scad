// Pin Puck production CAD: every parameter from CAD.md section 2.
// Units mm, angles degrees. Derived values carry their formula so a change propagates.
//
// Puck frame:  x across columns (user's left negative), y along the shafts
//              (y = 0 is the servo horn mounting plane, pins toward +y),
//              z toward the palm (z = 0 is the palm face of the top plate at its edge).
// Shaft frame: Z along the shaft (Z = puck y), X = puck -x, Y = puck z.

// ---------------------------------------------------------------- layout
cols = 7;
col_pitch = 12;
rows = 4;
row_pitch = 13;
y_row0 = 14.5;
function col_x(c, n = cols) = (c - (n - 1) / 2) * col_pitch;
function row_y(r) = y_row0 + r * row_pitch;                    // 14.5, 27.5, 40.5, 53.5

// ---------------------------------------------------------------- servo, FEETECH FS0307, measured
servo_w = 9.0;              // across columns (x)
servo_len = 20.0;           // vertical (z); output end faces down
servo_body_h = 17.0;        // case back -> flat body top (y)
servo_h = 21.0;             // case back -> tower top = horn plane (y)
servo_back_y = -servo_h;    // -21
servo_tower_d = 8.0;
servo_shaft_off = 4.8;      // output axis above the body's lower end (z)
servo_tab_span = 27.0;      // ear tip to ear tip (z)
servo_tab_t = 1.0;          // ear thickness (y)
servo_tab_y = -(servo_h - 14.0) - servo_tab_t / 2;            // -7.5, ear front face at -7.0
servo_fit = 0.2;            // per side, bulkhead tunnel
servo_slide = 3.5;          // room behind the servo so it can slide back while the shaft drops in

// ---------------------------------------------------------------- horn (single-arm nylon, measured) and coupling
horn_hub_d = 5.0;
horn_y0 = 2.0;              // hub underside above y = 0
horn_y1 = 5.5;              // horn top above y = 0
horn_arm_w = 3.0;
horn_arm_t = 1.3;
horn_trim_r = 4.5;          // arm cut square 4.5 from centre
horn_head_d = 4.8;          // recess for the centre screw head
horn_head_h = 1.5;
hub_fit = 0.3;              // per side
arm_fit = 0.25;             // per side
coupling_d = 11;
coupling_y0 = horn_y0;      // 2.0
coupling_len = 5.2;
farj_d = 4.0;
bearing_fit = 0.2;

// ---------------------------------------------------------------- cam
band_angle = [0, 58, 116, 174];
function gap_angle(i) = (band_angle[i] + band_angle[i + 1]) / 2;   // 29, 87, 145
cam_flat = 5;
cam_ramp = 24;              // flat + ramp = 29 = half the band spacing
stroke = 2.55;
foot_clear = 0.3;
lift = stroke + foot_clear;                                    // 2.85
cam_base_r = 2.6;
cam_max_r = cam_base_r + lift;                                 // 5.45
lobe_w = 5;
cone_h = 2.0;
core_r = cam_base_r;
foot_tip_r = 0.5;
foot_cone = 25;             // half-angle
cam_step = 0.5;             // degrees per polygon vertex

// Three-lobe variant for a 120 degree servo. Row 1 has no lobe.
shaft3_rows = [0, 2, 3];
shaft3_angles = [0, 55, 110];
shaft3_flat = 5;
shaft3_ramp = 22.5;

// Four-lobe variant for a 120 degree servo: all four rows, lobes 40 degrees apart. Steeper ramps
// (flat + ramp = 20 = half the spacing): hold window +-6.2 degrees, tap dip 1.6 mm at 13 degrees.
shaft4_angles = [0, 40, 80, 120];
shaft4_flat = 5;
shaft4_ramp = 15;

function wrap180(d) = d - 360 * floor((d + 180) / 360);
function lobe_s(d, flat = cam_flat, ramp = cam_ramp) = let(a = abs(wrap180(d)))
    a <= flat ? 1 : a >= flat + ramp ? 0 : 0.5 * (1 + cos(180 * (a - flat) / ramp));
function lobe_r(t, flat = cam_flat, ramp = cam_ramp) = cam_base_r + lift * lobe_s(t, flat, ramp);

// ---------------------------------------------------------------- pin stack (z)
face_t = 4.5;
foam_t = 5.5;
collar_d = 6.0;
collar_h = 1.2;
guide_t = 6.0;
guide_gap = 0.7;
hole_d = 4.3;
pin_d = 4.0;
rest_proud = 0.5;
tip_r = 2.1;
tip_flat = 0.25;
foam_hole = 4.5;
foam_strip_w = col_pitch - 1;                                  // 11
z_guide_top = -(face_t + foam_t + collar_h);                   // -11.2
z_guide_bot = z_guide_top - guide_t;                           // -17.2
z_rod = z_guide_bot - cam_max_r - guide_gap;                   // -23.35, shaft axis
foot_rest = z_rod + cam_base_r + foot_clear;                   // -20.45, pin foot tip, pin down
pin_len = rest_proud - foot_rest;                              // 20.95
collar_z = z_guide_top - foot_rest;                            // 9.25, collar underside from the foot tip

// ---------------------------------------------------------------- chassis
wall = 2.0;
floor_t = 1.6;
cam_gap = 0.8;
z_floor_top = z_rod - cam_max_r - cam_gap;                     // -29.6
servo_body_bot = z_rod - servo_shaft_off;                      // -28.15
z_bottom = min(z_floor_top - floor_t, servo_body_bot - 0.8);   // -31.2
bulk_y = [servo_tab_y + servo_tab_t / 2, -0.5];                // [-7.0, -0.5]
wrist_in_y = servo_back_y - servo_slide - 1.0;                 // -25.5
wrist_t = 5.0;
wrist_out_y = wrist_in_y - wrist_t;                            // -30.5
far_in_y = y_row0 + 3 * row_pitch + lobe_w / 2 + 1.0;          // 57.0
far_t = 5.0;
far_out_y = far_in_y + far_t;                                  // 62.0
far_pocket = 3.5;
ledge = 1.5;
corner_r = 9;
bottom_chamfer = 3;
screw_pilot = 2.6;
screw_clear = 3.4;
screw_cb_d = 6.2;
screw_cb_h = 2.0;
screw_in = 3.0;
strap_w = 27;
lead_slot_w = 36;
lead_slot_h = 9;
lead_tie = true;
face_crown = 3.0;
finger_round = 3.0;
ridge_h = 0.8;
finger_scallops = 0;        // carried from the spec; 0 = none, no geometry
function half_w(n = cols) = col_x(n - 1, n) + cam_max_r + cam_gap + wall;   // 44.25 for n = 7
crown_yc = y_row0 + 1.5 * row_pitch;                           // 34.0
crown_R = (pow(half_w(), 2) + pow(max(far_out_y - crown_yc, crown_yc - wrist_out_y), 2))
          / (2 * face_crown);                                  // 1019.7
function crown_z(x, y) = cols < 3 ? 0
    : face_crown - (crown_R - sqrt(crown_R * crown_R - x * x - (y - crown_yc) * (y - crown_yc)));
screw_pts = [for (sx = [-1, 1], y = [(wrist_out_y + wrist_in_y) / 2, (far_in_y + far_out_y) / 2])
             [sx * (half_w() - screw_in), y]];                 // x +-41.25, y -28 and 59.5
pin_sprue_t = 1.0;
face_notch_r = 2.2;

// ---------------------------------------------------------------- forearm pack
bb_l = 82.5;  bb_w = 54.5;  bb_h = 8.5;       // half-size breadboard
adp_l = 30;   adp_w = 14.5; adp_h = 15;       // barrel-jack screw-terminal adapter
pack_fit = 0.6;
pack_wall = 2.0;
pack_floor = 2.0;
pack_rim = 14;
pack_loop_w = 27;
pack_loop_gap = 3.5;
pack_loop_t = 2.5;
pack_in_l = bb_l + 2 * pack_fit + adp_w + 2 * pack_fit + pack_wall;   // 101.4
pack_in_w = bb_w + 2 * pack_fit;                                       // 55.7
pack_out_l = pack_in_l + 2 * pack_wall;                                // 105.4
pack_out_w = pack_in_w + 2 * pack_wall;                                // 59.7
pack_gap_y = 18;
pack_y1 = wrist_out_y - pack_gap_y;                                    // -48.5
pack_y0 = pack_y1 - pack_out_l;                                        // -153.9
pack_z0 = z_bottom;                                                    // -31.2
lead_slot_pack = [26, 10];

// ---------------------------------------------------------------- resolution
$fa = 4;
$fs = 0.25;
crown_fn = 900;

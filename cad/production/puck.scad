// Pin Puck production CAD. Export one part:
//   openscad --backend Manifold -D 'part="chassis"' -o chassis.stl puck.scad
// Deliverables: chassis, guide, face, shaft, shaft3, pins, foam_template, pack_tray.
// Also: assembly (puck frame, -D angle=...), derived (echo only), and the x_* intersection
// checks used by verify.py (-D angle=..., variant=3|4, offset=...).
include <lib.scad>

part = is_undef(part) ? "assembly" : part;
angle = is_undef(angle) ? 0 : angle;
variant = is_undef(variant) ? 4 : variant;
offset = is_undef(offset) ? 0 : offset;

module chassis_print() translate([0, 0, -z_bottom]) chassis();
module guide_plate_print() translate([0, 0, -z_guide_bot]) guide_plate();
module face_plate_print() translate([0, 0, face_t]) face_plate();
module shaft_print(v = 4) translate([0, 0, -coupling_y0]) shaft(v);
module foam_template_print() translate([0, -(row_y(0) - 5), 0]) foam_template();
module pack_tray_print() translate([0, -pack_y0, -pack_z0]) pack_tray();

module shafts(a, v, cs = [0 : cols - 1]) for (c = cs) shaft_in_puck(c, a, v);
module servos(cs = [0 : cols - 1]) for (c = cs) servo_body(c);
evens = [for (c = [0 : 2 : cols - 1]) c];
odds = [for (c = [1 : 2 : cols - 1]) c];

// Lobe row r is raised when the servo angle a sits within the flat of its band.
function lobe_angle(v, r) = v == 3
    ? let(i = search(r, shaft3_rows)) (len(i) ? shaft3_angles[i[0]] : undef)
    : band_angle[r];
function pin_raise(v, r, a) = let(b = lobe_angle(v, r)) is_undef(b) ? 0
    : max(0, lift * lobe_s(a - b, v == 3 ? shaft3_flat : cam_flat, v == 3 ? shaft3_ramp : cam_ramp) - foot_clear);

module assembly(a = angle, v = variant) {
    color([0.15, 0.16, 0.18]) chassis();
    color("lightblue", 0.6) guide_plate();
    color("lightcyan", 0.35) face_plate();
    color([1, 0.6, 0.2]) shafts(a, v);
    color("royalblue") servos();
    for (c = [0 : cols - 1], r = [0 : rows - 1])
        color("black") translate([col_x(c), row_y(r), foot_rest + pin_raise(v, r, a)]) pin(pin_L(c, r));
    color([0.3, 0.3, 0.32]) pack_tray();
}

module derived() {
    vals = [["z_guide_top", z_guide_top], ["z_guide_bot", z_guide_bot], ["z_rod", z_rod],
            ["foot_rest", foot_rest], ["pin_len", pin_len], ["collar_z", collar_z],
            ["z_floor_top", z_floor_top], ["servo_body_bot", servo_body_bot], ["z_bottom", z_bottom],
            ["servo_tab_y", servo_tab_y], ["bulk_y0", bulk_y[0]], ["bulk_y1", bulk_y[1]],
            ["wrist_in_y", wrist_in_y], ["wrist_out_y", wrist_out_y], ["far_in_y", far_in_y],
            ["far_out_y", far_out_y], ["half_w", half_w()], ["crown_yc", crown_yc], ["crown_R", crown_R],
            ["screw_x", screw_pts[2][0]], ["screw_y0", screw_pts[0][1]], ["screw_y1", screw_pts[1][1]],
            ["lift", lift], ["cam_max_r", cam_max_r], ["gap0", gap_angle(0)], ["gap1", gap_angle(1)],
            ["gap2", gap_angle(2)], ["pack_in_l", pack_in_l], ["pack_in_w", pack_in_w],
            ["pack_out_l", pack_out_l], ["pack_out_w", pack_out_w], ["pack_y1", pack_y1], ["pack_y0", pack_y0],
            ["foam_strip_w", foam_strip_w]];
    for (v = vals) echo(str("DERIVED ", v[0], " ", v[1]));
}

if (part == "chassis") chassis_print();
else if (part == "guide") guide_plate_print();
else if (part == "face") face_plate_print();
else if (part == "shaft") shaft_print(4);
else if (part == "shaft3") shaft_print(3);
else if (part == "pins") pins_plate_puck();
else if (part == "foam_template") foam_template_print();
else if (part == "pack_tray") pack_tray_print();
else if (part == "assembly") assembly();
else if (part == "derived") { derived(); cube(1); }
// Collision checks, puck frame. Every intersection must be empty.
else if (part == "x_shaft_chassis") intersection() { shafts(angle, variant); chassis(); }
else if (part == "x_shaft_servo") intersection() { shafts(angle, variant); servos(); }
else if (part == "x_shaft_guide") intersection() { shafts(angle, variant); guide_plate(); }
else if (part == "x_shaft_shaft") intersection() { shafts(angle, variant, evens); shafts(angle, variant, odds); }
else if (part == "x_servo_chassis") intersection() { servos(); chassis(); }
else if (part == "x_servo_guide") intersection() { servos(); guide_plate(); }
else if (part == "x_servo_servo") intersection() { servos(evens); servos(odds); }
// Horn insertion check, shaft frame: horn backed out by offset along -Z.
else if (part == "x_horn") intersection() { shaft(variant); translate([0, 0, -offset]) horn(); }
else assert(false, str("Unknown part: ", part));

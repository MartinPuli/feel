// Pin Puck production CAD: one module per part, construction order from CAD.md section 3.
// Where a solid is unioned onto existing solid, it reaches 0.01 into it so the union is
// one body; those overlaps sit inside material and do not change the outer geometry.
include <params.scad>

// ---------------------------------------------------------------- helpers
// 2-D rectangle w wide (centred on x), running y = 0 ... l, corner radius r.
module rrect(w, l, r) {
    hull() for (x = [-w / 2 + r, w / 2 - r], y = [r, l - r]) translate([x, y]) circle(r = r);
}
// Cylinder of radius r along +y of length l, plus a box 2r wide, l long, h tall above it.
module uslot(r, l, h = 40) {
    rotate([-90, 0, 0]) cylinder(r = r, h = l);
    translate([-r, 0, 0]) cube([2 * r, l, h]);
}
// Axis-aligned box from ranges.
module bx(xr, yr, zr) {
    translate([xr[0], yr[0], zr[0]]) cube([xr[1] - xr[0], yr[1] - yr[0], zr[1] - zr[0]]);
}
// Shaft frame -> puck frame: (X, Y, Z) -> (-X + col_x, Z, Y + z_rod).
module in_puck(c) {
    multmatrix([[-1, 0, 0, col_x(c)], [0, 0, 1, 0], [0, 1, 0, z_rod], [0, 0, 0, 1]]) children();
}

// ---------------------------------------------------------------- 3.1 chassis
module chassis() {
    hw = half_w();
    iw = hw - wall;
    L = far_out_y - wrist_out_y;
    ztop = -face_t;
    ym = (row_y(0) + row_y(3)) / 2;
    ey = strap_w + 4;
    difference() {
        union() {
            difference() {
                // 1. outer body with a 3 mm bottom chamfer
                hull() {
                    translate([0, wrist_out_y + bottom_chamfer, z_bottom])
                        linear_extrude(0.01)
                            rrect(2 * hw - 2 * bottom_chamfer, L - 2 * bottom_chamfer, corner_r - bottom_chamfer);
                    translate([0, wrist_out_y, z_bottom + bottom_chamfer])
                        linear_extrude(ztop - z_bottom - bottom_chamfer) rrect(2 * hw, L, corner_r);
                }
                // 2. cavity
                bx([-iw, iw], [wrist_in_y, far_in_y], [z_floor_top, ztop + 1]);
            }
            // 3. bulkhead
            bx([-iw - 0.01, iw + 0.01], bulk_y, [z_floor_top - 0.01, ztop]);
            // 4. front ledge
            bx([-iw - 0.01, iw + 0.01], [bulk_y[1] - 0.01, bulk_y[1] + 1.6], [z_guide_bot - ledge, z_guide_bot]);
            // 5. side ledges: 45 degree prisms, top at z_guide_bot, 1.5 inward
            for (m = [0, 1]) mirror([m, 0, 0])
                translate([0, far_in_y + 0.01, 0]) rotate([90, 0, 0])
                    linear_extrude(far_in_y + 0.01 - bulk_y[1])
                        polygon([[iw - ledge, z_guide_bot], [iw + 0.01, z_guide_bot],
                                 [iw + 0.01, z_guide_bot - ledge], [iw, z_guide_bot - ledge]]);
            // 6. strap ears
            for (m = [0, 1]) mirror([m, 0, 0]) difference() {
                hull() {
                    bx([hw - 0.5, hw + 6], [ym - ey / 2, ym + ey / 2], [-20, -12]);
                    bx([hw - 0.5, hw], [ym - ey / 2, ym + ey / 2], [-26.5, -25.5]);
                }
                bx([hw + 0.8, hw + 4.3], [ym - strap_w / 2, ym + strap_w / 2], [-40, 0]);
            }
        }
        for (c = [0 : cols - 1]) let(x = col_x(c)) {
            // 7. servo tunnel through the bulkhead (closed on top) and pocket behind it (open on top)
            bx([x - servo_w / 2 - servo_fit, x + servo_w / 2 + servo_fit],
               [bulk_y[0] - 0.1, bulk_y[1] + 1.8],
               [servo_body_bot - servo_fit, servo_body_bot - servo_fit + servo_len + 0.8]);
            bx([x - 5.2, x + 5.2], [wrist_in_y - 0.1, bulk_y[0] + 0.1],
               [servo_body_bot - servo_fit, servo_body_bot - servo_fit + 60]);
            // 8. far journal slot, blind, 1.5 mm skin outside
            translate([x, far_in_y - 0.1, z_rod]) uslot(farj_d / 2 + bearing_fit, far_pocket + 0.1);
        }
        // 9. screw pilots
        for (p = screw_pts) translate([p[0], p[1], ztop - 12]) cylinder(d = screw_pilot, h = 12.1);
        // 10. lead slot
        bx([-lead_slot_w / 2, lead_slot_w / 2], [wrist_out_y - 0.1, wrist_in_y + 0.1],
           [z_floor_top, z_floor_top + lead_slot_h]);
        // 11. zip-tie slots
        if (lead_tie) for (sx = [-1, 1])
            bx([sx * 10 - 1.5, sx * 10 + 1.5], [wrist_in_y + 1.5, wrist_in_y + 3.3],
               [z_bottom - 1, z_floor_top + 1]);
    }
}

// ---------------------------------------------------------------- 3.2 guide plate
module guide_plate() {
    gx = half_w() - wall - 0.2;
    difference() {
        bx([-gx, gx], [0.3, far_in_y - 0.2], [z_guide_bot, z_guide_top]);
        for (c = [0 : cols - 1], r = [0 : rows - 1])
            translate([col_x(c), row_y(r), z_guide_bot - 1]) cylinder(d = hole_d, h = guide_t + 2);
    }
}

// ---------------------------------------------------------------- 3.3 face plate
module face_plate() {
    hw = half_w();
    L = far_out_y - wrist_out_y;
    r = corner_r;
    cr = face_crown;
    yf = far_out_y - finger_round;
    big = face_t + cr + 4;
    difference() {
        union() {
            intersection() {
                // 1. blank with a 0.8 mm edge round
                hull() {
                    translate([0, wrist_out_y, -face_t]) linear_extrude(face_t + cr - 0.8) rrect(2 * hw, L, r);
                    translate([0, wrist_out_y + 0.8, -face_t])
                        linear_extrude(face_t + cr) rrect(2 * hw - 1.6, L - 1.6, r - 0.8);
                }
                // 2. crown dome: 3 mm at the pin field centre, z = 0 at the farthest corner
                translate([0, crown_yc, cr - crown_R]) sphere(r = crown_R, $fn = crown_fn);
                // 3. finger edge rounded with a 3 mm radius tangent to the top
                union() {
                    bx([-hw - 1, hw + 1], [wrist_out_y - 1, yf], [-face_t - 1, cr + 1]);
                    hull() {
                        translate([-hw - 1, yf, crown_z(0, yf) - finger_round])
                            rotate([0, 90, 0]) cylinder(r = finger_round, h = 2 * hw + 2);
                        bx([-hw - 1, hw + 1], [yf, far_out_y], [-face_t - 1, -face_t - 0.99]);
                    }
                }
            }
            // 4. ridge, a centre landmark on the wrist side
            hull() for (y = [y_row0 - 12.5, y_row0 - 7])
                translate([0, y, crown_z(0, y)]) scale([1, 1, ridge_h / 0.8]) sphere(r = 0.8);
        }
        // 5. pin holes
        for (c = [0 : cols - 1], rr = [0 : rows - 1])
            translate([col_x(c), row_y(rr), -face_t - 1]) cylinder(d = hole_d, h = big);
        // 6. ear pocket
        bx([-(hw - wall), hw - wall],
           [servo_tab_y - servo_tab_t / 2 - 0.3, servo_tab_y - servo_tab_t / 2 - 0.3 + servo_tab_t + 0.6],
           [-face_t - 1, -face_t + 1.5]);
        // 7. screw holes, counterbored from the local top surface
        for (p = screw_pts) {
            translate([p[0], p[1], -face_t - 1]) cylinder(d = screw_clear, h = big);
            translate([p[0], p[1], crown_z(p[0], p[1]) - screw_cb_h]) cylinder(d = screw_cb_d, h = screw_cb_h + 5);
        }
        // 8. finger-edge notch
        translate([0, far_out_y, -face_t - 1]) cylinder(r = face_notch_r, h = big);
    }
}

// ---------------------------------------------------------------- 3.4 shaft
module lobe_2d(flat, ramp) {
    polygon([for (t = [0 : cam_step : 360 - cam_step]) lobe_r(t, flat, ramp) * [-sin(t), cos(t)]]);
}
module lobe(row, ang, flat, ramp) {
    z0 = row_y(row) - lobe_w / 2;
    rotate([0, 0, -ang]) {
        translate([0, 0, z0]) linear_extrude(lobe_w) lobe_2d(flat, ramp);
        hull() {   // print chamfer under the lobe
            translate([0, 0, z0 - 0.01]) linear_extrude(0.01) lobe_2d(flat, ramp);
            translate([0, 0, z0 - cone_h]) linear_extrude(0.01) circle(r = core_r);
        }
    }
}
module coupling_pocket() {
    z0 = coupling_y0 - 0.01;
    h = horn_y1 - z0;
    translate([0, 0, z0]) cylinder(d = horn_hub_d + 2 * hub_fit, h = h);                    // hub bore 5.6
    translate([0, 0, z0]) linear_extrude(h) union() {                                     // arm channel, full depth
        square([2 * (horn_trim_r + arm_fit), horn_arm_w + 2 * arm_fit], center = true);
        circle(d = horn_hub_d + 2 * arm_fit);
    }
    translate([0, 0, horn_y1 - 0.01]) cylinder(d = horn_head_d, h = horn_head_h);          // screw-head recess
    bx([4.5, 6.5], [-(0.7 + arm_fit), 0.7 + arm_fit], [z0, horn_y1]);                       // keying notch, hand crank
    translate([0, 0, z0]) cylinder(d1 = 6.4, d2 = horn_hub_d + 2 * hub_fit, h = 0.4);       // entry chamfer
}
// variant 4: band_angle on rows 0..3, one ID dot. variant 3: shaft3, three dots.
// variant 44: shaft4, four lobes in 120 degrees, two dots.
module shaft(variant = 4) {
    three = variant == 3;
    four120 = variant == 44;
    lobes = three ? [for (i = [0 : len(shaft3_rows) - 1]) [shaft3_rows[i], shaft3_angles[i]]]
          : four120 ? [for (k = [0 : 3]) [k, shaft4_angles[k]]]
          : [for (k = [0 : len(band_angle) - 1]) [k, band_angle[k]]];
    flat = three ? shaft3_flat : four120 ? shaft4_flat : cam_flat;
    ramp = three ? shaft3_ramp : four120 ? shaft4_ramp : cam_ramp;
    nd = three ? 3 : four120 ? 2 : 1;
    zc = coupling_y0 + coupling_len - 0.01;                  // 7.19
    zj = far_in_y - 0.21;                                    // 56.79
    difference() {
        union() {
            translate([0, 0, coupling_y0]) cylinder(d = coupling_d, h = coupling_len);         // 1. coupling disc
            translate([0, 0, zc]) cylinder(r = core_r, h = far_in_y - 0.2 - zc);              // 2. core
            for (l = lobes) lobe(l[0], l[1], flat, ramp);                                     // 3. lobes
            translate([0, 0, zj]) cylinder(d = farj_d, h = far_in_y + far_pocket - 0.3 - zj); // 4. far journal
            for (i = [0 : nd - 1])                                                            // 5. ID dots
                rotate([0, 0, 180 + (i - (nd - 1) / 2) * 32]) translate([4.0, 0, 7.0]) sphere(r = 0.7);
        }
        coupling_pocket();                                                                    // 6.
        translate([0, coupling_d / 2, 0]) rotate([0, 0, 45])                                  // 7. band-1 groove
            translate([-0.65, -0.65, 0]) cube([1.3, 1.3, 9.2]);
    }
}

// ---------------------------------------------------------------- 3.5 pins
function pin_L(c, r) = pin_len + crown_z(col_x(c), row_y(r));
// Single pin, foot tip at the origin, length L.
module pin(L) {
    tip_h = max(tip_r, 2.2);
    zct = foot_tip_r - foot_tip_r / sin(foot_cone) + (pin_d / 2) / tan(foot_cone);   // 3.606
    intersection() {
        union() {
            hull() {                                                         // 1. foot
                translate([0, 0, foot_tip_r]) sphere(r = foot_tip_r);
                translate([0, 0, zct]) cylinder(d = pin_d, h = 0.01);
            }
            translate([0, 0, zct]) cylinder(d = pin_d, h = L - tip_h - zct);  // 2. shaft
            hull() {                                                         // 3. palm tip
                translate([0, 0, L - tip_h]) cylinder(d = pin_d, h = 0.01);
                translate([0, 0, L - tip_r]) sphere(r = tip_r);
            }
            translate([0, 0, collar_z]) cylinder(d = collar_d, h = collar_h); // 4. collar
        }
        translate([-10, -10, 0]) cube([20, 20, L - tip_flat]);               // 5. flat tip
        union() {
            cylinder(d = pin_d, h = L);
            translate([0, 0, collar_z]) cylinder(d = collar_d, h = collar_h);
        }
    }
}
// Inverted pin with its flattened tip on the sprue top.
module plate_pin(x, y, L) {
    translate([x, y, pin_sprue_t + L - tip_flat]) rotate([180, 0, 0]) pin(L);
}
module pins_plate_puck() {
    g = 9;
    n_spare = 8;
    translate([-4.5, -8.5, 0]) cube([63, 58, pin_sprue_t]);
    for (c = [0 : cols - 1], r = [0 : rows - 1]) plate_pin(c * g, r * g, pin_L(c, r));
    // Spares: column 3, rows 2 and 3 alternating, continuing the 7-per-row grid (row 4 full, row 5 slot 0).
    for (i = [0 : n_spare - 1]) let(j = cols * rows + i)
        plate_pin((j % 7) * g, floor(j / 7) * g, pin_L(3, i % 2 == 0 ? 2 : 3));
    for (c = [0 : cols - 1])
        translate([c * g, -6.7, pin_sprue_t - 0.01]) linear_extrude(0.61)
            text(str(c), size = 3, halign = "center", valign = "center");
    translate([3.5 * g, 5 * g, pin_sprue_t - 0.01]) linear_extrude(0.61)
        text("spares", size = 3, halign = "center", valign = "center");
}

// ---------------------------------------------------------------- 3.6 foam template
module foam_template() {
    y0 = row_y(0) - 5;
    difference() {
        bx([-foam_strip_w / 2, foam_strip_w / 2], [y0, y0 + 49], [0, 1.2]);
        for (r = [0 : rows - 1]) translate([0, row_y(r), -1]) cylinder(d = foam_hole, h = 3.2);
        translate([0, y0, -1]) cylinder(r = 1.5, h = 3.2);   // wrist-end mark
    }
}

// ---------------------------------------------------------------- 3.7 pack tray
module pack_loop(y) {
    x0 = pack_out_w / 2;
    difference() {
        bx([x0 - 0.01, x0 + pack_loop_gap + pack_loop_t], [y, y + pack_loop_w], [pack_z0, pack_z0 + 16]);
        bx([x0, x0 + pack_loop_gap], [y - 0.1, y + pack_loop_w + 0.1], [pack_z0 + 1.6, pack_z0 + 16 - 1.6]);
    }
}
module pack_tray() {
    zt = pack_floor + pack_rim;   // 16
    difference() {
        union() {
            translate([0, pack_y0, pack_z0]) linear_extrude(zt) rrect(pack_out_w, pack_out_l, 4);
            for (m = [0, 1], y = [pack_y0 + 14, pack_y1 - 14 - pack_loop_w]) mirror([m, 0, 0]) pack_loop(y);
        }
        // breadboard and adapter bays
        bx([-pack_in_w / 2, pack_in_w / 2], [pack_y0 + 2, pack_y0 + 2 + bb_l + 2 * pack_fit],
           [pack_z0 + pack_floor, pack_z0 + pack_floor + 40]);
        bx([-pack_in_w / 2, pack_in_w / 2], [pack_y1 - 2 - adp_w - 2 * pack_fit, pack_y1 - 2],
           [pack_z0 + pack_floor, pack_z0 + pack_floor + 40]);
        // lead notch toward the puck, barrel-cable notch at the far end
        bx([-lead_slot_pack[0] / 2, lead_slot_pack[0] / 2], [pack_y1 - 2.1, pack_y1 + 0.1],
           [pack_z0 + zt - lead_slot_pack[1], pack_z0 + zt - lead_slot_pack[1] + 11]);
        bx([-6, 6], [pack_y0 - 0.1, pack_y0 + 2.1], [pack_z0 + zt - 9, pack_z0 + zt - 9 + 10]);
        // zip-tie slots
        for (sx = [-1, 1]) let(ys = pack_y1 - 2 - adp_w / 2 - 2)
            bx([sx * 15 - 1.5, sx * 15 + 1.5], [ys, ys + 4], [pack_z0 - 1, pack_z0 + pack_floor + 1]);
        // drain holes
        for (x = [-15, 0, 15], i = [0 : 3])
            translate([x, pack_y0 + 14 + 17 * i, pack_z0 - 1]) cylinder(d = 8, h = pack_floor + 2);
    }
}

// ---------------------------------------------------------------- check models (not printed)
// Servo body for clearance checks, puck frame. The lower ear is clipped off in assembly.
module servo_body(c) {
    zb = servo_body_bot;
    translate([col_x(c), 0, 0]) {
        bx([-servo_w / 2, servo_w / 2], [servo_back_y, servo_back_y + servo_body_h], [zb, zb + servo_len]);
        translate([0, servo_back_y + servo_body_h, z_rod]) rotate([-90, 0, 0])
            cylinder(d = servo_tower_d, h = -(servo_back_y + servo_body_h));
        bx([-servo_w / 2, servo_w / 2], [servo_tab_y - servo_tab_t / 2, servo_tab_y + servo_tab_t / 2],
           [zb + 0.5, zb + servo_len / 2 + servo_tab_span / 2]);
    }
}
// Horn for the insertion check, shaft frame.
module horn() {
    translate([0, 0, horn_y0]) cylinder(d = horn_hub_d, h = horn_y1 - horn_y0);
    bx([0, horn_trim_r], [-horn_arm_w / 2, horn_arm_w / 2], [horn_y1 - horn_arm_t, horn_y1]);
    translate([0, 0, horn_y1]) cylinder(d = 4.2, h = 1.3);
}
module shaft_in_puck(c, a = 0, variant = 4) { in_puck(c) rotate([0, 0, a]) shaft(variant); }

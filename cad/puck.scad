include <lib.scad>
part = is_undef(part)?"assembly":part;

module body_blank() {
    hull() {
        linear_extrude(epsilon) rounded_rect(body_w-2*bottom_chamfer,body_l-2*bottom_chamfer,corner_r-bottom_chamfer);
        translate([0,0,bottom_chamfer]) linear_extrude(epsilon) rounded_rect(body_w,body_l,corner_r);
    }
    translate([0,0,bottom_chamfer-epsilon]) rounded_box(body_w,body_l,body_h-face_t-bottom_chamfer+epsilon,corner_r);
}
module strap_ears(y=5) {
    for(s=[-1,1]) difference() {
        translate([s*(body_w/2+(strap_span-body_w)/4-1),y,18]) rounded_box((strap_span-body_w)/2+2,strap_w+7,5,2.8);
        translate([s*(body_w/2+(strap_span-body_w)/4+0.2),y,17.9]) rounded_box(strap_slot,strap_w+0.6,5.2,0.9);
    }
}
module chassis() {
    difference() {
        union() {
            difference() {
                body_blank();
                translate([0,0,floor_h]) rounded_box(body_w-2*wall,body_l-2*wall,body_h+1,corner_r-wall);
                // Wrist exit, deliberately above floor to preserve bed and strain relief.
                translate([-16,-body_l/2-1,5]) cube([32,wall+3,12]);
                if(finger_scallops) for(x=[-24,0,24]) translate([x,body_l/2+2,body_h-10]) rotate([90,0,0]) cylinder(r=10,h=6,center=true);
            }
            strap_ears();
            if(second_strap) strap_ears(-25);
            for(c=[0:columns-1],y=bearing_y) lower_bearing(col_x(c),y);
            for(p=screw_positions()) {
                translate([p[0],p[1],floor_h-epsilon]) cylinder(r=3.5,h=guide_z-floor_h+epsilon);
                translate([p[0],p[1],guide_z-epsilon]) cylinder(r=2.4,h=body_h-face_t-guide_z+epsilon);
            }
            // Eight separators, seven servo bays, all still measurement-gated.
            for(i=[0:columns]) translate([col_x(0)-pitch/2+i*pitch-0.7,servo_face_y-servo_case_depth,floor_h-epsilon]) cube([1.4,servo_case_depth,9]);
        }
        for(p=screw_positions()) translate([p[0],p[1],body_h-face_t-11]) cylinder(d=screw_pilot_d,h=12);
        // Two pairs of floor slots allow two cable-bundle zip ties.
        for(x=[-10,10],y=[-39,-34]) translate([x-0.9,y-1.6,-epsilon]) cube([1.8,3.2,floor_h+2*epsilon]);
        // Each servo can be retained by its own tie during the first fit check.
        for(c=[0:columns-1],s=[-1,1]) translate([col_x(c)+s*5-0.65,-36,-epsilon]) cube([1.3,4,floor_h+2*epsilon]);
    }
}
module dome_cap() {
    // Radial sampling avoids the coarse pole tessellation of a very large sphere.
    if(dome_h>0) rotate_extrude($fn=128) polygon(concat(
        [[0,face_t-epsilon],[dome_radius,face_t-epsilon]],
        [for(i=[0:64]) let(r=dome_radius*(64-i)/64) [r,face_t+dome_at(r,0)]]));
}
module finger_rounding_mask() {
    // Exact sampled circular section, 3mm radius, on the finger-side top edge.
    pts=concat([[-body_l,0],[body_l/2,0]],
        [for(i=[0:16]) let(z=face_t*i/16,dy=sqrt(max(0,finger_edge_r* finger_edge_r-pow(z+finger_edge_r-face_t,2))))
            [body_l/2-finger_edge_r+dy,z]],
        [[-body_l,face_t]]);
    rotate([0,0,90]) rotate([90,0,0]) linear_extrude(body_w+2,center=true) polygon(pts);
}
module face() {
    difference() {
        union() {
            intersection() { rounded_box(body_w,body_l,face_t,corner_r); finger_rounding_mask(); }
            dome_cap();
            // Centre landmark on flat wrist edge, away from all active pin tips.
            for(i=[0:6]) hull() for(y=[-38+i,-37+i])
                translate([0,y,face_t+dome_at(0,y)-epsilon]) cylinder(r=0.4,h=0.8+epsilon);
        }
        for(c=[0:columns-1],r=[0:rows-1]) translate([col_x(c),row_y(r),-epsilon]) cylinder(d=hole_d,h=face_t+dome_h+1);
        // Different harmless polygon phases avoid collinear zero-area CGAL triangles
        // between identical aligned bores when exporting the flat underside.
        for(p=screw_positions()) translate([p[0],p[1],-epsilon]) rotate([0,0,1.23+p[1]*0.07]) cylinder(d=screw_d,h=face_t+dome_h+1);
        // Centre notch at finger edge, not a second raised pin.
        translate([-1,body_l/2-3,-epsilon]) cube([2,4,face_t+2*epsilon]);
    }
}
module guide_assembly() {
    difference() {
        union() {
            translate([0,(row_y(0)+row_y(3))/2,guide_z]) rounded_box(body_w-2*wall-0.6,58,guide_t,3);
            for(c=[0:columns-1],y=bearing_y) upper_bearing(col_x(c),y);
        }
        for(c=[0:columns-1],r=[0:rows-1]) translate([col_x(c),row_y(r),guide_z-epsilon]) cylinder(d=hole_d,h=guide_t+2*epsilon);
        for(p=screw_positions()) translate([p[0],p[1],guide_z-epsilon]) cylinder(d=5.2,h=guide_t+2*epsilon);
    }
}
module servo_retainer() {
    // Removable spacer comb between measured upper ears and face; no guessed spline.
    h=body_h-face_t-(shaft_axis_z+servo_axis_from_top+(servo_tab_span-servo_case_z)/2);
    assert(h>0,"Servo top ear exceeds face underside; change layout after measuring");
    translate([0,0,0]) rounded_box((columns-1)*pitch+servo_case_w,4,h,1);
}
if(part=="chassis") chassis();
else if(part=="face") face();
else if(part=="guide") translate([0,0,guide_z+guide_t]) rotate([180,0,0]) guide_assembly();
else if(part=="shaft_A") camshaft(0);
else if(part=="pins") pin_plate(columns,pin_tip_r,true);
else if(part=="foam_template") foam_template(columns);
else if(part=="servo_retainer") servo_retainer();
else if(part=="assembly") {
    angle=is_undef(angle)?58:angle;
    color([0.12,0.13,0.15]) chassis();
    color("lightblue",0.55) guide_assembly();
    color("lightcyan",0.35) translate([0,0,body_h-face_t]) face();
    for(c=[0:columns-1]) {
        color([1,0.65,0.2]) shaft_in_place(c,angle,0);
        color("royalblue") translate([col_x(c),0,0]) servo_nominal();
        for(r=[0:rows-1]) color("black") translate([col_x(c),row_y(r),shaft_axis_z+cam_base_r+(band_angles[r]==angle?stroke:0)]) pin(pin_length(c,r));
    }
} else assert(false,str("Unknown puck part: ",part));

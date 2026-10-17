include <lib.scad>
part = is_undef(part)?"assembly":part;

module frame() {
    difference() {
        union() {
            rounded_box(22,body_l,floor_h,4);
            for(y=bearing_y) lower_bearing(0,y);
            for(x=[-7.5,7.5],y=[screw_y[0],screw_y[3]]) translate([x,y,floor_h-epsilon]) cylinder(r=2.8,h=body_h-face_t-floor_h+epsilon);
            // Side rails locate the nominal dummy/servo; final fit needs measurements.
            for(x=[-servo_case_w/2-1.6,servo_case_w/2+fit_clearance]) translate([x,servo_face_y-servo_case_depth,floor_h-epsilon]) cube([1.6,servo_case_depth,8]);
        }
        for(x=[-7.5,7.5],y=[screw_y[0],screw_y[3]]) translate([x,y,body_h-face_t-11]) cylinder(d=screw_pilot_d,h=12);
        for(x=[-5.5,5.5]) translate([x-0.8,-39,-epsilon]) cube([1.6,8,floor_h+2*epsilon]);
    }
}
module guide_assembly() {
    difference() {
        union() {
            translate([0,(row_y(0)+row_y(3))/2,guide_z]) rounded_box(22,60,guide_t,3);
            for(y=bearing_y) upper_bearing(0,y);
        }
        for(r=[0:rows-1]) translate([0,row_y(r),guide_z-epsilon]) cylinder(d=hole_d,h=guide_t+2*epsilon);
        for(x=[-7.5,7.5],y=[screw_y[0],screw_y[3]]) translate([x,y,guide_z-epsilon]) cylinder(d=6,h=guide_t+2*epsilon);
    }
}
module strip() {
    difference() {
        translate([0,(row_y(0)+row_y(3))/2,0]) rounded_box(22,60,face_t,3);
        for(r=[0:rows-1]) translate([0,row_y(r),-epsilon]) cylinder(d=hole_d,h=face_t+2*epsilon);
        for(x=[-7.5,7.5],y=[screw_y[0],screw_y[3]]) translate([x,y,-epsilon]) cylinder(d=screw_d,h=face_t+2*epsilon);
    }
}
module crank() {
    difference() {
        union() {
            cylinder(d=10,h=7);
            hull() { cylinder(d=8,h=3); translate([22,0,0]) cylinder(d=8,h=3); }
            translate([22,0,2.9]) cylinder(d=5,h=12);
        }
        translate([0,0,-epsilon]) d_shaft(7+2*epsilon,fit_clearance);
    }
}
module hole_coupon() {
    difference() {
        rounded_box(61,17,5,3);
        for(i=[0:5]) translate([-25+i*10,0,-epsilon]) cylinder(d=4.1+i*0.1,h=5+2*epsilon);
        for(i=[0:5]) translate([-25+i*10,-6.8,4.5]) linear_extrude(0.6) text(str(4.1+i*0.1),size=2,halign="center");
    }
}
module pitch_coupon() {
    union() {
        rounded_box(50,30,2,3);
        for(p=[11,12],i=[0:3]) translate([(i-1.5)*p,p==11?-6:6,1.9]) cylinder(d=pin_d,h=2.1);
    }
}
if(part=="frame") frame();
else if(part=="guide") translate([0,0,guide_z+guide_t]) rotate([180,0,0]) guide_assembly();
else if(part=="strip") strip();
else if(part=="shaft_A") camshaft(0);
else if(part=="shaft_H") camshaft(1);
else if(part=="shaft_G") camshaft(2);
else if(part=="pins_tip21") pin_plate(1,2.1,false);
else if(part=="pins_tip15") pin_plate(1,1.5,false);
else if(part=="crank") crank();
else if(part=="dummy_servo") translate([0,0,-(shaft_axis_z-servo_case_z+servo_axis_from_top)]) servo_nominal();
else if(part=="foam_template") foam_template(1);
else if(part=="hole_coupon") hole_coupon();
else if(part=="pitch_coupon") pitch_coupon();
else if(part=="coupling_C1") coupling(1);
else if(part=="coupling_C2") coupling(2);
else if(part=="coupling_C3") coupling(3);
else if(part=="assembly") {
    color("dimgray") frame();
    color("lightblue",0.7) guide_assembly();
    color("lightblue",0.5) translate([0,0,body_h-face_t]) strip();
    color("orange") shaft_in_place(3,band_angles[1],0);
    for(r=[0:rows-1]) color("black") translate([0,row_y(r),shaft_axis_z+cam_base_r+(r==1?stroke:0)]) pin(pin_length(3,r,false));
    color("blue") servo_nominal();
} else assert(false,str("Unknown test part: ",part));

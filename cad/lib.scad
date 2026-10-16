include <params.scad>

module rounded_rect(w,l,r) {
    assert(w>2*r && l>2*r);
    hull() for(x=[-w/2+r,w/2-r],y=[-l/2+r,l/2-r]) translate([x,y]) circle(r=r);
}
module rounded_box(w,l,h,r=3) { linear_extrude(h) rounded_rect(w,l,r); }
module bore_y(d,length) { rotate([90,0,0]) cylinder(d=d,h=length,center=true); }
module d_shaft(h,clearance=0) {
    intersection() {
        cylinder(d=shaft_d+clearance,h=h);
        translate([-shaft_d,-shaft_d,-epsilon]) cube([shaft_d+shaft_flat+clearance/2,2*shaft_d,h+2*epsilon]);
    }
}
module camshaft(variant=0) {
    assert(2*(cam_base_r+stroke)<pitch,"Adjacent nominal cam envelopes overlap");
    union() {
        cylinder(d=shaft_d,h=shaft_length-coupling_shaft_depth);
        translate([0,0,shaft_length-coupling_shaft_depth-epsilon]) d_shaft(coupling_shaft_depth+epsilon);
        for(r=[0:rows-1]) translate([0,0,shaft_origin_y-row_y(r)-cam_t/2])
            linear_extrude(cam_t) polygon(cam_points(r,variant));
    }
}
module shaft_in_place(c=0,angle=0,variant=0) {
    translate([col_x(c),shaft_origin_y,shaft_axis_z]) rotate([0,angle,0]) rotate([90,0,0]) camshaft(variant);
}
module pin(len=12.2,tip_r=pin_tip_r) {
    cone_h=(pin_d-pin_foot_tip_d)/2/tan(pin_cone_half_angle);
    assert(len>cone_h+tip_r+1);
    union() {
        cylinder(d1=pin_foot_tip_d,d2=pin_d,h=cone_h);
        translate([0,0,cone_h-epsilon]) cylinder(d=pin_d,h=len-tip_r-cone_h+epsilon-0.6);
        translate([0,0,len-tip_r-0.6-epsilon]) cylinder(d1=pin_d,d2=2*tip_r,h=0.6+2*epsilon);
        translate([0,0,len-tip_r]) intersection() {
            sphere(r=tip_r);
            translate([-tip_r,-tip_r,-epsilon]) cube([2*tip_r,2*tip_r,tip_r+epsilon]);
        }
        translate([0,0,pin_collar_z]) cylinder(d=pin_collar_d,h=pin_collar_h);
    }
}
module pin_plate(nc=7,tip_r=pin_tip_r,domed=true) {
    plate_w=(nc-1)*pitch+10;
    ymid=(row_y(0)+row_y(rows-1))/2;
    // Breakaway frame, runners and foot tabs keep every pin one connected mesh.
    difference() {
        translate([0,ymid,0]) rounded_box(plate_w,rows*pitch+6,1,2);
        translate([0,ymid,-epsilon]) rounded_box(plate_w-3,rows*pitch+3,1+2*epsilon,1);
    }
    for(c=[0:nc-1]) {
        x=(c-(nc-1)/2)*pitch;
        translate([x,row_y(rows-1)+8.2,0.85]) linear_extrude(0.45)
            text(nc==1?"TEST":str("C",c),size=1.5,halign="center",valign="center");
        translate([x+3.2,row_y(0)-8,0]) cube([1.4,(rows-1)*pitch+16,1]);
        for(r=[0:rows-1]) {
            translate([x,row_y(r),0]) pin(domed ? pin_length(c,r,true) : pin_length(3,r,false),tip_r);
            translate([x,row_y(r)-0.35,0.35]) cube([3.8,0.7,0.45]);
        }
    }
}
module lower_bearing(x,y) {
    difference() {
        translate([x-4.2,y-bearing_t/2,floor_h-epsilon]) cube([8.4,bearing_t,shaft_axis_z-floor_h+epsilon]);
        translate([x,y,shaft_axis_z]) bore_y(shaft_d+bearing_clearance,bearing_t+2*epsilon);
    }
}
module upper_bearing(x,y) {
    difference() {
        translate([x-4.2,y-bearing_t/2,shaft_axis_z]) cube([8.4,bearing_t,guide_z-shaft_axis_z+epsilon]);
        translate([x,y,shaft_axis_z]) bore_y(shaft_d+bearing_clearance,bearing_t+2*epsilon);
    }
}
module servo_nominal() {
    bottom=shaft_axis_z-(servo_case_z-servo_axis_from_top);
    translate([-servo_case_w/2,servo_face_y-servo_case_depth,bottom]) cube([servo_case_w,servo_case_depth,servo_case_z]);
    translate([-servo_case_w/2,servo_face_y-servo_tab_from_face-servo_tab_t,bottom+servo_case_z]) cube([servo_case_w,servo_tab_t,(servo_tab_span-servo_case_z)/2]);
    if(keep_lower_tab) translate([-servo_case_w/2,servo_face_y-servo_tab_from_face-servo_tab_t,bottom-(servo_tab_span-servo_case_z)/2]) cube([servo_case_w,servo_tab_t,(servo_tab_span-servo_case_z)/2]);
    translate([0,servo_face_y+servo_spline_h/2,shaft_axis_z]) bore_y(servo_spline_d,servo_spline_h+epsilon);
}
module coupling(kind=1) {
    clear=fit_clearance+(kind==2?0.2:0);
    difference() {
        cylinder(d=coupling_d,h=coupling_h);
        // Bed side mates to the D-shaft; top side captures a measured horn.
        translate([0,0,-epsilon]) d_shaft(coupling_shaft_depth+epsilon,clear);
        if(kind<3) {
            translate([0,0,coupling_h-horn_hub_h]) cylinder(d=horn_hub_d+clear,h=horn_hub_h+epsilon);
            translate([-coupling_d/2-epsilon,-(horn_arm_w+clear)/2,coupling_h-horn_arm_t]) cube([coupling_d+2*epsilon,horn_arm_w+clear,horn_arm_t+epsilon]);
            // Two tie holes hold a real horn arm; the supplied centre screw stays accessible.
            for(x=[-horn_hole_radius-0.4,horn_hole_radius+0.4]) translate([x,0,coupling_h-horn_hub_h-0.4]) cylinder(d=1.2,h=horn_hub_h+1);
        } else {
            // SIZING COUPON ONLY: smooth nominal bore, NOT a reproduced 20T spline.
            translate([0,0,coupling_h-servo_spline_h]) cylinder(d=servo_spline_d+clear,h=servo_spline_h+epsilon);
        }
        translate([0,0,-epsilon]) cylinder(d=1.6,h=coupling_h+2*epsilon);
    }
}
module foam_template(nc=7) {
    w=nc==1?9:(columns-1)*pitch+9;
    difference() {
        translate([0,(row_y(0)+row_y(rows-1))/2,0]) rounded_box(w,rows*pitch+1,1.2,1.5);
        for(c=[0:nc-1],r=[0:rows-1]) translate([(c-(nc-1)/2)*pitch,row_y(r),-epsilon]) cylinder(d=hole_d,h=1.2+2*epsilon);
        if(nc>1) for(c=[0:columns-2]) translate([col_x(c)+pitch/2-0.25,row_y(0)-3,0.6]) cube([0.5,(rows-1)*pitch+6,0.7]);
    }
}

include <../lib.scad>
function inside_rounded(x,y,w,l,r) = pow(max(abs(x)-(w/2-r),0),2)+pow(max(abs(y)-(l/2-r),0),2) <= r*r;
servo_bottom = shaft_axis_z-servo_case_z+servo_axis_from_top;
cone_h = (pin_d-pin_foot_tip_d)/2/tan(pin_cone_half_angle);
assert(servo_bottom>=floor_h-epsilon,"Nominal servo intersects floor");
assert(servo_bottom+servo_case_z<body_h-face_t,"Nominal servo intersects face");
for(c=[0:columns-1],sx=[-1,1],y=[servo_face_y-servo_case_depth,servo_face_y])
    assert(inside_rounded(col_x(c)+sx*servo_case_w/2,y,body_w-2*wall,body_l-2*wall,corner_r-wall),"Nominal servo envelope intersects inner side wall");
assert(shaft_axis_z+cam_base_r+stroke+cone_h<guide_z,"Raised pin cone enters straight guide");
assert(shaft_axis_z+cam_base_r+pin_collar_z>guide_z+guide_t,"Pin collar intersects lower guide");
assert(shaft_axis_z+cam_base_r+pin_collar_z+pin_collar_h+stroke<body_h-face_t,"Raised collar hits face underside");
assert(2*(cam_base_r+stroke)<pitch,"Nominal adjacent shaft cam envelopes overlap");
echo(["NOMINAL_FIT","passed", "actual servo/horn fit NOT VERIFIED"]);
echo(["PIN_CONE_CLEARANCE",guide_z-(shaft_axis_z+cam_base_r+stroke+cone_h)]);
echo(["PIN_FOAM_SPACES",body_h-face_t-(shaft_axis_z+cam_base_r+pin_collar_z+pin_collar_h),body_h-face_t-(shaft_axis_z+cam_base_r+pin_collar_z+pin_collar_h+stroke)]);
for(c=[0:columns-1],r=[0:rows-1]) echo(["PIN",c,r+1,col_x(c),row_y(r),pin_length(c,r),body_h+dome_at(col_x(c),row_y(r))+rest_proud+stroke]);
cube(1);

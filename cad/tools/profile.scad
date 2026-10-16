// Emit precisely the polygon vertices the STL generator uses.
include <../lib.scad>
echo(["PARAMETERS",band_angles,gap_angles,tap_degrees,cam_base_r,stroke,pin_d/2,pin_foot_tip_d/2,pin_cone_half_angle,pitch,cam_step]);
for(v=[0:2],b=[0:3]) echo(["PROFILE",v,b,cam_points(b,v)]);
cube([1,1,1]);

// Exploded inspection view only; this is not a printable assembled STL.
use <puck.scad>
use <pack.scad>
include <params.scad>
explode=is_undef(explode)?0:explode;
color([0.12,0.13,0.15]) chassis();
color("lightblue",0.65) translate([0,0,explode]) guide_assembly();
color("lightcyan",0.5) translate([0,0,body_h-face_t+2*explode]) face();
for(c=[0:columns-1]) color("orange") shaft_in_place(c,58,0);
translate([115,0,0]) color("gray") pack_tray();

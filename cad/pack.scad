include <lib.scad>
part = is_undef(part)?"pack_tray":part;
module pack_tray() {
    difference() {
        union() {
            difference() {
                rounded_box(pack_w,pack_l,pack_h,7);
                translate([0,0,pack_floor]) rounded_box(pack_w-5,pack_l-5,pack_h+1,4.5);
            }
            // Board adhesive rests on the floor; these four shallow stops locate it.
            for(s=[-1,1],y=[-40,26]) translate([s*(pack_breadboard_w/2+1+fit_clearance)-1,y,pack_floor-epsilon]) cube([2,7,3]);
            translate([-pack_w/2+2.5,33,pack_floor-epsilon]) cube([pack_w-5,2,5]);
            translate([2,34,pack_floor-epsilon]) cube([2,pack_adapter_l+1,5]);
            for(s=[-1,1],y=[-34,34]) translate([s*(pack_w/2+2),y,0]) rounded_box(9,strap_w+7,5,2);
        }
        for(s=[-1,1],y=[-34,34]) translate([s*(pack_w/2+2.7),y,-epsilon]) rounded_box(strap_slot,strap_w+0.6,5+2*epsilon,0.8);
        translate([-14,-pack_l/2-1,pack_floor+1]) cube([28,5,6]);
        for(x=[-19,19],y=[40,47]) translate([x-1,y-1.5,-epsilon]) cube([2,3,pack_floor+2*epsilon]);
    }
}
assert(part=="pack_tray",str("Unknown pack part: ",part));
pack_tray();

// FEEL greenfield V1 — millimetres/degrees. NOT recovered original CAD.
// All hardware fit values are UNMEASURED. See README before printing.
measurements_confirmed = false;
horn_fit_confirmed = false;
$fn = 48;
epsilon = 0.02;
columns = 7;
rows = 4;
pitch = 12;
row_y0 = -8;                  // New layout assumption: room for wrist-side servos.
body_w = 88.6;
body_l = 88.8;
body_h = 35;
corner_r = 9;
bottom_chamfer = 3;
finger_edge_r = 3;
wall = 2.5;
floor_h = 2.5;
face_t = 2.5;
dome_h = 3;
dome_radius = 43.5;           // Spherical cap footprint; corners remain flat.
strap_span = 101;
strap_w = 25;
strap_slot = 2.5;
second_strap = false;         // v7 prose said off, despite showing true in its table.
finger_scallops = false;
keep_lower_tab = false;
hole_d = 4.366;               // Nominal 11/64 inch FINISHED hole, not printer proof.
pin_d = 4.2;
pin_tip_r = 2.1;
pin_foot_tip_d = 0.6;
pin_cone_half_angle = 30;     // Assumption: 30 degrees from axis (60 included).
pin_collar_d = 6;
pin_collar_h = 0.5;
pin_collar_z = 6.7;           // From low pin foot; gives 4→2mm foam cavity.
rest_proud = -1.5;
stroke = 2;
band_angles = [0, 58, 117, 175];
gap_angles = [29, 87.5, 146];
tap_degrees = 13;
cam_base_r = 3.8;
cam_half_width = 12;         // Retained 12-degree flank and 13-degree tap; physical force/travel unverified.
cam_exponents = [2.2, 2.5, 1.6]; // A / H (flatter crest) / G (lower flank slope).
cam_step = 1;                // Actual polygon resolution, also used by cam_sim.
cam_t = 3;
shaft_d = 3;
shaft_flat = 1.0;            // D flat plane X=+1mm, shaft radius 1.5mm.
shaft_length = 58;
shaft_origin_y = 38;
shaft_axis_z = 17.5;
bearing_clearance = 0.35;
bearing_y = [-13, 35];
bearing_t = 3;
guide_z = 26.7;
guide_t = 1.2;               // New thin-guide assumption; stiffness unverified.
screw_d = 3.3;
screw_pilot_d = 2.7;
screw_x = 40.5;
screw_y = [-14, -2, 10, 34];
foam_h = 5;                 // Two 3+2mm strips are a TEST; preload is unverified.
servo_case_w = 8.3;         // Overall manufacturer B; measure actual case.
servo_case_z = 20;          // Overall manufacturer A, oriented upright.
servo_case_depth = 13.3;    // UNMEASURED case alone; published C=17.3 includes shaft.
servo_face_y = -25;
servo_axis_from_top = 5;    // UNMEASURED
servo_tab_span = 26;        // UNMEASURED
servo_tab_t = 1.5;          // UNMEASURED
servo_tab_from_face = 1.5;  // UNMEASURED
servo_spline_d = 3.8;       // UNMEASURED — do not force a printed spline.
servo_spline_h = 2.5;       // UNMEASURED
servo_spline_teeth = 20;    // Manufacturer spec; tooth shape remains unmeasured.
fit_clearance = 0.3;
horn_hub_d = 4.7;           // UNMEASURED
horn_hub_h = 2.2;           // UNMEASURED
horn_arm_w = 3.2;           // UNMEASURED
horn_arm_t = 1.2;           // UNMEASURED
horn_hole_radius = 3.2;     // UNMEASURED
coupling_d = 10;
coupling_h = 7;
coupling_shaft_depth = 4;
pack_breadboard_w = 55;     // UNMEASURED 400-point board envelope.
pack_breadboard_l = 82;
pack_w = 68;
pack_l = 112;
pack_h = 13;
pack_floor = 3;
pack_adapter_w = 22;        // UNMEASURED
pack_adapter_l = 15;
pack_cap_d = 14;            // UNMEASURED

function col_x(c) = (c - (columns-1)/2)*pitch;
function row_y(r) = row_y0 + r*pitch;
function dome_R() = (dome_radius*dome_radius+dome_h*dome_h)/(2*dome_h);
function dome_at(x,y) = dome_h <= 0 || x*x+y*y >= dome_radius*dome_radius ? 0 :
    sqrt(dome_R()*dome_R()-x*x-y*y) - (dome_R()-dome_h);
function pin_length(c,r,domed=true) = body_h + rest_proud +
    (domed ? dome_at(col_x(c),row_y(r)) : 0) - (shaft_axis_z+cam_base_r);
function angular_distance(a,b) = abs(((a-b+540)%360)-180);
function cam_radius(theta,band,variant=0) = cam_base_r + stroke *
    max(0,1-pow(angular_distance(theta,90+band_angles[band])/cam_half_width,cam_exponents[variant]));
function cam_points(band,variant=0) = [for(a=[0:cam_step:360-cam_step])
    [cam_radius(a,band,variant)*cos(a),cam_radius(a,band,variant)*sin(a)]];
function screw_positions() = [for(x=[-screw_x,screw_x],y=screw_y) [x,y]];

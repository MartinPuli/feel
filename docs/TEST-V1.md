# Test V1 from main

`main` contains V1. Spatial Memory (V2) remains on its separate branch.
Software checks passed locally; hosted CI is blocked by GitHub account billing.
See [release evidence](evidence/v1-release/report.json). This does not certify
physical readiness of the complete seven-column device.

## Existing one-servo setup

Keep the tested wiring intact, the servo unloaded, the ESP32 powered by USB and
the servo on its separate compatible supply. Do not change wiring while powered.
The previously installed board firmware is the limited single-servo demo; pushing
main does not update the board or the installed iPhone app.

1. Open FEEL on the iPhone. Under **Puck connection**, use **Scan for puck** and
   connect **FEEL Center Demo** (the cached name may be FEEL Puck). Confirm connected.
2. Tap **Live sensing**. Hold the phone in landscape-left with the rear camera
   forward and its top edge to your left. Measure lens height from the floor,
   set **Camera height**, then tap **Calibrate floor**. Wait for valid tracking.
3. Point the center of the camera at a large box or a person in the waist-to-head
   sensing region. Test distances around2 m,1.2 m and0.5 m. Keep the object in
   the middle and wait about a second at each distance.
4. Expect a small change between servo positions. The center sector alone drives
   GPIO32 in this demo. Remaining in one distance band holds one position;
   this is not continuous rotation. Simulation does not move hardware.
5. Tap **Stop**, then change the object distance. The servo should no longer
   follow it. The shaft need not visibly return to center: Stop detaches PWM.
6. Restart Live sensing and confirm movement returns. Then disconnect Bluetooth
   from the app and check that it stops following changes. Software tests check
   the500 ms timeout; visual observation cannot measure that latency precisely.

Record each result as observed PASS, FAIL or NOT TESTED. Report connection state,
app tracking status, center band, object distance, movement and Stop behavior.
If there is sustained buzzing, a jam, heat or unexpected movement, remove servo
power. Detaching PWM does not disconnect electrical power.

## Software checks (agent can run these)

```sh
python3 scripts/run_v1_checks.py
```

The runner includes production host tests, Swift and cross-language contracts,
all five main firmware variants, the separate bench build, CAD export/checks,
model integrity, iOS simulator tests and unsigned device builds. It does not
flash a board or validate real sensors, power or mechanics.

## Complete physical release

After the single-servo check, follow [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md):
measure power and travel, test one assembled cam/four-pin column, perform P1–P5,
then validate all seven columns and real perception. Keep default seven-servo
PWM disabled until measured pulse limits are supplied. Nominal120° is a design
assumption, not a verified physical sweep. Do not install a seven-output build
as a replacement for the GPIO32-only demo before those gates pass.

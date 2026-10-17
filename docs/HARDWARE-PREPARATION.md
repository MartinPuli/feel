# What to prepare now

Inventory confirmed by the team on October 16, 2026. We have not yet physically
inspected or tested these parts.

1. **Bench for testing a single column.** One ESP32-WROOM will be the main board
   and the second will be a spare. Keep the USB-C data cable, multimeter,
   5 V/4 A supply, and barrel-to-terminal adapter together.
2. **Identify the servos before powering them.** We need to confirm whether all
   seven plus a spare are already available, photograph the label, and retain
   the supplier's datasheet. The current FS0307 datasheet and the handoff do not
   agree on travel and power requirements. The available supply is not yet
   approved for the actual variant. The firmware builds with PWM output disabled.
3. **Measure and test by hand.** Get access to calipers and a printer. Start with
   the hole coupon and the hand-cranked column. The servo body, shaft, and horn
   dimensions must be measured before printing the final assembly.
4. **Fasteners and finishing.** Prioritize M3 × 8 and M3 × 12 screws with nuts.
   Also confirm foam, sandpaper, and Velcro/elastic. Check each screw's final
   length against the part; do not force a screw against the bottom of the plastic.
5. **Power distribution.** Breadboards are suitable for signals and temporary
   low-current connections. Prepare secure motor power distribution on
   perfboard/terminals, sized for the measured current draw. Do not route the
   current for seven servos through the ESP32 or its GPIOs. Check continuity,
   polarity, and common ground with everything disconnected.

If the pack contains a 1000 µF/25 V electrolytic capacitor, reserve it for the
servo power input and verify its polarity before installing it. It does not
replace a suitable supply and wiring. Keep CA glue away from guides, shafts,
and moving pins; do not seal an assembly that still needs adjustments.

The USB-A → 5.5 × 2.1 mm barrel cable can wait until portable testing. It does
not increase the current the port or battery can supply; polarity and voltage
drop under load must also be checked. Perform the first test on the bench with
one servo, without a cam or load, after confirming its limits.

**Integration order:** manual column → pin return and 100 cycles → unloaded,
calibrated servo → one motorized column → seven columns → BLE and iPhone.
Detailed criteria and steps are in [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md)
and [the CAD guide](../cad/README.md). No software test validates this physical
assembly yet.

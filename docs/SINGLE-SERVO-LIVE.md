# Single-servo live V1: nominal120° mapping

The user requested the production mapping instead of the small midpoint demo.
The opt-in `esp32-single-live` environment applies the existing production
controller's center-sector pulse to GPIO32 only. It uses nominal900–2100 µs for
0/40/80/120° band selection, including the controller's gap transitions and
highlight behavior. These are design values, not measured travel or waveform.
It does not enable the other six servo outputs or verify the complete device.

The previous `esp32-single-demo` environment retains its1450–1550 µs range.
Default seven-servo builds still require separately supplied measured limits.
The live environment is a user-selected nominal profile, not measured calibration.

Boot, no connection, stale packets, all-zero Stop and disconnect detach output.
A central band of0 while other sectors are occupied follows the controller's
neutral gap. Serial bench/raw/calibration commands remain unavailable in this
profile. The production500 ms watchdog and packet checks remain active.
Detachment does not disconnect servo power or prove passive pin return.

## Use

After uploading, reconnect the iPhone to **FEEL Center Live** (a cached old
name may persist), start **Live sensing**, set
**Camera height**, then **Calibrate floor**. Move a large object between distance
bands in the center camera sector. Expect distinct positions instead of the
small demo motion. Use **Stop** to end live commands. Avoid holding the shaft;
remove servo power if it jams, heats or buzzes continuously.

A software build and firmware readback establish installation only. Observe
travel and stop behavior before mounting a cam. Full120° sweep, load/voltage,
mechanical fit and seven-column operation remain separate physical gates.

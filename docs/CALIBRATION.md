# V1 calibration — physical measurements required

Start with the hand-cranked single column and complete P1–P5 in
[HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md). Record CAD/firmware commits, servo part
label, supply, printed material, shaft variant and foam configuration.

## Servo travel is unresolved

The handoff proposes 175° across 650–2500 µs. The [current manufacturer page](https://www.feetechrc.com/en/6v-06 kg-analog-steering-gear-fs 0307.html)
lists 120° across 900–2100 µs and a voltage specification that must be reconciled
with the exact delivered unit. Do not apply either specification to an unidentified
variant. The four-lobe cam requires the handoff's travel; if your unit cannot
provide it within its supported range, use a suitable servo or redesign/revalidate
the cam. An offset does not create missing travel.

Firmware GPIO output is disabled by default. Follow `firmware/README.md` to set
explicit measured pulse guards before enabling a bench build. Software status and
the phone show output-disabled/fault conditions. Enabling requires team inspection,
not a simulated test result.

## Unloaded, then coupled

1. Power off; leave horn and cam disconnected. Confirm supply/pin map/polarity and
   an immediate power disconnect. Install the reviewed bench firmware.
2. Use a supported midpoint from the actual datasheet; make small unloaded pulse
   changes, measuring shaft angle. Stop at binding, buzzing or heat. Never begin
   with the unverified extreme endpoints.
3. Record the usable measured pulse-angle range for every servo. Verify required
   band angles and gaps are achievable before coupling.
4. Measure body, spline, tab and horn geometry. Update `cad/params.scad`, regenerate
   parts and repeat fit checks. Read the CAD measurement gate before final printing.
5. With power off, index the shaft/horn to the known neutral gap. Power one column
   and use the serial commands below. Observe all pins, not just the chosen one.
6. Save only after all four bands, three gaps, highlight and neutral behavior pass.
   Reboot, re-arm as documented, and repeat to verify stored calibration.

## Serial interface

See firmware README for exact syntax;115200 baud, newline. BLE must be disconnected
for bench commands. `ARM` grants a bounded bench lease; `B c b` selects one band,
`HL c` highlights, `CAL c offset` sets an offset, `CAL save` stores offsets and
stops motion. `US c pulse` is an unloaded characterization tool. `KEEP` refreshes
an active bench motion watchdog; `STOP` ends it.

The 500 ms motion watchdog still applies. A static terminal command will expire;
use the documented repeat/keep mechanism during measured observations. Never
leave a coupled rig running unattended. Invalid commands do not extend motion.

| Column | Servo ID | Min/max pulse verified | Offset ° | Bands/gaps | Tap | Reboot | Evidence |
|---|---|---|---|---|---|---|---|
|0|____|____|____|____|____|____|____|
|1|____|____|____|____|____|____|____|
|2|____|____|____|____|____|____|____|
|3|____|____|____|____|____|____|____|
|4|____|____|____|____|____|____|____|
|5|____|____|____|____|____|____|____|
|6|____|____|____|____|____|____|____|

A motor may be commanded neutral yet remain jammed. Measure return and stop
latency physically. Offset limits and pulse guards prevent some software errors;
they cannot detect force, current, slip or pin contact.

# Experimental one-servo Bluetooth wide travel

Explicitly requested by the user on October 17, 2026. This is not production
calibration. The current source uses the shared assumed175° controller, with
seven-servo PWM disabled by default. This adapter supports only one unloaded
servo on GPIO32. Previously flashed firmware is unchanged until uploaded.

Build: `pio run -d firmware -e esp32-single-wide-test`.
Bluetooth name: **FEEL Wide TEST**. Connect from FEEL's puck connection panel.
The normal app including main sends the same nine-byte protocol. Live center
sector3 drives GPIO32; Simulation does not send movements. Other six outputs
remain unattached. A fresh all-zero packet commands the nearest empty cam gap.
The500ms watchdog and disconnect detach the output; serial STOP also detaches. Serial STOP is temporary if live phone packets continue;
use app Stop or disconnect/power off to stop the experiment.

The adapter passes through the shared linear650–2500us /0–175° mapping without
a second expansion.87.5° maps to1575us. These are command widths and assumed
angles, not measured shaft positions.
The app can immediately command an endpoint: this is not the incremental manual
bench. Use no camshaft/pin mechanism. If straining, buzzing, heating or stalled,
cut servo power. PWM detach is not a power disconnect.

Pololu reports extended travel on tested FS0307 units at650–2500us, outside the
manufacturer's900–2100us specification; unit variation means this is not a safe
range guarantee: https://www.pololu.com/product/3420
The user reports successful wider movement on the real servo. The exact angle
has not been measured;175° is the selected design target.

Host tests cover shared mapping, endpoint bounds, no double expansion,
invalid input, all-zero gap return, bench isolation, watchdog expiry and disconnect.
Physical range, pulse timing, power and mechanical acceptance remain unverified.

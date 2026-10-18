> Current six-column revision: GPIO32 is unused. Use [SIX-COLUMN-LAYOUT.md](SIX-COLUMN-LAYOUT.md)
> for current wiring and the `esp32-six-live` target. Historical single-servo
> examples below using GPIO32 are superseded; current single profiles use GPIO33.

# Live FEEL iPhone integration: one servo only

This demo connects the existing iPhone app to the single unloaded FS0307 on GPIO32. It is not the seven-servo tactile device and must not be used with the production cam mechanism. The user reported successful movement in the nominal1450–1550 µs midpoint test; no physical angle, torque, supply-current or endpoint measurements have been taken.

## What moves

The board advertises **FEEL Center Demo**, using the existing FEEL BLE service and unchanged nine-byte packet. The connected servo represents **sector3, the central (fourth) sector** of the iPhone camera. The other six sectors have no physical actuators connected in this mode.

| Central distance band | Nominal pulse | Meaning |
| --- | --- | --- |
|1|1450 µs|nearest band|
|2|1483 µs|next band|
|3|1517 µs|next band|
|4|1550 µs|farthest band|
|0 with other sectors occupied|1500 µs|center empty|
|all bands0, no fresh packets, disconnect, boot|no PWM|output detached and GPIO LOW|

These are nominal pulses, not measured angles. Highlight/tap and stored cam calibration do not alter this adapter. All-zero app Stop/tracking-loss packets detach on receipt. Loss of fresh accepted packets detaches after the existing500 ms software watchdog. Detachment does not cut electrical supply or guarantee torque release. PWM readiness status1 applies to this single output, not seven ready servos. Serial STATUS reports DEMO, central band, actual requested demo pulse and attached flag; production angle/pulse summaries are suppressed in this mode.

## Use the installed iPhone app

1. Leave the servo unloaded and connections secure. Use the separate5 V supply with common ground and ESP32 USB power. Do not move wiring while powered.
2. In FEEL, expand **Puck connection**, scan and select **FEEL Center Demo**. A cached peripheral name may still show FEEL Puck; the service is unchanged.
3. Choose **Live sensing**, enter the measured camera height and use **Calibrate floor**. Keep the iPhone upright and give AR tracking time to settle. Simulation intentionally sends no movement packets.
4. Place an object in the central camera sector, approximately0.3–4 m away and in the app's obstacle height range. Vary distance across bands and observe the small change in servo angle. A fixed object in a fixed band should hold a position; it does not make the servo spin continuously.
5. Tap **Stop** to stop the app stream and detach PWM. Unplug servo power to remove electrical power.

## Build and restore

```sh
sh firmware/test/run_host_tests.sh
.venv/bin/pio run -d firmware -e esp32-single-demo -j 2
.venv/bin/pio run -d firmware -e esp32-single-demo -j 2 -t upload --upload-port /dev/cu.usbserial-0001
# Restore normal, output-disabled production firmware:
.venv/bin/pio run -d firmware -e esp32 -j 2 -t upload --upload-port /dev/cu.usbserial-0001
```

Prefer servo supply disconnected for flashing; reset/bootloader transients are not controlled by sketch setup. The dedicated environment cannot be combined with production seven-channel output or an S3 board. Default production builds remain PWM-disabled; their measured-range requirements are unchanged. Demo serial control accepts only STATUS, STOP and HELP; raw movement and calibration are rejected. Serial STOP can be followed by another live BLE packet, so use the iPhone Stop control to end the stream.

## Validation scope

Portable tests reuse the production packet decoder/controller and cover mapping, boot/connect idle, all-zero stop,500 ms expiration, duplicate freshness, disconnect, highlight isolation and exclusion of raw bench/calibration effects. Board builds and runtime readback are separate from real iPhone transport and user-observed movement. See the accompanying validation record for actual evidence.

# V1 seven-servo production setup

This is the final **7 columns × 4 pins** configuration: seven FS0307 servos,
one camshaft per column,28 tactile pins. `main` is V1. The app already sends all
seven columns in the existing nine-byte BLE packet; no V2 feature is required.
Only one servo is connected in the current user setup. Do not replace its
installed single-live firmware until the seven-servo wiring is ready.

## Exact signal mapping

Place the device with the wrist end toward the user. Columns run from the user's
left to right. GPIO numbers are printed pin names, not connector positions.

| Physical servo | Firmware column / camera sector | Signal GPIO |
|---|---:|---:|
|1 — far left|0|32|
|2|1|33|
|3|2|25|
|4 — center|3|26|
|5|4|27|
|6|5|14|
|7 — far right|6|13|

**Mapping changes from the single-servo adapter:** GPIO32 currently represents
the center camera sector. In the seven-servo configuration GPIO32 represents
the far-left sector; **GPIO26 is the center**. Label each servo before mounting.

Each servo's verified positive power lead goes to the external supply positive
distribution bus. Each ground lead goes to the negative bus, also connected to
ESP32 GND. Only the signal leads connect to the GPIOs above. ESP32 USB remains
its programming/power connection; do not join external supply positive to USB,
3V3 or a GPIO. Use mechanically secure, insulated connections and distribution
rated for simultaneous load. Do not send all motor current through a single
breadboard rail or improvised single contact. The available5V/4A supply has not
been measured under seven-servo load; its label alone does not prove capacity.

Supplier reference for the identified model: [Pololu3420 FS0307](https://www.pololu.com/product/3420)
and its [datasheet](https://www.pololu.com/file/0J1429/FS0307-specs.pdf). These specify
4.8–6V and nominal120° at900–2100µs, but do not replace unit/load measurements.

## Firmware profile and calibration record

The explicit `esp32-production` environment enables the existing seven-channel
production controller only with a completed local measurement record. The
example is a blank form, not a calibration result. Follow the configuration
instructions in [firmware README](../firmware/README.md), and complete all seven
servos' measured limits before building/uploading that environment.

Once the actual measurements and evidence files exist, make a local copy of
`firmware/production-measurements.example.json` as
`firmware/production-measurements.local.json` and fill every record. Do not mark
unperformed checks as verified. From the repository root with PlatformIO set up:

```sh
.venv/bin/pio run -d firmware -e esp32-production -j 2
# After wiring and individual travel checks, with servo power disconnected:
.venv/bin/pio run -d firmware -e esp32-production -j 2 -t upload --upload-port /dev/cu.usbserial-0001
```

The build currently refuses because measurements have not been supplied. This
is the intended deployment gate, not a compilation result for measured hardware.
The existing compile-only fixtures exercise the same seven-output code path
without creating a deployable configuration. The actual connected board remains
on its previously installed single-live firmware.

The selected design is nominal120°, with band angles0/40/80/120 and neutral
gaps20/60/100. The pulse envelope is900–2100µs. Every servo must physically
support that envelope for this design; narrower travel needs design changes,
not invented measurements or silently rescaled angles. Stored offsets are
per-column, limited to±5°, and cannot add missing travel.

Unlike the single-live adapter, production commands a neutral gap at startup
and holds gap pulses on Stop, disconnect or timeout. It may move on startup.
This behavior keeps the cam at a no-pin position; return and load must still be
observed. An output-range fault detaches all outputs until reboot. Detaching
PWM does not remove electrical power.

## Bring-up in order

1. With power off, label the seven servos and check every signal, power and
   ground connection. Verify power distribution and polarity with the meter.
2. Measure unloaded travel for each servo and record its identity and evidence.
   Finish the local configuration; compile and upload the production profile
   with motor power disconnected. Do not use a compilecheck binary for upload.
3. With all shafts free, power the motors and verify neutral. Connect **FEEL
   Puck** from the app, choose Live sensing, set camera height and calibrate floor.
4. Move one large object through the seven camera sectors. Verify the matching
   servo left-to-right. Test near/far distance bands and then combinations across
   several sectors; observe power stability and ESP32 resets.
5. Test Stop, Bluetooth disconnect, tracking loss and reconnect. Neutral gap
   commands should replace raised-pin commands; reconnect needs fresh packets.
   Measure the real response rather than inferring latency from host tests.
6. Fit and validate one cam/four-pin column using P1–P5 in
   [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md), then expand to all seven. Verify
   selection, return, thumb hold,100 cycles, taps and calibration persistence.

Record PASS/FAIL/NOT TESTED per column. Software tests cover decoding, sequencing,
all seven requested outputs, neutral/timeout logic and output guards. They do
not establish correct wiring, current capacity, physical120° travel, cam fit or
reliable tactile interpretation. Full-device physical acceptance is still pending.

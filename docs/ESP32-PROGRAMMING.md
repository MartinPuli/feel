# ESP32 programming handoff

Use **`esp32-six-live`** for the selected classic ESP32-WROOM six-column setup.
This is the existing experimental live profile, not measured production calibration.
The `esp32` default keeps PWM disabled; `esp32-production` requires physical
measurement records and is a separate gated profile.

## Build and upload

Run from the repository root. The existing local PlatformIO 6.1.18 environment is
`/private/tmp/feel-travel-pio`; activate it first:

```sh
source /private/tmp/feel-travel-pio/bin/activate
python -m platformio run -d firmware -e esp32-six-live -j 2
```

The build uses the repository's pinned Espressif32 6.9.0, Arduino-ESP32 2.0.17,
and NimBLE-Arduino 2.3.6. It does not connect to hardware.

For a deliberate upload, confirm the board is the classic ESP32, remove servo
power, connect a USB data cable, and identify the matching port:

```sh
python -m platformio device list
# Replace the placeholder with the actual port for this board.
python -m platformio run -d firmware -e esp32-six-live -j 2 --target upload --upload-port /dev/cu.REPLACE_WITH_BOARD_PORT
```

Use PlatformIO's upload target so it applies the board's bootloader, partition
and application offsets. Do not flash the application binary at address zero.
After upload, inspect status over USB if needed:

```sh
python -m platformio device monitor --port /dev/cu.REPLACE_WITH_BOARD_PORT -b 115200
```

The live profile advertises **FEEL Puck** and accepts BLE commands from one central.
Disconnect another phone before pairing. Serial accepts STATUS, STOP and HELP;
it does not accept bench movement/calibration commands in this profile.

## Preserved mapping and user adjustment

The packet remains nine bytes: sequence, seven band slots, highlight. Slot 0 is
reserved and GPIO32 is unused.

| Active wire slot | Position | GPIO | Total live trim |
|---|---|---|---|
| 1 | L3 | 33 | +159 microseconds |
| 2 | L2 | 25 | +307 microseconds |
| 3 | L1 | 26 | +159 microseconds |
| 4 | R1 | 27 | +159 microseconds |
| 5 | R2 | 14 | +159 microseconds |
| 6 | R3 | 13 | +159 microseconds |

The unchanged live upper cap is **2648 microseconds**. GPIO25's requested
adjustment is +148 microseconds relative to the previous trim. Its band 1 is
nominal 29 degrees, not a measured physical angle. With zero calibration offsets,
GPIO25's band 1–4 commands are **957, 1570, 2183, 2648 microseconds**. The remaining
columns retain **809, 1422, 2035, 2648 microseconds**. No values were changed for
this programming handoff.

An accepted neutral packet cannot restore an old band by itself. A later valid
packet is required to raise a band. Disconnect and the existing 500 ms watchdog
detach outputs. Software tests do not establish actual pin return or mechanical
neutral position.

## Physical status

No upload, serial connection, BLE connection, or servo actuation was performed
for this handoff. Six-column movement, power under load, safe travel, cam alignment,
and tactile behavior remain **NOT VERIFIED**. Use separate appropriate servo power
with common ground; ESP32 GPIOs are control signals, not servo power sources.

`firmware/production-measurements.local.json` is absent. The guarded production
profile therefore remains blocked until real measurements are recorded. This does
not prevent compiling the explicitly selected experimental `esp32-six-live` profile.

## Current build evidence

A fresh `esp32-six-live` build passed on 2026-10-18 in 44.07 seconds after the
GPIO25 adjustment was merged. RAM usage is 35,916 / 327,680 bytes (11.0%);
application flash usage is 603,009 / 1,310,720 bytes (46.0%).

Artifacts in the integration checkout:

- `/private/tmp/feel-version-validation-main/firmware/.pio/build/esp32-six-live/firmware.bin`
  — 609,520 bytes, SHA-256 `32585c122352af95ba25a1cb30aae649d9d3de5e54cfbc03c2fa621d7a096c7f`.
- `bootloader.bin` and `partitions.bin` in the same directory are also present.
- Build log: `/private/tmp/feel-esp32-six-live-programming-build.log`.

These artifacts are ignored build outputs, not Git-tracked release binaries.
Rebuild from the updated canonical checkout before uploading there; an older
binary in a different checkout may predate the GPIO25 adjustment. Compilation
passed; programming and physical behavior remain unverified.

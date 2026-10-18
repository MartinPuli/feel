# Pin test: raise chosen pins on the real puck

`firmware/tools/pin_test.py` sends the puck exactly the pins you ask for and reads back the bands the
firmware is holding. You watch the puck; the tool cannot see a servo move.

## Setup once

```
source .venv/bin/activate          # bleak and pyserial are installed here
```

The puck must be powered and running the live firmware (BLE name `FEEL Puck`). Disconnect the phone
app first: the puck accepts one BLE central at a time. The first run asks macOS for Bluetooth
permission for your terminal.

## Say which pins

Wire slots 1..6 are the six physical columns, left to right when worn: L3 L2 L1 R1 R2 R3. Slot 0 has
no servo. Bands: 1 near (under 0.9 m), 2 (under 1.6), 3 (under 2.5), 4 far (up to 4 m).

```
python3 firmware/tools/pin_test.py --pins 3:2 5:4            # L1 to band 2 and R2 to band 4
python3 firmware/tools/pin_test.py --each                     # every slot alone, band 4, 3 s each
python3 firmware/tools/pin_test.py --each --band 1            # every slot alone, nearest band
python3 firmware/tools/pin_test.py --pins 4:4 --tap 4         # raise R1 and tap it
python3 firmware/tools/pin_test.py --lidar -30:1.2 20:0.6     # obstacles, see below
python3 firmware/tools/pin_test.py --pins 2:3 --seconds 10    # hold longer
```

Add `--dry-run` to print the picture and packet without touching hardware.

## LiDAR input

`--lidar BEARING:DISTANCE[:HEIGHT]` describes obstacles the camera would see: bearing in degrees
(right positive, the pins cover -45..45), range in metres, optional height above the floor (default
1.0 m). Each obstacle becomes a real surface and runs through the production depth projector and
encoder, so the pins that rise are the pins the phone would raise for that scene.

```
--lidar 0:0.5          something straight ahead, half a metre: R1 (slot 4) to band 1
--lidar -37:3.0        far left, 3 m: L3 (slot 1) to band 4
--lidar -30:1.2 20:0.6 two obstacles: L2 band 2 and R2 band 1
--lidar 0:1.0:0.3      something at knee height: nothing rises (below the 0.6 m window)
```

The first `--lidar` run builds `feel-replay` in release mode; pass `--build` after changing FeelCore.

## What you see

```
Requested:
        L3 L2 L1 R1 R2 R3
far  4   ·  ·  ·  ·  █  ·
     3   ·  ·  ·  ·  ·  ·
     2   ·  ·  █  ·  ·  ·
near 1   ·  ·  ·  ·  ·  ·
         1  2  3  4  5  6   wire slot
Expect to rise: L1 (slot 3, GPIO26) to band 2; R2 (slot 5, GPIO14) to band 4. Every other pin stays down.
packet: 00000002000400ff  (seq, b0..b6, highlight)
Scanning for "FEEL Puck"...
Connected. Holding for 3.0 s ...
Firmware held:
        (same picture, from the puck's status characteristic)
Firmware held exactly the requested pins. Did the puck show the same picture?
```

Exit code 0: firmware held what you asked. 1: it held something else, or output is disabled. 2: no
puck found. If the firmware agrees but a pin did not move, the fault is downstream of the packet:
wiring to that GPIO, servo power, the horn, or the cam. If the firmware disagrees, read the mismatch
lines; they name the slot.

## Bench firmware over USB

A board flashed with the bench profile refuses BLE motion and takes serial commands instead:

```
python3 firmware/tools/pin_test.py --pins 3:2 5:4 --serial /dev/cu.usbserial-XXXX
```

The tool arms, sets each requested slot, keeps the lease alive for the hold, then stops. On the live
profile this path prints that serial motion is refused and tells you to use BLE.

## Tests

`firmware/test/test_pin_test.py` covers the spec parsing, packet layout, status decoding and the
picture; it runs as part of `sh firmware/test/run_host_tests.sh`.

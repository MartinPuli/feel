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
1.0 m). Each obstacle produces three identical, high-confidence synthetic depth samples and runs
through the production depth projector and encoder. This checks the packet mapping only. It does
not reproduce camera noise, temporal filtering, floor estimation, target tracking, or the full phone
pipeline. A dry run neither connects to the puck nor proves any physical movement.

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
packet: 0000000002000400ff  (seq, b0..b6, highlight)
Scanning for "FEEL Puck"...
Connected. Holding for 3.0 s ...
Firmware held:
        (same picture, from the puck's status characteristic)
Firmware reported the requested pins with output ready. Physical movement remains unverified; observe the puck.
```

For BLE, exit code 0 means fresh firmware status acknowledged the final hold packet with the
requested bands and highlight, connected/active/sequence-valid state, bench mode off, and output
ready. It does not prove mechanical movement. Exit 1 means mismatched, unavailable or stale
evidence, output disabled/faulted, a transport error, or incomplete cleanup. Exit 2 means no puck
was found. A dry run returns 0 for a valid request without testing hardware.

Hold evidence is frozen before cleanup so neutral notifications cannot overwrite it. The tool
attempts three neutral packets even after a hold/write error or cancellation, then disconnects.
Cleanup failures are reported; the firmware's existing disconnect and 500 ms watchdog are the
fallback. Neutral delivery is not physically verified. `--each` stops on its first failed test. If the firmware agrees but a pin did not move, the fault is downstream of the packet:
wiring to that GPIO, servo power, the horn, or the cam. If the firmware disagrees, read the mismatch
lines; they name the slot.

## Bench firmware over USB

A board flashed with the bench profile refuses BLE motion and takes serial commands instead:

```
python3 firmware/tools/pin_test.py --pins 3:2 5:4 --serial /dev/cu.usbserial-XXXX
```

The tool arms, sets each requested slot, keeps the lease alive for the hold, then sends STOP in
cleanup. Serial exit 0 means the commands were acknowledged after the initial output-ready check;
it does not read back the final bands/highlight and does not verify physical motion. Use BLE for
correlated final-hold status validation. The live profile refuses serial motion.

## Tests

`firmware/test/test_pin_test.py` covers the spec parsing, packet layout, status decoding and the
picture, negative-bearing arguments, fake BLE status ordering/readiness/sequence/highlight checks,
write failures, cleanup, cancellation, and fail-fast iteration; it runs as part of `sh firmware/test/run_host_tests.sh`.

## Offline regression evidence (2026-10-18)

Before the diagnostic fixes, the new fake-transport suite ran 17 tests and reported 12 assertion
failures plus 3 errors. A further regression proved `--each` continued after a failed hold. All 21
pin-tool tests pass after the fixes. The fake BLE client cannot discover or connect to real hardware.
No servo angles, pulses, watchdog behavior, or hardware firmware were changed by these fixes.
The separate GPIO25 user calibration remains intact. Hardware movement is **NOT VERIFIED**.

Validation commands and results:

- `sh firmware/test/run_host_tests.sh` — PASS, including 44 controller cases, board/output guards,
  CLI/adapters, production configuration, six-column calibration, pin-rise and 21 pin-tool cases.
- `CLANG_MODULE_CACHE_PATH=/private/tmp/feel-pin-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/feel-pin-swift-cache swift build --disable-sandbox -c release --product feel-replay --package-path ios/Shared/FeelCore --scratch-path /private/tmp/feel-pin-replay-20261018`
  — PASS. The first attempt using the default module cache was blocked by filesystem permissions;
  the successful build used isolated temporary caches.
- Freshly built `feel-replay stdio` plus the pin tool's dry-run path — PASS for the four documented
  LiDAR examples, three direct pin patterns, and tracking-lost/stale-depth/uncalibrated neutral
  outputs. The tool's `REPLAY` path was pointed at the isolated build for these offline checks.
  `FeelReplay` does not expose a `--pin-pattern` option.

Local evidence: `/private/tmp/feel-pin-regression-before.log`,
`/private/tmp/feel-pin-regression-second-before.log`, `/private/tmp/feel-pin-final-host.log`,
`/private/tmp/feel-pin-replay-build.log`, and `/private/tmp/feel-pin-offline-replay.log`.
These logs are local validation artifacts, not physical measurements.

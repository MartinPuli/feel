# Single-servo bench validation

Recorded UTC: 2026-10-17T02:43:42.996509+00:00

- Host state-machine tests: PASS (arming/expiry, watchdog, absolute cap, invalid commands, STOP, rollover).
- ESP32 build: PASS.
- Independent read-only control review: no blocking issue found.
- USB upload to ESP32-D0WD-V3 rev3.1: PASS; uploader verified flash hashes.
- User confirmed external servo supply unplugged and shaft unloaded before upload.
- Initial board diagnostic reported AUTO clock frequency49 Hz; output remained disabled. Explicit APB clock override now reports50 Hz, matching the inspected pinned IDF clock calculation. This is software readback, not waveform measurement.
- Boot idle and STOP: PASS, transcript below.
- No ARM or CENTER command sent to hardware.
- Supply polarity/voltage measurement, UART parser test coverage, actual PWM waveform, servo movement/current: NOT VERIFIED.
- Production BLE temporarily unavailable while standalone bench firmware is installed.

Firmware SHA256: `b5f0bc59cd6d82b3b522b871df72b26c23c5e072ce1e2e4b41961e08750e2a69`

```text
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
> STOP
ok
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
```

## First bounded command

UTC: 2026-10-17T02:46:27.960630+00:00

User requested activation and indicated supply connected, having previously confirmed an unloaded shaft. One nominal1500 us CENTER command was acknowledged, followed by STOP after200 ms. No KEEP and no repeat were sent; firmware watchdog is250 ms. Final software status confirms detached output. Actual shaft motion, voltage, polarity and current are not measured or independently verified. This command does not validate the physical wiring.

```text
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
> ARM
ok
> CENTER
ok
> STOP
ok
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
```

## User-requested longer center hold

UTC: 2026-10-17T02:47:23.048797+00:00

One nominal1500 us CENTER hold requested for800 ms with80 ms KEEP intervals and final STOP. Firmware retains its absolute1 s cap and250 ms communication watchdog. Final software state was inactive and detached. User has not yet confirmed motion; electrical measurements remain pending.

```text
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
> ARM
ok
> CENTER
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STOP
ok
> STATUS
SINGLE_CENTER ready=1 armed=0 active=0 attached=0 gpio=32 nominalUs=1500 timerHz=50
```

## Five-second midpoint sequence

UTC: 2026-10-17T02:51:17.800215+00:00

User explicitly requested five seconds of movement and said the supply remained connected after being asked to unplug it. Updated firmware was flashed and boot idle was confirmed. Bootloader/reset transients were not measured. TEST5 was sent once with KEEP approximately every75 ms. STATUS reported active output and alternating1450/1550 µs targets, then1500 µs, then inactive/detached after its five-second software cap. STOP was also acknowledged. These are controller readbacks, not measurements of waveform, actual position, torque, voltage or current. Physical motion still awaits user observation. Host tests and independent review passed for phase changes, watchdog, hard cap, active-command rejection and rollover.

Firmware SHA256: `a10006bf8bf021582598b1f0c14b4c228eabefeee45cfe52cd4885235d5e0f60`

```text
> STATUS
SINGLE_BENCH ready=1 armed=0 active=0 attached=0 gpio=32 pulseUs=0 timerHz=50
> ARM
ok
> TEST5
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1450 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1550 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1450 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1550 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1450 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1550 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1450 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1550 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=1 attached=1 gpio=32 pulseUs=1500 timerHz=50
> KEEP
ok
> KEEP
ok
> KEEP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=0 attached=0 gpio=32 pulseUs=0 timerHz=50
> STOP
ok
> STATUS
SINGLE_BENCH ready=1 armed=0 active=0 attached=0 gpio=32 pulseUs=0 timerHz=50
```

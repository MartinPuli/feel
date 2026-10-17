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

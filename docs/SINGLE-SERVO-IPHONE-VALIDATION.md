# Single-servo iPhone integration validation

Recorded UTC: 2026-10-17T02:57:02.186764+00:00

- User reported successful physical motion during the prior five-second midpoint test.
-41 production controller tests,17 CLI cases,14 config gate cases,6 compile-only guard cases,4 bench-input cases and single-demo adapter suite: PASS.
- Default classic ESP32 and esp32-single-demo builds: PASS.
- Independent read-only single-demo review: no blocking finding.
- Upload to connected ESP32-D0WD-V3 rev3.1: PASS, flash hashes verified by uploader.
- Boot timer readiness and output detached: PASS via serial readback below.
- Physical voltage/current/pulse measurements: NOT DONE.
- Live iPhone-to-servo integration: pending user connection and observation.
- Attempt to launch existing installed iPhone app from Mac failed because the device was not available through CoreDevice; user can open app directly without a cable to Mac.

Firmware SHA256: `c568b732c8cbee99b81ade26baeefb8cbe4b49050a843f3054f93fe4e56bf55e`

```text
DEMO connected=0 active=0 ready=1 attached=0 gpio=32 sector=3 band=0 pulseUs=0 timerHz=50 accepted=0 rejected=0 timeouts=0
```

# Seven live outputs — October17,2026

The user explicitly requested the same current alignment on all seven servos.
`esp32-seven-live` opts into seven independent live outputs, separate from the
measured-record production profile. No synthetic measurement record was used.

Independent review passed. Full host suite passed, including seven-column
independence, exact trimmed band/gap values, all-or-nothing plan validation,
invalid late-column input, zero return, timeout/disconnect/Stop, sequence wrap,
and37compile-time configuration checks. Host evidence:
`/tmp/feel-seven-live-host.log`; build evidence:`/tmp/feel-seven-live-build.log`.

Board: classicESP32. GPIO order32,33,25,26,27,14,13. Center nowGPIO26; GPIO32
nowleftsector0. BLE name FEEL Puck. Existing9-byte contract supports V1–V4.
Per-column adjusted selection pulses809/1422/2035/2648µs are commands, not
measured angles. All outputs boot detached and wait for a fresh live packet.
Default seven-PWM-off and measured-production profiles retain their guards.

Actual movement of all seven servos, power under load, individual2648µs clearance
and mechanical pin return are not established by this software validation.
See docs/SEVEN-SERVO-LIVE.md for wiring and behavior.

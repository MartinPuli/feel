# Bench session — user-reported progress

October 16, 2026, America/New_York. These observations were reported in chat;
no remote serial port or physical device was accessed by the build environment.

- The team has two ESP32-WROOM USB-C boards and the kit in `HARDWARE-INVENTORY.md`.
- The user reports that one ESP32 is connected by USB to a **Mac**.
- Next diagnostic supplied: open Terminal and run `ls /dev/cu.*`; port output is
  still pending. This lists ports; it does not flash or control the board.
- Servo possession/model, wire identification and photograph are pending.
- No firmware installation, physical PWM, supply measurement, servo movement or
  printed-mechanism acceptance has been confirmed.

For this session, keep the external servo supply and servo disconnected while
identifying the board and serial port. Do not infer board recognition from the
power LED alone. The first intended firmware install uses the default
`esp32` environment, with physical PWM disabled. Enabled-output compile fixtures
are never installation images.

# Isolated FS0307 nominal-center test

This is a separate PlatformIO project. It does not change the production firmware or its measured-range guards. It uses only GPIO32, without Bluetooth. While it is installed, the iPhone cannot connect to FEEL Puck; restore production firmware afterward.

## Physical prerequisites

The identified Pololu3420 FS0307 supports 4.8–6 V supply and 3.3 V control signals. Sources: https://www.pololu.com/product/3420 and https://www.pololu.com/file/0J1429/FS0307-specs.pdf . The CENTER command uses a1500 µs pulse for nominal center, not a measured safe travel range. Initial centering can cause substantial movement from an unknown starting position. Keep the servo unloaded, with no cam or mechanism attached.

Before upload, unplug servo power and power only the ESP32 through USB. Before motion, check supply voltage and polarity, common ground, secure contacts, and a free shaft. Remove power if there is a stall, heat, sustained buzzing, or unexpected motion. Detaching PWM does not remove electrical power or guarantee torque release.

## Behavior

Boot leaves GPIO32 LOW and detached. STATUS never activates output. ARM grants one motion request for10 s. CENTER consumes that permission and emits only nominal1500 µs at50 Hz, for at most1 s. KEEP must arrive within250 ms; it never extends the absolute1 s cap. STOP, invalid commands, or expiration stop and disarm. Every new trial needs a new ARM. TEST5 provides the bounded midpoint sequence described below; there is no endpoint or continuous-rotation command.

Serial parsing is bounded and replies are dropped if the transmit buffer cannot accept them without blocking. Timeout handling still depends on the MCU loop running; it does not protect against a locked MCU or replace physical power isolation. Arduino2 LEDC write and attach APIs provide no success return. Software state is not a waveform or motion measurement.

## Build, upload and restore

From the repository root:

```sh
c++ -std=c++17 -Wall -Wextra -Werror -Ifirmware/bench-single/include firmware/bench-single/test/state_test.cpp -o /tmp/feel-single-center-test
/tmp/feel-single-center-test
.venv/bin/pio run -d firmware/bench-single -j 2
# Only after servo power is removed and the board is identified:
.venv/bin/pio run -d firmware/bench-single -j 2 -t upload --upload-port /dev/cu.usbserial-0001
# Restore production firmware (PWM disabled by default):
.venv/bin/pio run -d firmware -e esp32 -j 2 -t upload --upload-port /dev/cu.usbserial-0001
```

Opening serial may reset the board. Wait for boot and read STATUS before ARM. Never retry CENTER automatically after reconnecting. Host tests cover the portable state machine, not the UART parser, electrical output, current, or servo movement. Physical validation remains pending.

## Five-second test (explicit user request)

TEST5 also requires and consumes ARM. It requests nominal pulses at500 ms intervals:1500,1450,1550,1450,1550,1450,1550,1450,1550,1500 µs, then detaches at5000 ms. It retains the250 ms KEEP watchdog. CENTER retains its1 s cap. Repeating ARM, CENTER or TEST5 during motion stops and disarms; it does not extend the run. The1450–1550 µs neighborhood is a nominal design choice, not measured travel. This is positional reciprocation, not continuous rotation. Initial centering can still move substantially from an unknown position.

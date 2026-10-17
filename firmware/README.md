> Single-servo app control: the opt-in `esp32-single-live` environment uses the
> production center-sector mapping on GPIO32 within nominal900–2100 µs. This
> user-selected120° profile is not measured calibration. See
> [single-live instructions](../docs/SINGLE-SERVO-LIVE.md). The older midpoint
> demo and default disabled seven-servo environments remain available.

# FEEL V1 firmware — greenfield implementation

This is newly written code derived from `HANDOFF-v7.md`. It is **not** the missing original firmware. Its portable production controller is exercised on the host; board compilation and physical testing are separate gates. Never infer servo motion, pin return, force, or BLE reliability from a passing host test.

**Selected hardware:** the team confirmed two **ESP32-WROOM boards with USB-C** (one main, one spare), so use the `esp32` environment and the classic GPIO map after checking the actual board's exposed labels. The `esp32s3` environment is a secondary portability build; it does not describe a board in the confirmed inventory. A USB data cable, 400-point breadboards, perfboards/headers, 22-AWG solid wire, a multimeter, soldering tools and an Adafruit 5 V / 4 A supply are available. The supply's availability does **not** establish that 5 V is correct for the unconfirmed servo variant. Check the capacitor's actual value/polarity/rating (target inventory check: 1000 µF / 25 V) and identify every servo label before powering it. Breadboards are for logic prototyping, not an assumed adequate seven-servo current path.

**Physical PWM is disabled by default** (`FEEL_ENABLE_SERVO_OUTPUT=0`). The board still runs BLE, decoding, calibration, status and timeout logic, but GPIOs remain LOW. The current design assumes **120°**, as explicitly requested, using the FS0307 datasheet's nominal **900–2100 µs** range. This supersedes the historical handoff's 175° / 650–2500 µs design. It is a software/mechanical design assumption, **not a measurement or physical validation of the received servo**. See the [manufacturer PDF, running degree row](https://www.feetechrc.com/Data/feetechrc/upload/file/20220608/6379029528194935652722624.pdf). Confirm the actual unit's power requirements separately; the web page and PDF list conflicting voltage ranges.

An explicitly enabled build must set all three build macros: `FEEL_ENABLE_SERVO_OUTPUT=1`, `FEEL_VERIFIED_PULSE_MIN_US=<measured-safe-minimum>`, and `FEEL_VERIFIED_PULSE_MAX_US=<measured-safe-maximum>`. Missing measured limits cause compilation to fail. Bounds must be ordered within 900–2100 µs. The guard validates **all seven** commanded pulses before any update; an out-of-range request detaches every PWM output and latches a fault until reboot. A narrower confirmed range permits only commands within that range; it does not silently rescale angles. Do not use the nominal values as a substitute for identifying the received servo and verifying unloaded operation. This revision neither enables outputs nor flashes a board.

## Build and test

```sh
# From repository root, Linux/macOS, no board needed:
sh firmware/test/run_host_tests.sh
firmware/build/feel-sim --help

# Actual board binaries, pinned toolchain, no upload:
python3 -m pip install 'platformio==6.1.18'
sh firmware/build.sh
# Compile the physical-output code paths with UNMEASURED software fixtures:
# these non-default environments reject upload/program targets.
sh firmware/test/build_output_paths.sh

# Only with the matching board connected and servo power removed:
python3 -m platformio run -d firmware -e esp32 --target upload
# ESP32-S3 DevKitC-1: use -e esp32s3 instead.
python3 -m platformio device monitor -b 115200
```

`platformio.ini` pins Espressif32 6.9.0 (Arduino-ESP32 2.0.17) and NimBLE-Arduino 2.3.6. Seven independent LEDC channels produce 50 Hz PWM at 14-bit resolution; no ESP32Servo dependency. `main.cpp` includes a guarded Arduino 3 LEDC API path for future upgrades; the default build uses the pinned Arduino 2 API. A build proves compilation, **not** a real servo waveform.

`esp32-compilecheck` and `esp32s3-compilecheck` are software-only compiler fixtures using 900/2100 test bounds so the enabled output path is compiled and linked. Those are **not measured safe bounds**, and their binaries must never be flashed. A pre-build guard rejects `upload`, `uploadfs`, and `program` targets in these environments. Normal default environments remain PWM-disabled. Build scripts cap parallel compilation at two jobs (`FEEL_BUILD_JOBS` can override on an adequately sized machine).

Arduino IDE alternative: copy `include/feel` and `src/controller.cpp`, `src/commands.cpp`, `src/main.cpp`, `include/board_config.hpp` into a sketch while retaining the `feel/` include hierarchy, and provide an empty sketch-named `.ino`; install the same Espressif core and NimBLE versions. PlatformIO is the reproducible, supported build route.

| Column | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| Classic ESP32 GPIO (handoff) | 32 | 33 | 25 | 26 | 27 | 14 | 13 |
| ESP32-S3 DevKitC-1 GPIO (**new assumption**) | 4 | 5 | 6 | 7 | 8 | 9 | 10 |

Do not transfer the classic pin list to an S3. Confirm the actual board, module memory connections, exposed pads, and pin labels before wiring. Both mappings need physical validation. ESP32-C3/C6 are unsupported because this design needs seven independent PWM channels. Keep servo power separate from ESP32 GPIO/3.3 V, with a suitable supply and common ground; voltage/current/connector polarity must be measured or established from the actual servo documentation.

## Production controller and wire contract

`include/feel/controller.hpp` + `src/controller.cpp` implement the exact controller used by both the board adapter and `build/feel-sim`:

```
[sequence, band0, band1, band2, band3, band4, band5, band6, highlight]
```

- Exactly 9 bytes; bands 0–4; highlight 0–6 or 255. Malformed packets apply no motion. Wire-legal highlight on a zero band is normalized to effective highlight 255.
- First valid sequence is accepted. Subsequent modulo-256 delta 1–127 is accepted; delta 0 is duplicate, 128–255 is stale. Rejections do **not** refresh the watchdog. Disconnect and timeout clear the sequence baseline.
- At `elapsed >= 500 ms` without an accepted packet or valid bench motion/keepalive, command all bands down into their previous nearest gaps. Unsigned subtraction handles the 32-bit `millis()` rollover.
- Four band angles: **0°, 40°, 80°, 120°**. Gaps: **20°, 60°, 100°**. Last selected bands 1/2 use 20°, band 3 uses 60°, band 4 uses 100°; initially every column uses 20°. Nearest-gap ties choose the lower angle. Raw bench positions use the same nearest-gap rule.
- Highlight dips **13° toward that band's gap** (tap positions 13°, 27°, 67°, 107°) for the first **100 ms of a 600 ms cycle**. These durations are new tunable assumptions, not recovered handoff facts. Repeated 10 Hz packets do not restart a tap; changing the highlighted column/band does.
- Calibration offsets are finite ±5°, added to every non-raw position and clamped to **0–120°**. The nominal pulse conversion is **900–2100 µs across 0–120°**, with **60° = 1500 µs**; real endpoints remain **unmeasured**. Raw `US` bypasses the offset. An endpoint offset may be clipped; it cannot create extra travel.
- A jump between distant bands necessarily sweeps through intervening cam positions. This controller does **not** promise neighbor-free transient motion. CAD endpoint geometry is insufficient to establish physical P5.

The wire has no checksum, timestamp, session identifier, or authentication. Semantically valid bit corruption and delayed forward-sequence packets can pass. The local 500 ms watchdog bounds receiver silence; it cannot prove the sensor observation was fresh. The iOS sender must enforce its own sensing/tracking freshness. Sequence baseline reset also means a delayed packet after timeout cannot be recognized as belonging to an old session.

## BLE adapter

Name: `FEEL Puck`. Service: `7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000`.

| Characteristic suffix | Properties | Contents |
|---|---|---|
| `0002` | write / write without response | exact nine-byte command |
| `0003` | read / notify | 15-byte versioned status below |

The full UUID uses the suffix in the same base as the service. The new UUID assignments are project decisions, not handoff-recovered values.

Status bytes: `[version=1, connected, active, sequenceValid, lastSequence, effectiveHighlight, benchArmed, outputState, band0…band6]`. Boolean flags are 0/1; byte 7 is an **enum**, `0 = PWM disabled`, `1 = PWM initialized and range guard ready`, `2 = latched output fault`. Notifications are attempted every 200 ms; they are observational and never keep motion alive. `outputState=1` does not prove any physical pin moved. Default builds report 0 with an explicit serial banner. An active controller with outputState 0 is processing commands without emitting servo waveforms.

BLE callbacks copy immutable events into a bounded FreeRTOS queue; only `loop()` mutates the controller or writes PWM. Events retain receipt time. Queue backlog older than 500 ms is dropped; current-time expiry runs before PWM is updated. Queue overflow discards pending commands, commands neutral and disconnects. Connect/disconnect events and packets are drained in order, with no intermediate PWM writes. Runtime Arduino 3 PWM write failures detach **all** channels and drive pins LOW, leaving a latched fault until reboot; Arduino 2's write API supplies no success return. PWM detachment does not cut power or guarantee the servo releases torque or the pins return.

The prototype permits one BLE connection and does not implement pairing/authentication. Use in a controlled demo environment. A product needs authenticated control, physical emergency power isolation, and a hardware-level fault strategy. MCU lockup/brownout and PWM signal integrity are physical integration gates.

## Bench commands (115200 baud, newline)

Disconnect the phone first. No servo motion command is accepted until `ARM`. Arming lasts 30 seconds, regardless of keepalives. Motion expires at 500 ms; this is deliberate for both BLE **and serial**. A manual `B` demonstrates a brief move. Use the bounded `tools/bench.py` helper to hold a supervised position while inspecting it.

| Command | Meaning |
|---|---|
| `ARM` | Start a 30-second bench lease, neutral; rejected while BLE connected |
| `B c b` | Column c 0–6, band b 0–4; `B 0 0` drops column 0 |
| `HL c` / `HL off` | Tap selected column or disable tap; zero band has no effective tap |
| `US c pulse` | Exclusive raw bench pulse 900–2100 µs, other columns neutral |
| `KEEP` | Refresh current active bench motion only; cannot revive timed-out motion |
| `CAL c offset` | Offset ±5°; does not refresh motion watchdog |
| `CAL save` | Neutral, stop/disarm, then persist one versioned offset blob in NVS |
| `STOP` | Immediate neutral and disarm; always available |
| `STATUS` | Print commanded bands, angles, pulses, offsets and flags |
| `HELP` | Print command syntax |

Malformed/overlong lines, extra arguments, NaN/infinite offsets and out-of-range numbers are rejected. A 96-byte serial budget and one command per loop prevent unbounded serial parsing from starving the watchdog. NVS save uses a version-2 record under `offsets_120_v2`, validates its version and all offset values before applying any, and rejects invalid data atomically. The old `offsets_v1` key is never read or migrated: calibration for the previous geometry cannot be reused, so this revision starts at zero offsets until recalibrated. Invalid data keeps all default zero offsets. Saving never writes continuously to flash.

One-column bring-up:

1. Remove servo power. Confirm board pins, voltage, current limits, polarity, common ground and actual FS0307/horn geometry. Flash only the matching target. The default build holds the signal outputs LOW; verify that no servo PWM is emitted before enabling a measured-range build.
2. Complete the **unpowered** single-column P1–P5 tests before fitting a servo. Keep the hand clear. Identify the actual servo voltage/travel and establish safe limits with an appropriate unloaded servo tester. The default FEEL build emits no servo pulses.
3. Configure the three measured-range macros above for deliberate bench use, rebuild and flash. Start with one uncoupled servo and a current-limited supply; the initial neutral pulse can move it immediately. Measure a safe pulse range gradually; **do not blindly send both 900/2100 µs endpoints**. Those values are nominal design limits, not verified safe limits for the received part. Stop at any stall, excess current, heat, or mechanical end stop. If the received unit cannot provide the assumed 120° within measured safe limits, stop cam integration and revise the design; changing pulse limits does not establish safe travel.
4. Only after sufficient measured travel and safe endpoints are established, fit the verified coupling at known orientation. Run `ARM`, `B 0 1`, then other bands one at a time, renewing ARM as needed. For a brief supervised hold: `python3 firmware/tools/bench.py --port /dev/ttyUSB0 --band 0 2 --seconds 2`. Default transport opening may reset the ESP32; read the helper's console output. OutputState 0 or 2 means no motion should be expected; disconnect servo power before investigating a fault.
5. Adjust `CAL 0 offset`, inspect all four bands and gaps, `CAL save`, reboot, and verify `STATUS`. One offset cannot correct a nonlinear/incorrect pulse range; never use offset to hide mechanical misalignment.
6. Only after one column passes real motion/return/tap tests, repeat per column and expand to seven. Test power under load, disconnect, phone backgrounding, missing packets, and the 500 ms failsafe with measured latency. Log physical findings separately from software evidence.

## Deterministic host simulator

```sh
firmware/build/feel-sim <<'EOF'
CONNECT 0
PACKET 10 0 1 2 3 4 0 1 2 255
PACKET 110 1 1 2 3 4 0 1 2 3
TICK 610
EOF
```

Each command produces JSON with `mode: "SIMULATION"`, commanded `bands`, `angles_deg`, `pulses_us`, effective highlight, tap phase, connection/watchdog/sequence flags and counters. There is no simulated torque, friction, servo lag, power sag, tactile sensation, or BLE radio. The **production** decoder/controller is reused; the clock, input transport, and servo outputs are substituted.

Line commands: `CONNECT ms`, `DISCONNECT ms`, `TICK ms`, `STATE ms`, `RESET ms`, `PACKET ms bytes...`, `DECODE ms bytes...`, `ARM ms`, `STOP ms`, `KEEP ms`, `BAND ms c b`, `HL ms c|off`, `CAL ms c offset`, `US ms c pulse`. Decimal and `0x` bytes accepted; `DECODE` only validates the wire packet without applying it. `RESET` resets controller state, including offsets. Time must advance monotonically modulo 2³², with no interval longer than a full clock wrap.

## Sources and deliberate assumptions

Official implementation references consulted 2026-10-16:

- [NimBLE-Arduino migration/callback signatures](https://github.com/h2zero/NimBLE-Arduino/blob/master/docs/Migration_guide.md) and [server callbacks](https://h2zero.github.io/NimBLE-Arduino/class_nim_b_l_e_server_callbacks.html).
- [Espressif LEDC](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html), [Arduino 2→3 migration](https://docs.espressif.com/projects/arduino-esp32/en/latest/migration_guides/2.x_to_3.0.html) and [Preferences/NVS](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/preferences.html).
- [PlatformIO ESP32-S3 DevKitC-1 board](https://docs.platformio.org/en/latest/boards/espressif32/esp32-s3-devkitc-1.html) and [unit testing](https://docs.platformio.org/en/latest/advanced/unit-testing/index.html).

Handoff omissions resolved explicitly: UUIDs/status layout, modular sequence policy, gap tie rule, tap period/dip duration, safe command parsing, offset bounds, disconnected bench mode, 30-second ARM lease, raw-pulse exclusivity and proposed S3 GPIO mapping. Physical endpoints, servo polarity, motion timing, current supply, horn alignment, pin return and tactile interpretation remain measurement tasks.

## Opt-in single-servo live120 adapter

`esp32-single-live` is a separate classic-ESP32 environment for the explicitly
selected **nominal120-degree** design. It advertises **FEEL Center Live** and
attaches only GPIO32. It reads production controller `pulses[3]` directly: the
center sector's band positions, adjacent gaps, highlight taps and existing
calibration offsets all apply within nominal900–2100 microseconds. This is not
a measured-safe-range build or evidence of full physical120-degree travel.

Boot, connection without a packet, all-zero STOP/tracking-loss packets,
disconnection and the existing500ms command timeout leave GPIO32 detached/LOW.
Serial accepts only STATUS, STOP and HELP; calibration and bench motion remain
unavailable in this mode. Serial STOP is temporary if the phone continues
sending live packets. The other six servo outputs remain unattached.

```sh
# Compile only; does not flash or actuate hardware:
python3 -m platformio run -d firmware -e esp32-single-live -j 2
```

The existing `esp32-single-demo` keeps its nominal1450–1550us mapping. Default
seven-servo environments keep PWM disabled and their measured-limit requirement
is unchanged. The new adapter reuses the same nine-byte BLE protocol and
quantized50Hz output path; no independent sweep is performed.

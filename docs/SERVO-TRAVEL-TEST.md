# Servo travel test: which shaft to print

Takes about 15 minutes with one servo. It answers one question: **how far does our FS0307 actually turn?** That decides which shaft to print.

| Measured travel | Print | Rows |
|---|---|---|
| About 175° or more | `shaft.stl` | 4 |
| Less than 175° | `shaft4.stl` | 4, steeper lobes |
| Fallback if nothing else works | `shaft3.stl` | 3 (the 0.9–1.6 m band never shows) |

Background: FEETECH rates the servo at 120° for 900–2100 µs pulses. Pololu measured about 180° on their units at 650–2500 µs, but says units differ. Nobody has measured ours. `shaft.stl` was designed for 175° on that assumption.

## What you need

- The ESP32 on its USB cable, one FS0307 with **no horn, cam or shaft attached** (free to spin), the 5 V supply and its screw-terminal adapter.
- Wiring as in the earlier single-servo test: servo white → GPIO32; red → supply +; black → supply −; a wire from supply − to an ESP32 GND pin. The ESP32 stays on USB power. Don't connect supply + to anything on the ESP32.
- A paper protractor under the servo, with a pointer taped to the output shaft, is enough to read the angle. A phone photo at each end works too.

## Flash the bench firmware

This is the same isolated test program from last night's TEST5, plus a `SWEEP` command. It has no Bluetooth; the phone can't connect while it's installed. Restore the production firmware afterward (last step).

From the repository root, with servo power **unplugged** first:

```sh
.venv/bin/pio device list                         # find the port, e.g. /dev/cu.usbserial-0001
.venv/bin/pio run -d firmware/bench-single -j 2 -t upload --upload-port /dev/cu.usbserial-0001
.venv/bin/pio device monitor --port /dev/cu.usbserial-0001 --baud 115200 --echo --eol LF
```

Keep the monitor open for the whole test. Opening and closing it resets the board.

## Safety rules the firmware enforces

- Nothing moves until you type `ARM`, and the permission lasts 10 s.
- While moving, you must type `KEEP` at least every 250 ms, or it stops. A sweep lasts at most 12 s then stops on its own.
- `STOP` always stops it. Any unknown command stops it.

In practice: type `ARM`, press Enter, then `SWEEP 1`, Enter, then hold down `KEEP` + Enter repeatedly (or paste a line of `KEEP` commands). It's clumsy on purpose.

## The test

1. Plug in servo power. Type `STATUS`: expect `ready=1 armed=0 active=0`.
2. `ARM`, then `CENTER`, with a few `KEEP`s. The horn goes to the middle. Mark that angle on the protractor as 0.
3. `ARM`, then `SWEEP 1`, keeping `KEEP` going. The servo holds centre for 1 s, then steps 50 µs further every half second, toward 2500 µs.
4. **Watch and listen.** The horn should keep stepping. The moment it **stops stepping, buzzes, or you hear it strain**, type `STOP`. Then `STATUS`: note `pulseUs`. The last pulse that still produced a step is the top limit. Note the angle.
5. `ARM`, then `SWEEP 0`, same thing the other way, toward 500 µs. Note the bottom pulse and angle.
6. Unplug servo power. Write down: bottom pulse, top pulse, total angle.

If the sweep reaches 2500 (or 500) and the horn is still stepping, it has more travel than we need; the limit is 2500/500.

Do this on **one servo first**. If it's near 175°, test two or three more; they'll vary by a few degrees, which the firmware's per-column calibration absorbs. One that's 15° short would not.

## Reading the result

- **Total angle ≥ ~175°:** print `shaft.stl`. The firmware needs its pulse range widened to your measured bottom/top and its angles set to 0/58/117/175. That's a firmware change I can make from the numbers you write down.
- **Total angle < 175°:** print `shaft4.stl`. The firmware's current angles (0/40/80/120, gaps 20/60/100, tap 13°) already match it. Only the pulse range needs to be whatever you measured for 120° of travel.

Either way, the numbers go into `firmware/production-measurements.local.json` (there's an example file) before the production build will compile.

## Restore the normal firmware

```sh
.venv/bin/pio run -d firmware -e esp32 -j 2 -t upload --upload-port /dev/cu.usbserial-0001
```

## What this test does not tell you

Whether the servo has enough force to lift a pin through the cam. That needs a shaft on the servo and a column assembled: the P1–P5 tests in `cad/README.md`.

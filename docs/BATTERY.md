# Servo power: wall supply vs battery bank

*Oct 17 2026, updated Oct 20. Apart from the one run recorded under [What has been observed](#what-has-been-observed), nothing below has been measured on our hardware. The numbers are datasheet figures and arithmetic. Fill in the test table at the end before trusting either option for a demo.*

**Short answer:** use the **wall supply** for bring-up, calibration and the seated judging demo. Use a **battery bank** only for the walking demo, and only after it passes the four tests below. Bring both to the demo; the wall supply is the fallback.

## What has been observed

One run at HackHarvard 2026, on a 20,000 mAh bank powering the puck and keeping the LiDAR phone topped up, over several hours of use. The bank's charge indicator read **99 %** at the end. Bank model, port, cable and the exact hours were not written down: ______.

What that supports: the README's **"up to 48 hours"** figure. A 20,000 mAh bank is ≈ 74 Wh, ≈ 12 Ah at 5 V after conversion losses, so 48 h means an average draw of about 0.25 A for puck plus phone top-up. A 1 % drop after several hours is consistent with that and probably well under it.

What it does not support: a measured runtime. Bank indicators are coarse (many hold 100 % for a long time and then fall quickly), the current draw was not measured (test 5 is still open), and the phone's own battery state during the run was not recorded. Treat 48 h as a conservative extrapolation until test 4 is run to a meaningful discharge.

## What needs power

| Load | Figure | Source |
|---|---|---|
| 7 × FEETECH FS0307 | Rated 4.8–6 V. Stall current 0.40 A at 4.8 V and 0.50 A at 6 V | Datasheet, as recorded in `docs/HARDWARE-INVENTORY.md` |
| Worst case, all 7 stalled | 7 × 0.5 A = **3.5 A** | Arithmetic |
| Idle and moving current | **Unknown**; not in our docs | Measure (test 5) |
| ESP32 + BLE | Roughly 0.1–0.25 A | Typical figures. It runs on its own USB lead, not the servo supply |

Three facts drive the comparison:

- **The 4.8 V minimum is only 0.2 V under a 5 V supply.** Any drop in the cable or connectors pushes the servos below their rated range. Voltage measured *at the servo screw terminal* is what counts.
- **All seven servos start together at power-up.** Production firmware commands a neutral gap at startup (`docs/SEVEN-SERVO-PRODUCTION.md`). That makes power-up the worst surge, not the steady state.
- **The 1000 µF capacitor does not cover a surge.** Carrying 3 A for 1 ms would drop it ΔV = IΔt/C = 3 A × 1 ms / 1000 µF = 3 V. It smooths fast spikes only.

## The options

- **A. Wall supply (owned).** The Adafruit 5 V / 4 A supply feeds a barrel-to-screw-terminal adapter, which feeds the servo bus.
- **B. Battery bank, USB-A port.** A USB-A to 5.5 × 2.1 mm barrel cable (**still to buy**) feeds the same adapter.
- **C. Battery bank, USB-C port.** A USB-C to barrel cable or trigger board feeds the same adapter. A passive USB-C cable without the 5.1 kΩ sink resistor gets **no power at all** from a USB-C port. With that resistor, the cable can draw up to the 3 A the port advertises, at 5 V. This is the better way to use a bank, if the bank has a USB-C output.

## Comparison

| | A. Wall 5 V / 4 A | B. Bank, USB-A port | C. Bank, USB-C port |
|---|---|---|---|
| **Current available** | 4 A: 0.5 A over the 3.5 A worst case | Usually 1–2.4 A per port; 3 A on some models. Often a shared total across ports | Typically up to 3 A at 5 V |
| **Covers 7 servos at worst case?** | Yes, on paper | **No** at 2.4 A or less. Close at 3 A | Close (3 A vs 3.5 A) |
| **Voltage at the servos** | Regulated 5 V; losses come from wiring only | About 5.0–5.2 V unloaded, then it sags under load. **Thin USB cables add a large drop** (see below) | Same cable-drop issue; usually a heavier cable |
| **During a surge** | Usually a brief dip | Overcurrent protection may **cut the output completely** until replugged or a button is pressed | Same risk, with more headroom |
| **At low load** | Never turns off | Many banks **turn themselves off** after tens of seconds below about 50–100 mA. Idle servos may draw that little | Same, unless the bank has a low-current or always-on mode |
| **Mobility** | Tethered to an outlet; a trip hazard while walking | Untethered | Untethered |
| **Runtime** | Unlimited | Not the limit: a 10,000 mAh bank is ≈ 37 Wh, ≈ 6 Ah at 5 V, so roughly 3 h even at a constant 2 A. Real draw is far lower; see the observed run above | Same |
| **Where it goes** | Table or outlet | Pocket, armband or belt. The pack tray has **no battery bay** (it holds only the breadboard and adapter). About 200 g | Same |
| **What we have** | Everything | Need the USB-A to barrel cable and a bank | Need a USB-C to barrel cable with a 5 V trigger, and a bank with USB-C output |
| **If it fails** | Servo jitter or droop | Pins silently stop responding. The puck has no current or position sensing (`docs/KNOWN-ISSUES.md`), so neither the firmware nor the app can tell | Same as B |
| **Best use** | Bench, calibration, first 7-servo run, seated demo | Last resort | Walking demo |

### Cable drop

The drop is current × round-trip wire resistance, so wire gauge decides whether a bank is usable at all:

| 1 m cable, power conductors | Round-trip resistance | Drop at 2 A | Voltage left at the servos |
|---|---|---|---|
| 28 AWG (common in cheap USB cables) | ≈ 0.43 Ω | ≈ 0.85 V | ≈ 4.15 V: **below rating** |
| 24 AWG | ≈ 0.17 Ω | ≈ 0.34 V | ≈ 4.7 V: below rating |
| 22 AWG (our solid wire) | ≈ 0.11 Ω | ≈ 0.21 V | ≈ 4.8 V: at the limit |

Keep the bank cable short, 0.5 m or less, and buy one that states 20–22 AWG power conductors. The same applies to the run from the forearm pack to the puck: never route all servo current through one breadboard rail.

## Rules for both options

- **Power the ESP32 separately** from the servo supply (its own USB lead or a second bank) so a servo surge can't reset it. Always connect servo supply negative to ESP32 GND; the signals need a common ground. Never join servo supply positive to the ESP32's USB, 3V3 or a GPIO.
- If one bank powers both the ESP32 and the servos, the bank's **total** output rating has to cover both loads.
- Possible firmware change (**not implemented**): stagger the startup moves by about 100 ms per servo. That would cut the power-up surge from 7 servos to one.

## Tests before trusting a supply

Measure at the servo screw terminal with the multimeter. A multimeter averages, so it won't show millisecond dips. The visible symptoms are servo twitching and ESP32 resets (boot messages appearing on serial).

| # | Test | Pass | Wall | Bank |
|---|---|---|---|---|
| 1 | Voltage at the terminal: idle, one servo moving, all seven moving | ≥ 4.8 V in every case | ____ | ____ |
| 2 | Power-cycle the system 10 times (all seven start together) | Supply never cuts out; no ESP32 reset | ____ | ____ |
| 3 | Hold at neutral for 5 minutes with no new commands, then send a band | Supply still on; the pin moves | n/a | ____ |
| 4 | Run the live demo loop for 20 minutes | No dropouts. Record the bank's charge before and after: ___ % → ___ % | ____ | ____ |
| 5 | Current on the 10 A range, in series with the servo + lead: idle, one servo moving, power-up | Write the numbers into `docs/HARDWARE-INVENTORY.md` | ____ | ____ |

**Bank model and port used:** ______  **Cable and gauge:** ______

# FEEL calibration record

**PHYSICAL TESTS NOT RUN. All blanks require real measurements.** Calibration cannot be completed in a software simulator. Read [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md) first; recover the original CAD and production firmware documentation before proceeding.

## Before movement

- [ ] Manual single-column P1–P5 passed and recorded.
- [ ] Exact servo datasheet, board pin map, supply and wiring review completed.
- [ ] Human reviewed board flashing; servo power disconnected during flashing.
- [ ] Mechanism removed from the servo for the initial unloaded check; no hand is restrained by a powered mechanism.
- [ ] Power disconnect is within reach. Record and stop for hard stops, heat, unexpected motion, sustained buzzing, current-limit activation or binding.

Session/date: ____ · Operator/reviewer: ____ · Board/firmware commit: ____ · Servo model/source: ____

## 1. Characterize the unloaded servo first

The handoff calls G1 a `US c 650` → `US c 2500` sweep expecting approximately 175°. **Neither endpoint nor the expected travel has been physically verified here. Do not execute that full sweep blindly.** The command syntax also needs confirmation in recovered production firmware.

1. Read the actual manufacturer's voltage, allowed pulse width/frequency and signal requirements. If they are unavailable, stop powered characterization until the team obtains reliable specifications.
2. Use a documented valid starting command, with the horn/cam unloaded and clearance around the shaft. Check the unit's response, direction, supply and current.
3. In small, observed increments **within the documented limits**, establish usable travel without reaching a mechanical stop. Do not discover limits by holding the servo stalled. Record the measured range; do not assume angle is linear with pulse width.
4. Repeat for the seven operating units and spare. A unit that cannot cover the required mechanism travel safely needs a mechanical/drive review, not wider guessed pulses.

| Servo ID | Datasheet voltage/pulses/frequency | Tested safe pulses | Measured usable travel | Supply/current observation | PASS/FAIL / evidence |
|---|---|---|---|---|---|
| 0 | ____ | ____ | ____ | ____ | ____ |
| 1 | ____ | ____ | ____ | ____ | ____ |
| 2 | ____ | ____ | ____ | ____ | ____ |
| 3 | ____ | ____ | ____ | ____ | ____ |
| 4 | ____ | ____ | ____ | ____ | ____ |
| 5 | ____ | ____ | ____ | ____ | ____ |
| 6 | ____ | ____ | ____ | ____ | ____ |
| Spare | ____ | ____ | ____ | ____ | ____ |

## 2. Measure the parts before choosing a coupling

Use the reference datums in the recovered `cad/README.md`; do not infer axes from this table. Enter actual values in `cad/params.scad`, retain a measurement record, rebuild and inspect the resulting parts. If that file is absent, the update is blocked.

| Measurement (mm unless stated) | Value / instrument |
|---|---|
| Servo body, three dimensions | ____ / ____ / ____ |
| Spline axis to nearest case end | ____ |
| Tab span / thickness / distance behind spline face | ____ / ____ / ____ |
| Spline height / diameter | ____ / ____ |
| Horn hub diameter | ____ |
| Horn hub bottom / top above case | ____ / ____ |
| Horn arm thickness / width / first hole radius | ____ / ____ / ____ |
| Hole coupon free-sliding fit, before / after finishing | ____ / ____ |
| Breadboard / board / barrel adapter dimensions | ____ |
| CAD commit / print material and settings / coupon evidence | ____ |

Test C1/C2/C3 coupling options only after the matching geometry exists. Select one with secure retention and no slip through the intended range; record it. Do not cut the servo lower ear without the explicit human fit/retention review in the bring-up guide.

## 3. Calibrate the powered test column

The handoff's **nominal cam coordinates** are bands 1–4 at **0°, 58°, 117°, 175°**, gaps halfway between neighboring bands, and a **21° dip toward the relevant gap** for highlighting. These are design/model values, **not universal servo electrical endpoints** or measured output. Confirm the real geometry, motor direction and safe offset range before commanding them.

1. Power off, fit the reviewed coupling, and align the servo/cam using the recovered assembly reference. Do not rotate a powered servo by hand.
2. Start within the previously measured safe range. Use recovered firmware's explicit single-column bench mode; verify whether its watchdog applies to bench commands. Send each supported command separately and observe.
3. Check each band, all required gap positions, disappearing-pin transitions and taps. Only the intended pin should activate. Verify that calibrated commands plus tap/gap excursions remain inside the safe range.
4. Adjust offset using the documented units and sign. The handoff names `B 0 1` through `B 0 4`, `HL 0`, `CAL 0 o`, and `CAL save`; **these are historical references, not tested commands in the recovery software**. Do not paste the notation `1..4` as a command.
5. Save only a validated configuration. Power-cycle and verify the same behavior and safe startup. Recheck P1–P5 under power, recording any difference from hand operation.

Nominal stroke target from v7: **2 mm**; nominal tap dip: **1 mm**. Actual acceptance tolerances must come from recovered CAD specifications and measured fit. Never label nominal values “measured.”

| Column | Servo ID / coupling | Offset (units/sign) | Actual band travel 1/2/3/4 | Gap/tap/neighbor check | Power-cycle check | Evidence / result |
|---|---|---|---|---|---|---|
| 0 | ____ | ____ | ____ | ____ | ____ | ____ |
| 1 | ____ | ____ | ____ | ____ | ____ | ____ |
| 2 | ____ | ____ | ____ | ____ | ____ | ____ |
| 3 | ____ | ____ | ____ | ____ | ____ | ____ |
| 4 | ____ | ____ | ____ | ____ | ____ | ____ |
| 5 | ____ | ____ | ____ | ____ | ____ | ____ |
| 6 | ____ | ____ | ____ | ____ | ____ | ____ |

## 4. Measure failure behavior separately from movement

With a camera/logic trace or other documented measurement method, record last valid packet time, firmware neutral-command time and completed physical pin-return time separately. The handoff requires a **500 ms failsafe**; a timely software command cannot prove timely physical return. Confirm corrupted/rejected packets do not keep stale guidance alive in the recovered firmware.

| Case | Last valid packet / neutral command / pins down | Expected vs observed | Result / evidence |
|---|---|---|---|
| Sender stops / timeout | ____ / ____ / ____ | ____ | ____ |
| BLE disconnect | ____ / ____ / ____ | ____ | ____ |
| Invalid packet stream | ____ / ____ / ____ | ____ | ____ |
| Phone reports lost/stale tracking | ____ / ____ / ____ | ____ | ____ |
| Restart / reconnect | ____ / ____ / ____ | ____ | ____ |

If pins cannot return with power lost, document that mechanical behavior explicitly; a software watchdog cannot correct an unpowered or jammed mechanism. Confirm the app shows unavailable guidance rather than interpreting neutral pins as a guaranteed clear path.

## 5. Confirm phone-to-palm orientation

Record phone mounting orientation, hand, wrist/finger direction and physical center column. From a stationary pose, move a known target to left, center and right and compare the app's direction, packet column and physical response. Repeat after phone rotation. Then test each distance band using measured distances and documented boundary rules.

Mounting convention: ____ · Left/center/right trials: ____ · Distance trials: ____ · Uncertainty behavior: ____

Optional Nearby Interaction: actual phone pair ____ · direction sign ____ · angular coverage ____ · measured update rate ____ · unavailable/interruption behavior ____. Skip the feature if its physical behavior remains unresolved.

Final release decision: ____ · Remaining failures: ____ · Reviewer/date: ____

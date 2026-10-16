# FEEL hardware bring-up

**Status: PHYSICAL HARDWARE NOT VERIFIED.** No servo, board, printed part, phone sensor, or completed puck was available to this engineering session. Blank records below mean **NOT RUN**, not pass. A software simulation cannot measure friction, torque, skin contact, current, or reliability.

This guide organizes the work in `HANDOFF-v7.md`. The original `cad/README.md`, CAD/STLs, production firmware, and iOS apps were missing from the supplied repository. **Recover and review those sources before printing, finishing, wiring for operation, or flashing.** This is a bring-up checklist, not a replacement for the missing assembly drawings. New portable test code is not board firmware.

## 1. Lay out and identify the parts

Photograph each numbered group with its label visible. Record substitutions before using them.

| Photo | Checklist | Record |
|---|---|---|
| A | [ ] Exact ESP32 board, readable model/revision, board pinout, USB cable | Board/revision: ____; pinout source: ____ |
| B | [ ] Eight FS0307 servos per the handoff: seven operating, one spare; supplied horns, screws, leads | Manufacturer/model/revision: ____; datasheet: ____ |
| C | [ ] Regulated servo supply, adapter, rated power distribution, switch/disconnect, meter | Voltage/current rating: ____; connector polarity: ____ |
| D | [ ] Unpowered single-column prints and hole coupon from recovered `stl/test/` | CAD commit: ____; material: ____; print settings: ____ |
| E | [ ] Pins, foam/template, chosen shaft, guide and face components | Shaft A/H/G: ____; foam configuration: ____ |
| F | [ ] Calipers, appropriate finishing tools, 400/1000-grit abrasives, approved dry lubricant | Tool/material compatibility checked by: ____ |
| G | [ ] Full puck prints, fasteners, straps, strain relief, forearm pack | Full puck deferred until one column passes: ____ |
| H | [ ] iPhone 14 Pro Max; Mac/Xcode; second compatible phone only for optional phone finding | Phone/iOS: ____; Mac/Xcode: ____ |

Handoff supplies, **not measured fit guarantees**: half-size 400-point breadboard; barrel adapter; 1000 µF capacitor; two pack straps; eight M3 × 12 screws; 2 mm and 3 mm craft foam; 25 mm elastic/Velcro. Confirm capacitor voltage rating and polarity. Confirm screw fit and retention in recovered CAD. Keep an inspectable, removable assembly during bring-up; do not glue it shut before inspecting operation.

## 2. Review power with everything disconnected

Have the team member responsible for electronics sign this section before power or wiring changes. Record the actual servo manufacturer's operating voltage, allowed signal pulse range, signal-level requirements, current information, and connector pin order. Do not infer the pin order from wire color alone.

- [ ] Servo positive power comes from a supply and distribution path rated for the measured/specified load. **Never power servos from GPIO or the ESP32's 3.3 V output. Do not route seven-servo current through undersized breadboard rails.**
- [ ] Servo supply negative and ESP32 ground share the intended signal reference. Trace each connection against the exact board and servo documentation with power off.
- [ ] ESP32 power follows its actual development-board documentation. A chip's supply specification is not permission to apply that voltage to any board pin.
- [ ] USB and external power paths are reviewed to prevent unintended backfeeding. Do not join two positive supplies by assumption.
- [ ] Measure supply voltage and polarity before plugging in a servo. Confirm current limiting/protection and an accessible power disconnect.
- [ ] Secure leads and terminals; add strain relief; check for shorts and exposed conductors. The handoff's capacitor is not a substitute for an adequate supply.

| Check | Measurement / evidence |
|---|---|
| Servo voltage range, manufacturer source | ____ |
| Servo pulse range and signal requirements, manufacturer source | ____ |
| Supply no-load voltage and polarity | ____ |
| Load/current budget and wire/connector ratings reviewed | ____ |
| Ground continuity / positive rails kept as designed | ____ |
| Wiring photo and electronics reviewer/date | ____ |

### Signal map from the handoff

Only for a **classic ESP32** whose exact board exposes these pins and whose recovered firmware uses this mapping. These are GPIO numbers, not connector-position numbers. Confirm physical column orientation using the recovered CAD; do not assume left/right from an unlabeled part.

| Column / packet field | Handoff GPIO |
|---|---:|
| 0 / b0 | 32 |
| 1 / b1 | 33 |
| 2 / b2 | 25 |
| 3 / b3 | 26 |
| 4 / b4 | 27 |
| 5 / b5 | 14 |
| 6 / b6 | 13 |

**ESP32-S3 mapping is unresolved.** The handoff's claim that S3 built does not establish a wiring map. Do not copy the classic mapping to an S3. Recover board configuration and consult its schematic, flash/PSRAM usage, and available pins first.

## 3. Assemble one hand-cranked column, without power

1. Recover `cad/README.md` and the matching CAD/STLs. Read “Assemble the crank rig,” hole finishing, pin preparation, foam placement, shaft installation, and P1–P5 criteria. If these remain unavailable, **stop mechanical assembly here**; do not reconstruct guide geometry from this checklist.
2. Print only the test column and coupons first. The handoff lists frame, strip, shaft variants A/H/G, two pin-tip variants, guide, crank, dummy servo, foam template, and hole coupon. Couplings wait for actual horn measurements.
3. Follow the recovered instructions to finish eight test-column guide holes and smooth pin tips. The handoff mentions an 11/64-inch finishing bit and 400 → 1000 grit; confirm these against the actual revision, coupon fit, and tool setup before removing material. No heat polishing.
4. Fit the foam and chosen shaft as specified. Preserve each pin's position and length. Check free travel gently by hand; never force a jam.
5. Label the wrist and finger ends, columns and pin bands. Photograph the mechanism before closing it.

**Do P1–P5 manually before attaching a powered servo.** These practical observations supplement the missing original tolerances; they do not invent them. Record those tolerances from recovered `cad/README.md` before declaring a mechanical pass.

| Test | Action and required observation | Record |
|---|---|---|
| P1 — selection | Slowly select all four bands and intervening gaps. Exactly one intended pin is up for a band; no pin remains up in the gap. Measure travel. | Band/travel measurements: ____; unintended pins: ____; PASS/FAIL: ____ |
| P2 — return | Repeat on the side and upside down. All intended returns occur without gravity assistance or shaking. | Orientations/repeats: ____; failed returns: ____; PASS/FAIL: ____ |
| P3 — thumb hold | After free travel passes, apply gentle, comfortable thumb contact. Check selection/return under that contact. Stop at discomfort, binding, or pin tilt. | Contact method: ____; observations: ____; PASS/FAIL: ____ |
| P4 — endurance | Perform 100 complete four-band cycles using the same documented sequence. Stop and record any jam instead of forcing it. | Sequence: ____; completed: ____/100; jams: ____; PASS/FAIL: ____ |
| P5 — highlight | Manually demonstrate the intended tap dip and return. Watch all neighboring pins throughout; none should lift unintentionally. | Band(s)/repeats: ____; neighbor motion: ____; PASS/FAIL: ____ |

Tester/date: ____ · CAD revision: ____ · Photo/video references: ____ · Original tolerance source: ____

**P2 or P4 fails → stop expansion.** Investigate fit, alignment and return using the recovered CAD guidance; repeat the whole sequence after a change. Do not compensate for a jam by commanding more servo force. Tip and 11/12 mm pitch comparisons are optional seated comfort experiments, not evidence of navigation performance.

## 4. Measure and calibrate one real servo

Follow [CALIBRATION.md](CALIBRATION.md). Keep the mechanism disconnected for the initial servo check. The handoff's G1 `650` to `2500` µs range is **unverified and is not a safe starting prescription**. Establish the real unit's supported range and unloaded behavior before coupling a cam.

Board flashing requires a human review of the exact firmware, board selection and pin map; keep servo power disconnected during that step. The historical serial commands in the handoff are not proof that any executable in this repository supports them.

Measure servo and horn, update the recovered `cad/params.scad`, rebuild, inspect coupling fit, and then calibrate one powered test column. Pass its band, gap, highlight, power and timeout checks before fitting the rest.

## 5. Expand one column at a time

1. Recover “The full puck” in `cad/README.md` and confirm its CAD revision matches the parts. The handoff describes 28 pins and 56 guide holes; it does not supply their missing assembly geometry.
2. **Lower-ear clipping is destructive.** The handoff requests it, but do not cut a servo until the responsible human checks the exact servo, recovered CAD retention design and fit. Record approval and test one spare/dummy fit first. No automatic cutting or guessed cutting depth.
3. Assemble in the recovered order. Keep pin locations labeled, check clear travel, protect cables through the wrist slot, and fit strain relief and the forearm pack.
4. Add one calibrated servo at a time. Check bands/gaps/taps and idle behavior on each; record supply voltage under load, current and reset behavior before adding another.
5. After seven individual passes, verify simultaneous commanded movements, power stability, disconnect/timeout behavior, and mechanical return. Do not deliberately stall servos. Any unexpected motion, heat, persistent buzzing, jam, or supply collapse means power off and investigate.

## 6. Integrate real phone input last

- [ ] Recover production iOS/BLE code and build/sign it with the team's reviewed setup. Record app/firmware commits and actual phone/board versions.
- [ ] Verify physical direction and pin mapping using known left/center/right targets while stationary. Bands run wrist → fingers from near → far. Only one pin per column is selected.
- [ ] Observe real nine-byte packets, real pin response, and real time since the last accepted packet; confirm the 500 ms watchdog behavior. A neutral command timestamp is not the same as completed mechanical return time.
- [ ] Test tracked, stale/lost-depth, phone interruption, BLE disconnect/reconnect, malformed-input and target-loss cases safely at the bench. Visible uncertainty must not be presented as a clear path.
- [ ] Test LiDAR and each claimed detector independently on the actual phone, recording latency and failures. Do not count a photo detector test as live detection.
- [ ] Optional “find teammate”: test both phones, Nearby Interaction availability, direction sign and refresh rate. The handoff target is an angle across ±45° at at least 5 Hz; record observations. Omit this feature if it fails.
- [ ] Only after bench passes: clear, supervised indoor route with a spotter and an immediately accessible stop. Obtain consent for feedback/recordings. No unsupervised blindfolded walking; FEEL is a prototype, not a replacement for a white cane or other mobility aid.

Before any walking comparison, record route length, lighting, obstacles, spotter and stop conditions. If measured, report separate time/speed and contact observations with and without FEEL, trial counts and limitations; do not extrapolate a small demo into clinical benefit.

## First three team actions

1. Recover the original CAD/STLs, firmware and iOS sources from the machines described in the handoff; pin their revisions and read the missing assembly/board instructions.
2. Identify the actual electronics and supply, photograph/measure them, and complete the power review while printing and manually testing one column.
3. After P1–P5 pass, perform unloaded servo characterization and one-column calibration; only then expand and attempt real phone integration.

## Sources and scope

- Team-provided `AGENTS.md` and `HANDOFF-v7.md`: intended parts, geometry, staged tests and historical interfaces. Their pre-existing verification claims have not been reproduced here.
- [Espressif ESP32 hardware design checklist](https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32/schematic-checklist.html) and [ESP32-S3 checklist](https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32s3/schematic-checklist.html), consulted October 16, 2026: board-family-specific power/GPIO review. These do not supply FS0307 operating limits or replace the chosen development-board schematic.

No FS0307 manufacturer datasheet or physical measurements were supplied. Those remain required inputs.

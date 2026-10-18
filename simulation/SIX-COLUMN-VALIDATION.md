# Six-column replay validation

Validation date: 2026-10-18 UTC. Software simulation only; no physical movement, BLE radio, real LiDAR or user perception was verified.

## Baseline and correction

A pristine archive of `origin/main` commit `88c3900` ran `python3 simulation/run.py --repeat 1 --no-web`. Its 12 packet/firmware digests and score results were identical to the integration checkout before these fixes: **7 FAIL, 3 KNOWN, 2 PASS**. The failures therefore predate this integration. Evidence is retained in [six-column-validation.json](six-column-validation.json).

The scorer and labels still assumed seven physical sectors. The harness now scores only physical wire slots 1–6, divides flicker by six, and separately requires reserved b0 to remain zero and never highlighted on both phone and firmware output. A reserved-slot violation always fails, including otherwise known or unlabelled scenarios. The nine-byte ABI, production encoder, controller, calibration angles, and all existing accuracy/flicker thresholds were unchanged.

Geometry labels use six 15° sectors. The wall labels are derived analytically from `t = (5 - R*cos(innerBearing)) / 0.5`, for band boundaries R=4, 2.5, 1.6, 0.9 m and sector-pair inner bearings 0°, 15°, 30°. Each transition retains a ±0.35 s exclusion window.

The original 1 m doorway geometry remains as a known resolution limitation. A separate 1.2 m doorway is a passing positive control. The old frozen `baselines/` files are retained unchanged as historical seven-sector evidence; changed-baseline notices are expected and do not imply a new production regression. No baseline was regenerated merely to obtain a pass.

## Results

- `python3 -m unittest discover -s simulation/tests -v`: **4 PASS**. The independent scorer tests detect a real active-column miss, enforce b0 on both sources and protect the six-column flicker denominator.
- `python3 simulation/run.py --repeat 3 --no-web --no-build`: **13 scenarios, 9 PASS, 4 KNOWN, 0 FAIL**, all 13 deterministic across three runs. **Zero reserved-slot violations**. Existing binaries came from the current integration sources; this patch changes no compiled production code.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 simulation/unit_tests.py`: **360/360 XCTest cases PASS, 0 skipped**, plus **24/24 app-to-firmware pin command cases PASS**. The first restricted run could not write Xcode's existing module cache; the permitted retry passed.
- `node --check /private/tmp/feel-report-script.js` (the standalone report script) and `git diff --check -- simulation`: **PASS**.

Local logs: `/private/tmp/feel-six-column-replay-final.log` and `/private/tmp/feel-replay-unit-diagnostics.log`. Pin diagnostics assert the current configured angles 0°, 58°, 116°, 174° and pulses 650, 1263, 1876, 2489 µs, against `firmware/include/feel/controller.hpp`. These are software constants, not measured travel or pulse verification on hardware.

The four remaining synthetic limitations are narrow-door angular resolution, lintels inside the obstacle height window, intermittent target highlights with slow detections, and single-sample depth outlier flicker. The lintel scenario is also narrow: it demonstrates the expected clear-opening mismatch, but does not alone isolate which obstruction dominates. A pass does not establish physical safety or mobility performance.

## Other branch review

`replay-pin-diagnostics` at `6d41c62` independently fixes active-slot scoring and several labels. Its additive `pin_diagnostics.py` and `unit_tests.py` were ported. The latter now refuses to report PASS when no XCTest cases were parsed. The diagnostic angle/pulse expectations match the current firmware constants; no servo configuration was changed. Its widening of the original doorway and change from a clear-lintel expectation to an obstructed one were not applied: this report retains the existing limitation and adds a separate positive control.

`ethan/cad` commit `48774f0` mixes CAD, perception, replay and UI changes. Its geometry label generator explicitly assumes seven sectors, and it replaces frozen baselines. Its four new synthetic scenes and snapshot comparison exports have not been imported or validated here; they require a separate six-sector adaptation. Do not cherry-pick that commit wholesale into this bounded simulation correction.

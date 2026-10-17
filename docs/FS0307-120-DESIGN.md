# FEEL — FS0307 nominal 120° design

October 16, 2026. User decision: **assume 120° for the design**.
This supersedes the historical 175° cam/controller layout. It is not a physical
measurement of the received servo. Physical PWM remains disabled by default.

## Final design

| Parameter | Previous layout | Current layout |
| --- | --- | --- |
| Four band positions | 0 / 58 / 117 / 175° | **0 / 40 / 80 / 120°** |
| All-pins-down gaps | 29 / 87.5 / 146° | **20 / 60 / 100°** |
| Startup neutral | 29° | **20°** |
| Highlight dip toward nearest gap | 21° | **13°** |
| Highlight positions for bands 1–4 | 21 / 37 / 138 / 154° | **13 / 27 / 67 / 107°** |
| Nominal pulse envelope | 650–2500 µs | **900–2100 µs** (60° → 1500 µs) |
| Cam lobe half-width | 24° | **12°** |
| Pin stroke | 2 mm | **2 mm, retained** |

A tie between gaps selects the lower angle. After clearing bands 1–4, the
corresponding neutral commands are 20 / 20 / 60 / 100°. The nine-byte Bluetooth
packet, seven columns, four distance bands and iPhone UI remain unchanged.

Simply changing the angle constants was insufficient: the old 24° lobe profile
would lift neighbouring followers in the new 20° neutral gap. The redesigned
profile is narrower, while retaining the existing conical follower and nominal
2 mm lift. Cam simulation uses polygon vertices exported by OpenSCAD, including
edge contact with the finite pin tip; it does not equate radial height to pin lift.

## Firmware behavior

- Named constants define the angular range, band/gap positions and tap amplitude.
- Commands are bounded to 0–120° and 900–2100 µs; old raw endpoints are rejected.
- Calibration offsets remain bounded and endpoint commands clamp to the envelope.
  Clipping can reduce physical alignment/travel; measure every band/gap after
  calibration. An offset is not permission to exceed the nominal range.
- New NVS key `offsets_120_v2` and schema version 2 prevent old 175° offsets from
  being reused. Invalid records are rejected atomically.
- `FEEL_ENABLE_SERVO_OUTPUT` remains **0** by default. A deliberate output-enabled
  build still requires explicit measured safe pulse bounds. Compilecheck binaries
  use software fixtures and refuse upload; they are not hardware-ready firmware.

## Executed validation

| Check | Result |
| --- | --- |
| Firmware controller host tests | PASS: 41 cases |
| Firmware CLI / configuration / upload guards / bench input | PASS: 17 / 10 / 6 / 4 checks respectively |
| ESP32 default firmware build | PASS |
| ESP32 enabled-path compile fixture | PASS; no upload |
| Compiled Swift → packet → compiled C++ replay | PASS: 2,634 assertions, 558 states; includes angle/pulse bounds on every state |
| Reference Python model | PASS: 51 tests, 18 scenarios / 77 asserted steps |
| Build tooling regressions | PASS: 7 tests |
| Actual-CAD / compiled-firmware contract | PASS: 104 checks across band, gap, tap, timeout and pulse mappings |
| Actual OpenSCAD cam/contact simulation | PASS: 80 checks across A/H/G profiles; 0.1° sampled shaft sweep |
| CAD tool regressions | PASS: 15 tests, including rejection of the old wider profile |
| Full STL export | PASS: 24 parts; see CAD manifest and mesh report |
| Independent code review | No actionable source regression found; stale active iOS documentation corrected |

Commands include:

```sh
sh firmware/test/run_host_tests.sh
.venv/bin/pio run -j 2 --project-dir firmware -e esp32 -e esp32-compilecheck
swift build -j 2 --package-path ios/Shared/FeelCore
python3 validation/production/run.py --output .artifacts/fs0307-120/production
python3 -m unittest discover -s validation/tests -v
python3 validation/run_scenarios.py --output .artifacts/fs0307-120/reference
python3 validation/check_cam_contract.py
python3 cad/tools/cam_sim.py --step 0.1
python3 -m unittest discover -s cad/test -v
sh cad/build.sh
```

OpenSCAD 2026.10.15 official macOS snapshot was used for this local validation;
its downloaded SHA-256 was verified. The older Intel-only stable binary could
not run on this Mac. The temporary tool lives outside the repository; future
runs need an available compatible OpenSCAD executable on PATH. ESP32 uses the
existing pinned PlatformIO/Espressif toolchain. This change did not rerun the
ESP32-S3 build or the full iOS UI/perception suite.

Current geometry evidence: `cad/evidence/`, `cad/VALIDATION.md`, and the generated
`stl/manifest.json`. Production/reference replay evidence: `.artifacts/fs0307-120/`.
Historical `docs/evidence/v1/` results describe the earlier layout and remain
preserved as provenance. They must not be substituted for these revision checks.

## Device and physical status

**No new firmware was flashed and no servo was energized during this revision.**
The ESP32 still has the earlier PWM-disabled firmware from the successful local
Mac/iPhone bring-up. Its recorded 14 accepted Bluetooth messages verify that
prior setup, not the new physical geometry. FEEL remains installed on the iPhone;
no app change is needed for this angle mapping.

The narrower cam has steeper flanks. Ideal geometry does not establish acceptable
side load, friction, torque, return force, backlash, tolerances or tactile feel.
Do not reuse old 175° shafts; regenerate parts from the new parameters. Existing
measurement/print-ready gates remain in place.

Next: identify the actual power source and connection parts, verify polarity and
supply compatibility, print/finish a single manual test column, complete P1–P5,
measure safe unloaded servo behavior, then integrate one powered column. Expand
to seven only after the single-column checks pass. The physical FS0307 travel,
horn fit, voltage documentation discrepancy and force/return remain unverified.

## Manufacturer reference

[FEETECH FS0307 datasheet, page 2, section 5](https://www.feetechrc.com/Data/feetechrc/upload/file/20220608/6379029528194935652722624.pdf):
nominal 120° for 900–2100 µs. The [product webpage](https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html)
also lists 120°, but its voltage range conflicts with the PDF. The user's design
choice resolves the nominal angular requirement; it does not resolve actual
power compatibility or certify a physical unit.

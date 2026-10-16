# FEEL V3 release status

**V1 and V2 software: PASS. V3 available local checks: PASS; native Apple gate
FAIL: one QR test remains after the third hosted run. Physical hardware: NOT VERIFIED.** October 16, 2026.

V3 was created in isolated branch `feel/v3-advanced` only after V1 hosted run
38972250150 and V2 run38974519620 passed all four jobs, including app/UI tests,
simulator builds and unsigned device builds. Their source branches are preserved.
See `evidence/v1/github-actions.json` and `evidence/v2/github-actions.json`.

V3 adds explicit on-device English/Spanish commands with typed fallback/readback,
one local persistent AR world map and its multiple bookmarks/Return point,
inactive-until-relocalized restoration, adaptive target cadence and Vision
barcode/QR finding. Protocol, firmware and mechanics are unchanged.

| Check | Actual result |
|---|---|
| Production Swift tests | 90 PASS, including 32 new V3 tests |
| Production Swift CLI | Build PASS |
| Firmware regressions | 38 cases + 17 CLI + 6 board + 6 upload guards PASS |
| V1 packet/controller replay | 1,518 assertions, 558 states PASS |
| V2 spatial replay | 358 assertions, 43 states PASS |
| V3 advanced replay | 1,441 assertions, 156 states PASS |
| Advanced recorded viewer | Browser controls, 28 pins, desktop/mobile PASS |
| Independent source review | Complete; no unresolved critical/high finding |
| Native Apple builds/app/UI tests | Third hosted run FAIL: 1 QR app test; all 3 UI tests PASS; input-path diagnostics pending |
| Actual speech, maps, camera, AR/BLE/NI and tactile hardware | NOT VERIFIED |

Command: `python3 scripts/run_advanced_checks.py --output .artifacts/v3-validated-complete`.
Actual exit 2: six available checks PASS, one Apple gate BLOCKED. Evidence is in
`evidence/v3/report.json` and adjacent logs; `TEST-REPORT.md` explains earlier
failures and fixes. An actual completed XCTest transcript, not just process exit,
is required. No native test result is inferred from Linux syntax parsing.

The V1 CAD and embedded source are unchanged; their prior physical limitations
still apply. PWM is disabled by default. No phone, board, servo, microphone or
printed assembly has been physically tested by this build environment.

Next human actions:

1. Clone `feel/v1-foundation` on the Mac and follow `SETUP-MAC-ESP32.md` for the
   default output-disabled ESP32 build and serial STATUS check.
2. Identify the exact servo variant and measure supply polarity/voltage and
   mechanical fit before the single-column powered procedure.
3. Use a LiDAR iPhone for the device checks in ADVANCED.md after bench bring-up;
   keep actual results separate from simulation.

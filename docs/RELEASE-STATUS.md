# FEEL V3 release status

**V1, V2 and V3 software: PASS. Physical hardware: NOT VERIFIED.**
Validated October 16, 2026. This is a greenfield recreation, not recovered original source.

All four jobs passed in [hosted run 38981718320](https://github.com/MartinPuli/hackharvard/actions/runs/38981718320)
for source commit `61460a2f787ed52b328a74874afd62a5c7220d07`, tree
`2663e23ad0bf0006b0fea8b74ec95f54c8dc0a4d`. This documentation-only follow-up
records that result without changing tested application, firmware or CAD source.
Exact job metadata, artifact IDs and excerpts are in `evidence/v3/github-actions.json`,
`ios-ci-final.log` and `hosted-final-excerpts.log`.

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
| CAD exports and checks | 24 STL exports, 78 cam checks, 13 tool tests PASS |
| Embedded builds | ESP32, ESP32-S3 and both enabled-output compile fixtures PASS |
| Advanced recorded viewer | Browser controls, 28 pins, desktop/mobile PASS |
| Independent source review | Complete; no unresolved critical/high finding |
| Native Apple tests | Xcode 16.4: 22 app tests + 3 UI tests, zero failures; actual Vision QR request PASS |
| Native Apple builds | Lantern tests, Beacon simulator, and both unsigned iPhone builds PASS |
| Actual speech, maps, camera, AR/BLE/NI and tactile hardware | NOT VERIFIED |

Command: `python3 scripts/run_advanced_checks.py --output .artifacts/v3-validated-complete`.
The historical Linux execution returned 2: six available checks PASS, one Apple
gate BLOCKED on that host. The hosted native run above closes that software gate.
Local evidence is in
`evidence/v3/report.json` and adjacent logs; `TEST-REPORT.md` explains earlier
failures and fixes. An actual completed XCTest transcript, not just process exit,
is required. No native test result is inferred from Linux syntax parsing.

The earlier failed native runs remain in the evidence directory. Their diagnostic
matrix isolated revision-dependent barcode behavior on the iOS 26.2 simulator:
revisions 1/2 decode the fixture, while 3/4 return no observations. Simulator builds
now select supported revision 2; device revision and compute defaults are unchanged.
Real-camera detection on a phone remains unverified. See TEST-REPORT.md for the
full failure history and final run rather than treating a fixture as device proof.

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

# FEEL V2 release status

**V2 portable software checks: PASS. Native iOS UI gate: FAIL, correction in progress.
Physical hardware: NOT VERIFIED.** October 16, 2026.

V1 was validated first and preserved on `feel/v1-foundation`; its source is now
published at commit `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`. That remote tree
exactly matches the reviewed local V1 snapshot. All four hosted jobs, including
iOS app/UI tests and simulator/unsigned-device builds, passed in run38972250150.
See `evidence/v1/github-actions.json`. V2 native CI is in progress from draft PR #3.

This isolated `feel/v2-spatial-memory` branch adds volatile bookmarks, Remember,
Recall, explicit Set Return Point/Return, multiple selection/rename/delete,
accessible controls and a production-backed replay. Memory resets when the AR
coordinate frame resets. Offscreen, behind, distant or different-level places do
not fabricate a target highlight. Closer obstacles remain encoded.

| V2 check | Result |
|---|---|
| Production Swift tests | 58 PASS, including 20 spatial-memory tests |
| Production Swift CLI build | PASS |
| Firmware host/controller regressions | PASS: unchanged V1 firmware |
| Preserved V1 packet/controller replay | PASS: 1,518 assertions, 558 states |
| Spatial-memory → packet → controller replay | PASS: 358 assertions, 43 states |
| Recorded spatial viewer | PASS browser rendering/controls/mobile layout |
| Apple-framework builds and app/UI tests | First hosted run: app compiles, 6 unit tests PASS; 2 UI tests ran with 3 assertions failing; correction awaiting rerun |
| Printed mechanics, servo/electrical, actual AR/BLE/NI/touch | NOT VERIFIED |

Command: `python3 scripts/run_spatial_checks.py --output .artifacts/v2-validated`.
The final run returned2 because its Apple check is BLOCKED; all five available
checks passed. The host invocation used a PTY to avoid this environment's
intermittent `/proc` process-monitor failure. Earlier failed wrapper attempts
were environment failures, not successful tests; the final logs and independent
58-test direct run are the evidence. See `TEST-REPORT.md` and `evidence/v2/`.

V1 CAD, protocol and embedded source are unchanged. Their 24 exports,78 cam
assertions,13 tool tests and four embedded builds remain the V1 evidence; these
were not needlessly repeated as new V2 tests. PWM remains disabled by default.
V3 remains pending until the newly available native gate passes. The initial
failed run is preserved in `evidence/v2/github-actions-initial-failure.json`.

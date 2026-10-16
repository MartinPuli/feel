# FEEL V2 release status

**V2 available software checks: PASS. Apple-platform/device checks: pending.
Physical hardware: NOT VERIFIED.** October 16, 2026.

V1 was validated first and preserved on `feel/v1-foundation`; its source is now
published at commit `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`. That remote tree
exactly matches the reviewed local V1 snapshot. Mac CI is now running from draft
PR #2; no hosted pass is claimed until the actual result is inspected.

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
| Apple-framework builds and app/UI tests | NOT RUN here; Linux lacks Xcode |
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
V3 is the next isolated milestone after this available-check gate.

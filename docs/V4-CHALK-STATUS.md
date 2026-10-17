# FEEL V4 release evidence

Status: LOCAL SOFTWARE CHECKS PASS; LIVE ACCESS BLOCKED. No live Chalk or physical pass is claimed.

| Requirement | Current evidence |
| --- | --- |
| Isolated V4 based on validated V3 | Worktree `/tmp/feel-v4-chalk`, baseline `e56e141` |
| Real Chalk Gateway integration | Implemented in `services/chalk/server.py`; transport tested with fixtures, real access pending |
| Explicit feedback and retained-context policy | Implemented, consent/TTL/session-isolation tests PASS |
| Replay and hosted evaluation workflow | Implemented; real SDK 2.13.7 installed, help/import verified without deployment; hosted run pending |
| iOS cloud controls and stale-response handling | Implemented; 37 app tests PASS (13 new cloud cases), 10 Lantern UI + 2 Beacon UI PASS |
| Backend/local contract tests | 28 PASS; 11 tooling/report tests PASS; retained adjacent logs |
| iOS native tests and device compilation | All above tests and both unsigned device builds PASS; see `evidence/v4-chalk/ios-final.log` |
| Actual Chalk request and latency measurement | NOT RUN: hackathon signup requires .edu; attempted account ineligible |
| Hosted Chalk evaluation with row-level results | Pending |
| English demo and architecture guide | `V4-CHALK.md` |
| Publication | Release branch `feel/v4-chalk`; current GitHub commit identifies the published handoff |
| Physical navigation/servo validation | Not verified by this integration |

No automatic claim of better accuracy, sub-second inference, successful navigation,
or prize eligibility follows from the existence of code or tests.

The user requested publication for Benjamin to continue obtaining access and live
validation. See `HANDOFF-BENJAMIN-V4.md`. Mock 24-case results are retained solely
to exercise report/contract plumbing; their scores and near-zero timing are not
model accuracy or real inference measurements.

Hardware boundary: 67 protected firmware/CAD/protocol/tactile/BLE files match
validated V3 exactly. No flash, installation or electrical change was performed.

Independent review: backend author reviewed iOS guards and schema; iOS author
reviewed backend integration. Parent reran server/tooling tests and corrected
report comparison checks. The first UI run was deliberately interrupted after
XCTest attempted to tap an offscreen disclosure; the test now scrolls to the
control above Stop and retains the assertions. The final full native run passed.

Hosted GitHub Actions were not used as evidence for this release. No new hosted
pass is claimed. V3 portable/firmware/CAD results apply to the unchanged layers;
those full suites were not unnecessarily rerun for this application integration.

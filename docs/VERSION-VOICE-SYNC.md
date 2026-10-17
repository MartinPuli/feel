# October 17 V1 voice synchronization

Initial source main: `6ad7004`. V1 remains on main; version-specific code stays isolated.
Concurrent published main advanced to `76e0453`; the follow-up below incorporates
that snapshot without overwriting its Where-is work.

## V2 Spatial Memory

Integrated main's OpenAI realtime assistant, proactive observations, mute/unmute,
latest camera controls and logo into the existing V2 branch `ae11404`.
Preserved session-bound places, return points, simulated memory and world-session
guards. Recall feeds only actual obstacle ranges to proactive speech; a stored
place cannot become a claimed visual detection. Stop clears memory and preserves
assistant listening. V2 retains version 2.0.0, build 14.

PASS: 58 core tests, 64 native unit/integration tests and 8 UI tests.
PASS: unsigned iPhone build. Independent model review preserved memory boundaries.
Commands: `swift test -j 2 --package-path ios/Shared/FeelCore`; `xcodegen generate
--spec ios/project.yml`; `xcodebuild` Lantern simulator test with
`-parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO`,
using iPhone17Pro simulator2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD; generic iOS build
with `CODE_SIGNING_ALLOWED=NO`. Completed October17 at02:02 EDT.
Evidence logs: `/tmp/feel-v2-core-sync.log`, `/tmp/feel-v2-sync-tests.log`,
`/tmp/feel-v2-sync-device.log`. New regression confirms saved places never become
live visual observations in voice snapshots.
No V2 installation, hardware flashing or cloud deployment performed.

## V2 follow-up from current main

Integrated main `76e0453`, including Where-is, local object lookup, typed Assistant
requests, updated controls and the existing photo gateway setup. Preserved V2's
session-bound places. Explicit memory recall cancels pending Where-is work so a
late photo or response cannot replace the selected place. World/session invalidation
clears both types of guidance. A stored place remains separate from live detections.

PASS: 85 portable core tests, 109 native tests, 15 Where-is Python tests and
the unsigned iPhone build. All nine UI tests passed, including the unchanged retry
of a camera-recovery test whose first app launch timed out. Retry evidence:
`/tmp/feel-v2-current-main-ui-retry.log`. Independent review was interrupted;
these results establish the tested checkpoint only. Commands: core and Xcode commands above; `python3 -m unittest discover
-s chalk/tests -p 'test_*.py'`.
Evidence: `/tmp/feel-v2-current-main-core.log`, `/tmp/feel-where-is-python.log`,
`/tmp/feel-v2-current-main-tests.log`, `/tmp/feel-v2-current-main-device.log`.

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

## Latest main snapshot f2fb703

The user requested all newly published main work. Local main now includes
`f2fb703`: direction cues, V-sign keyword capture, pointing, depth/video recording,
synthetic scenes, web replay, production CAD references and simplified settings.
Version branches retain their own memory/advanced features during propagation.

V2 preserves memory/Where-is cancellation while adding direction/pointing mutual
exclusion. Session loss resets those interactions; cached pointing output requires
live encoder state. Pointing speech respects global mute. Independent model review
found no new critical/high issues at these merge seams.

PASS: 204 core tests, 19 Where-is Python tests, three replay web tests.
The deterministic simulation ran twice: nine scenarios PASS and three retain
known upstream limitations (door lintel, slow detection, LiDAR outliers). All
baselines match. This is not a clean physical-navigation acceptance result.
Commands: `swift test -j 2 --package-path ios/Shared/FeelCore`,
`python3 -m unittest discover -s chalk/tests -p 'test_*.py'`, `npm test --prefix web`,
`python3 simulation/run.py --repeat 2 --no-web`.
Logs: `/tmp/feel-latest-v2-core.log`, `/tmp/feel-latest-chalk-python.log`,
`/tmp/feel-latest-web-tests.log`, `/tmp/feel-latest-simulation.log`.
PASS: all 15 pointing scenarios through the real macOS Vision detector
(`sh ios/scripts/pointing_harness.sh`, `/tmp/feel-latest-pointing.log`). These use
synthetic frames and do not prove physical puck tracking.
PASS: unsigned iPhone build (`/tmp/feel-latest-v2-device.log`). Independent
ARPerception review found no new critical/high issue in session, world-epoch,
route-reset or callback guards. Native tests: 117 passed, one skipped because the
simulator cannot run that Vision barcode path; the Mac harness covers all 15
synthetic scenarios. All 10 UI tests passed (`/tmp/feel-latest-v2-tests.log`),
completed October 17 at 13:35 EDT.
No phone installation or board deployment.

## V3 initial voice checkpoint

## V3 Advanced

Integrated validated V2 `2620acf` into existing V3 `e56e141`. Preserved saved-map
restoration gates, adaptive target feedback, barcode finding and explicit local
speech/typed commands. The local recognizer has its own name and cannot own audio
at the same time as Realtime. Explicit local capture pauses Realtime without a
spoken pause; resuming Realtime cancels local capture. Global mute covers readback.
Barcode payloads remain data, never commands. V3 retains version3.0.0, build14.
PASS: 90 core tests, 81 native unit/integration tests, four selected UI tests,
and the unsigned iPhone build. Three UI tests passed on the first run; the typed
command test passed after replacing overshooting test swipes with native element
targeting. Product assertions remain intact. Completed October 17 at 03:41 EDT.
Commands match V2, selecting LanternTests plus voice setup, largest-text Advanced
panel, typed-command fallback and Stop reachability UI tests. Evidence logs:
`/tmp/feel-v3-core-sync.log`, `/tmp/feel-v3-sync-tests.log`,
`/tmp/feel-v3-ui-native-tap.log`, `/tmp/feel-v3-sync-device.log`.
Voice token service: 18 tests passed (`npm test --prefix services/voice-token`),
using local mock HTTP servers. Independent review found no new critical/high
issues in audio ownership, global mute, saved-map gates or barcode isolation.
No V3 installation or hardware deployment performed.

## V3 latest-main propagation

Integrated V2 `79a8863`, including main `f2fb703`. Preserved saved-map restoration,
local command speech, adaptive feedback and barcode detection. Local speech and
V-sign keyword capture release one another's microphone ownership. Restoring maps
cancels pending interactions; barcode payloads remain display-only. Independent
review found no new critical/high issues in those merge paths.
PASS: 236 core tests, 135 native tests across the full run and targeted detector
retry, three selected UI tests, and unsigned iPhone build. The initial simulator
Vision backend returned no codes; the detector now uses the already verified CPU
revision in simulator builds, with unchanged defaults on physical devices. The
capability probe uses that same factory; all 15 assertions run and pass. No test
assertions were removed. The Mac harness also passed all 15 scenarios again.
Additional logs: `/tmp/feel-latest-v3-pointing-cpu.log`,
`/tmp/feel-latest-pointing-factory.log`. Completed October 17 at 13:43 EDT.
Logs: `/tmp/feel-latest-v3-core.log`, `/tmp/feel-latest-v3-tests.log`,
`/tmp/feel-latest-v3-device.log`. Version 3.0.0, build 14; no device installation.

## V4 Chalk

Integrated V3 `4bd93d9` into existing V4 `16fa832`. Preserved local English/Spanish
command parsing, optional Chalk interpretation, consent defaults, strict response
validation, offline fallback and feedback. A new realtime command cancels pending
Chalk work before execution, including mute and Stop. The panel explicitly
separates its text-only Chalk sharing from OpenAI Assistant microphone streaming.
V4 retains version 4.0.0, build 14. No V4 installation or cloud deployment performed.

PASS: 90 portable core tests, 28 Chalk service/evaluation tests, four report tests,
and the unsigned iPhone build. Boundary check confirms all 67 baseline hardware,
protocol and tactile files unchanged. All 104 native unit/integration tests passed,
including delayed Chalk cancellation after a realtime mute command. Three selected
UI tests passed: Chalk consent defaults/Stop, typed local commands and Assistant
setup. Completed October 17 at 07:20 EDT. The UI runner experienced long idle
waits; the recorded successful run is not a performance benchmark.
Commands: `python3 scripts/check_chalk_boundary.py`; `python3 -m unittest discover
-s services/chalk -p 'test_*.py'`; `python3 -m unittest discover -s scripts/tests
-p 'test_chalk_report.py'`; core and Xcode commands match V3.
Evidence logs: `/tmp/feel-v4-core-sync.log`, `/tmp/feel-v4-chalk-sync.log`,
`/tmp/feel-v4-report-sync.log`, `/tmp/feel-v4-sync-device.log`,
`/tmp/feel-v4-sync-tests.log`.

Independent review found no new critical/high issues in the V4 merge paths.

## V4 latest main integration

Integrated validated V3 `54b08ac`, including main `f2fb703`. Preserved the
text-command Chalk service and its independent consent. New Where-is, pointing
and direction interactions cancel delayed text commands. The new regression
confirms a delayed cloud recall cannot override a subsequent Where-is request.

PASS: 236 portable core tests, 159 native tests, 28 Chalk service tests, four
report tests and the unsigned iPhone build. The 67-file hardware boundary matches
validated V3 exactly. Only the upstream target-span encoder and replay command
files changed from the previous baseline; their hashes were compared to V3 before
refreshing the boundary. Independent merge review found no new critical/high issue.

Evidence: `/tmp/feel-latest-v4-core.log`, `/tmp/feel-latest-v4-tests.log`,
`/tmp/feel-latest-v4-device.log`, `/tmp/feel-latest-v4-chalk.log`. Commands match
the preceding V3/V4 sections. No device installation or hardware test performed.

PASS: all three selected UI cases across the completed runs. The first Chalk UI
attempt was interrupted after XCUI entered an automatic-scroll alert loop; the
next overshot the disclosure. Bounded bidirectional scrolling passed the unchanged
consent-default and reachable-Stop assertions. Direction arrows and typed commands
passed in the preceding run. Logs: `/tmp/feel-latest-v4-ui-retry.log` and
`/tmp/feel-latest-v4-chalk-ui.log`. Completed October 17 at 13:52 EDT.

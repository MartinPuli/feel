# October 17 V1 voice synchronization

Source main: `6ad7004`. V1 remains on main; version-specific code stays isolated.

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

## Remaining physical validation

These branch integrations validate software only. Headphone routing, real-device
perception, BLE/tactile end-to-end behavior and supervised user acceptance remain
pending. The phone retains V1. No V2/V3/V4 build replaced it.

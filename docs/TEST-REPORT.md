# V3 executed tests

V1 and V2 results are preserved in TEST-REPORT-V1.md, TEST-REPORT-V2.md and their
evidence directories. Both prerequisite hosted native gates passed before V3.

The V3 final local runner completed six available checks; it returned2 for the
Apple gate unavailable on Linux. See `evidence/v3/report.json` and actual logs.

| Command | Observed result |
|---|---|
| `sh ios/scripts/test_portable.sh` | 90 tests, 0 failures |
| `swift build -j 2 --package-path ios/Shared/FeelCore` | Build complete |
| `sh firmware/test/run_host_tests.sh` | 38 controller,17 CLI,6 board,6 upload-guard cases PASS |
| `python3 validation/production/run.py` | 1,518 assertions,558 states PASS |
| `python3 validation/spatial/run.py` | 358 assertions,43 states PASS |
| `python3 validation/advanced/run.py` | 1,441 assertions,156 states PASS |
| `bash scripts/check_ios.sh` | BLOCKED on this Linux host; hosted execution pending |

The32 new portable tests comprise12 adaptive,11 voice grammar and9 persistence
tests. They exercise unchanged bands/sequence numbers, quiet-first timing and
hysteresis, malformed/composite/partial commands, Unicode bounds, strict archive
validation, atomic restore, map/session identity, settling gaps and timeouts.

The advanced replay invokes the real compiled Swift parser/archive/guide/encoder,
then feeds actual packet bytes into the production C++ decoder/controller. Its
speech transcripts, AR bytes/poses/relocalization observations and motor model
are synthetic. The baseline and spatial replays also still pass. No transport,
real map alignment or physical motor feedback is fabricated.

Chromium155 checked the actual recorded viewer:28 pins, actual result/count,
Next, slider, playback/pause, desktop screenshot,390px mobile without horizontal
overflow and no JavaScript errors. Metadata: `evidence/v3/browser-check.json`.

## Found failures and fixes

The first version of the restore gate incorrectly counted a one-second gap
without observations as continuous normal tracking. Root reproduced this through
the production CLI (`expected awaitingRelocalization, got ready`). The fix resets
settling after gaps over250ms; direct and cross-layer regressions pass. Additional
review fixes are documented in REVIEW-V3.md.

A nested Linux wrapper initially exited zero without completed XCTest output;
that invocation is not counted as a test pass. A subsequent attempt exposed the
restricted `/proc` SwiftPM monitor SIGILL in the extra `--show-bin-path` process.
The Linux launcher now executes the built XCTest symlink directly after building,
and the V3 runner requires explicit test/build completion markers. The final
consolidated log contains all90 passing tests. Root also ran the compiled binary
directly with90/0. Earlier failure and regression metadata remain in evidence/v3.
The legacy-driver/private-libncurses workaround is local to this restricted host;
a normal Mac does not require these cloud filesystem paths.

## Native and physical gates

All29 Swift source files passed syntax parsing, which is not Apple typechecking.
The native suite contains22 app tests and3 UI tests awaiting hosted Xcode:
coordinator actions, voice attempt/lifecycle bounds, secure rejection of invalid
map data and atomic file storage, plus an actual Vision barcode request over a
CoreImage-generated QR pixel buffer. UI tests use labeled Simulation and explicit
typed commands, without microphone permissions. Counts describe tests present,
not a successful execution, until the hosted result is recorded.

No real speech recognition, saved-map relocalization, camera QR detection,
CoreML inference, LiDAR, BLE, UWB, servo motion, power, fit, force or human tactile
usability was verified. The synthetic map fixture is deliberately not ARWorldMap;
valid real-map capture/load and environment matching remain device tests.

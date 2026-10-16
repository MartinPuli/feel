# V3 executed tests

V1 and V2 results are preserved in TEST-REPORT-V1.md, TEST-REPORT-V2.md and their
evidence directories. Both prerequisite hosted native gates passed before V3.

The V3 final local runner completed six available checks; it returned 2 for the
Apple gate unavailable on Linux. See `evidence/v3/report.json` and actual logs.

| Command | Observed result |
|---|---|
| `sh ios/scripts/test_portable.sh` | 90 tests, 0 failures |
| `swift build -j 2 --package-path ios/Shared/FeelCore` | Build complete |
| `sh firmware/test/run_host_tests.sh` | 38 controller, 17 CLI, 6 board, 6 upload-guard cases PASS |
| `python3 validation/production/run.py` | 1,518 assertions, 558 states PASS |
| `python3 validation/spatial/run.py` | 358 assertions, 43 states PASS |
| `python3 validation/advanced/run.py` | 1,441 assertions, 156 states PASS |
| `bash scripts/check_ios.sh` | BLOCKED on this Linux host; hosted execution pending |

The 32 new portable tests comprise 12 adaptive, 11 voice grammar and 9 persistence
tests. They exercise unchanged bands/sequence numbers, quiet-first timing and
hysteresis, malformed/composite/partial commands, Unicode bounds, strict archive
validation, atomic restore, map/session identity, settling gaps and timeouts.

The advanced replay invokes the real compiled Swift parser/archive/guide/encoder,
then feeds actual packet bytes into the production C++ decoder/controller. Its
speech transcripts, AR bytes/poses/relocalization observations and motor model
are synthetic. The baseline and spatial replays also still pass. No transport,
real map alignment or physical motor feedback is fabricated.

Chromium 155 checked the actual recorded viewer: 28 pins, actual result/count,
Next, slider, playback/pause, desktop screenshot, 390px mobile without horizontal
overflow and no JavaScript errors. Metadata: `evidence/v3/browser-check.json`.

## Found failures and fixes

The first version of the restore gate incorrectly counted a one-second gap
without observations as continuous normal tracking. Root reproduced this through
the production CLI (`expected awaitingRelocalization, got ready`). The fix resets
settling after gaps over 250 ms; direct and cross-layer regressions pass. Additional
review fixes are documented in REVIEW-V3.md.

A nested Linux wrapper initially exited zero without completed XCTest output;
that invocation is not counted as a test pass. A subsequent attempt exposed the
restricted `/proc` SwiftPM monitor SIGILL in the extra `--show-bin-path` process.
The Linux launcher now executes the built XCTest symlink directly after building,
and the V3 runner requires explicit test/build completion markers. The final
consolidated log contains all 90 passing tests. Root also ran the compiled binary
directly with 90 tests and zero failures. Earlier failure and regression metadata remain in evidence/v3.
The legacy-driver/private-libncurses workaround is local to this restricted host;
a normal Mac does not require these cloud filesystem paths.

## Native and physical gates

All 29 Swift source files passed syntax parsing, which is not Apple typechecking.
The native suite contains 22 app tests and 3 UI tests awaiting hosted Xcode:
coordinator actions, voice attempt/lifecycle bounds, secure rejection of invalid
map data and atomic file storage, plus an actual Vision barcode request over a
CoreImage-generated QR pixel buffer. UI tests use labeled Simulation and explicit
typed commands, without microphone permissions. Counts describe tests present,
not a successful execution, until the hosted result is recorded.

No real speech recognition, saved-map relocalization, camera QR detection,
CoreML inference, LiDAR, BLE, UWB, servo motion, power, fit, force or human tactile
usability was verified. The synthetic map fixture is deliberately not ARWorldMap;
valid real-map capture/load and environment matching remain device tests.

## First native hosted result

Run38977441252 for source `af9f99a32be4532f6635280c497fdf6f0cd4d40c`
passed the portable, CAD and embedded jobs. The native job compiled Lantern and
executed 22 app tests with 1 failure and 3 UI tests with 2 failures. The generated QR
fixture produced no matching detection; memory and typed-command UI interactions
failed before their behavior assertions. Beacon simulator and unsigned-device
builds were not reached. This is a failed gate, not a successful native validation.

Xcode 16.4 used SDK 18.5 and the installed iOS 26.2 simulator. Exact failure lines and
job metadata are preserved in `evidence/v3/ios-ci-initial-failure.log` and
`github-actions-initial-failure.json`. Corrective work and a full rerun are pending.

The corrective commit removes the parent DisclosureGroup accessibility identifier
that overwrote its child control identifiers. Focused-field editing is verified
by typing through XCTest and asserting the exact field value; button/switch and
all memory/neutral/recovery assertions remain. The QR fixture now materializes
pixels on the CPU, verifies black/white modules and an opaque quiet zone, and
retains an image attachment plus raw Vision diagnostics on failure. The actual
production detector and payload/confidence/bounding-box expectations are unchanged.
The initial QR cause is not conclusively established; the full native rerun must
confirm whether the fixture correction resolves it.

## Second native hosted result

Run38978568683 for source `025be398e4c15777c9a5b4b9fe08b21f20faf9bb`
passed all three UI tests, confirming the memory flow and explicit typed commands.
All non-native jobs passed again. The 22 app tests still contain one failing QR
case: its black/white/opaque pixel assertions passed, but production detection
returned an empty list. This remains a failed native gate; later Beacon/device
builds were not reached. The retained fixture and raw observations are being
investigated. See `evidence/v3/github-actions-second-failure.json` and
`ios-ci-second-failure.log`.

An independent ZXing-C++ 2.3.0 decoder successfully read the exact retained
350 × 350 fixture as `FEEL test shelf`. Its SHA-256 and result are recorded in
`evidence/v3/qr-independent-decode.json`; the fixture is `qr-fixture.png`.
The failed request's raw Vision attachment contained no observations, before
the production confidence filter. The next corrective commit deliberately
selects CPU execution for simulator barcode requests using the pinned SDK's
public `usesCPUOnly` property. Device compute selection, algorithm revision,
symbologies, confidence threshold and expected payload remain unchanged. The
internal cause is unproven, and a third full native run is required.

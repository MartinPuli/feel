# Six-column release evidence — October 17, 2026

Base: current main54f5cd7, including room-memory, venue packs, Chalk and sign-in.
V2 base0e46eb6, V3 base42626ec, V4 base5f0ff56. Version features stay isolated.

## Change

Six active physical columns retain original slots1–6 → GPIO33,25,26,27,14,13.
GPIO32 is unused. App perception covers the full ±45° view in six15° sectors;
UI, target spans, arrows, pointing, voice direction descriptions and memory use
that mapping. Final Bluetooth writes force b0=0 and suppress highlight0. The
nine-byte raw codec remains compatible. Firmware independently skips slot0 in
all normal output paths. New esp32-six-live target; legacy seven-live also skips
slot0. Current angle/trim settings are unchanged and are not measured rotation.

V2/V3/V4 received the same hardware sources and minimal iOS mapping backports,
preserving their memory/advanced features. Firmware files were compared byte for
byte across all four trees. Standalone historical bench tools are not deployment
profiles and remain labeled separately. CAD retains the existing seven-position
shell with its leftmost position empty; no geometry or fit claim was added.

## Results

| Check | Status | Evidence |
|---|---|---|
| Main portable core/replay | PASS |264 tests; /tmp/feel-six-core.log; final direction/layout10 tests /tmp/feel-six-final-targeted.log |
| Main iOS unit tests | PASS |174 tests; /tmp/feel-six-ios-final.log |
| Main simulator interface | PASS |8 tests; /tmp/feel-six-ios.log |
| Firmware host suites / board guards | PASS | /tmp/feel-six-host-final.log; /tmp/feel-six-pin-map.log |
| Firmware esp32 / single-live / six-live builds | PASS | /tmp/feel-six-build-final.log |
| Main signed iPhone build19 | PASS | /tmp/feel-six-device.log |
| V2 portable core/replay | PASS |209 tests; /tmp/feel-six-v2-core.log |
| V3 / V4 portable core/replay | PASS |241 tests each; /tmp/feel-six-v3-core.log; /tmp/feel-six-v4-core.log |
| V2 / V3 / V4 simulator app builds | PASS | /tmp/feel-six-v2-build.log; v3-build.log; v4-build.log |
| Cross-layer replay, each of four versions | PASS |2634 assertions /558 states each; /tmp/feel-six-replay and /tmp/feel-six-v{2,3,4}-replay |
| Connected ESP32 upload | PASS | esp32-six-live; /tmp/feel-six-upload.log |
| ESP32 status readback | PASS | esp32-status.txt: six pins, ready=1, detached, connected=0 |
| Install latest app on real phone | BLOCKED | devicectl reports iPhone unavailable |
| Six-servo physical / real phone integration | NOT VERIFIED | No physical motion acceptance test performed |

Initial iOS run had three obsolete seven-column fixture failures (b0 and two
pointing positions). Fixtures now explicitly assert reserved-slot suppression
and reject pointing at the missing physical column; all174 rerun tests passed.
Initial device build needed the existing development-team argument; signed
rebuild succeeded. No checks were skipped to turn those failures green.

## Commands

```sh
swift test --package-path ios/Shared/FeelCore
sh firmware/test/run_host_tests.sh
python3 firmware/test/test_board_config.py
/tmp/feel-travel-pio/bin/platformio run -d firmware -e esp32 -e esp32-single-live -e esp32-six-live
python3 validation/production/run.py --output /tmp/feel-six-replay
# Each historical version used its compiled feel-replay with identical firmware core.
xcodegen generate # from ios/
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' -derivedDataPath /tmp/feel-autofloor-build -only-testing:LanternTests CODE_SIGNING_ALLOWED=NO test
# Interface suite also run with -only-testing:LanternUITests/LanternUITests.
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -destination 'generic/platform=iOS' -derivedDataPath /tmp/feel-autofloor-device -allowProvisioningUpdates DEVELOPMENT_TEAM=39D23XHM5Z CURRENT_PROJECT_VERSION=19 build
/tmp/feel-travel-pio/bin/platformio run -d firmware -e esp32-six-live -t upload --upload-port /dev/cu.usbserial-0001
xcrun devicectl list devices
```

Independent read-only firmware-agent review found no blocking issue in app
mapping/pointing/cues. Parent reviewed hardware loops, sentinel exclusion,
protocol compatibility and version firmware identity. The iOS agent found and
fixed an obsolete single-center exclusion in direction classification, with a
regression assertion. Code review is not physical validation.

## Next three human actions

1. Leave GPIO32 disconnected; verify six white signal wires against the wiring guide, with adequate external power distribution.
2. Connect/unlock/trust the iPhone so build19 can be installed; then connect FEEL Puck.
3. Observe each column across the view, then Stop/disconnect and loss-of-tracking behavior. Record real mechanical and power behavior.

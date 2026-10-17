# Assumed175° migration validation

October17,2026. User-selected assumption, not measured travel. Initially prepared on codex/servo-travel-test. Subsequently promoted to main
at the user's request, preserving the latest published Chalk updates. The normal
single-live profile advertises FEEL Puck and retains the zero-band gap fix.
No iPhone installation was required. Upload outcome is recorded separately.

| Check | Status | Evidence / command |
|---|---|---|
| Firmware regression | PASS | firmware-host.log; sh firmware/test/run_host_tests.sh |
| Classic default, output fixture, single live, single wide builds | PASS | firmware-build.log; platformio run -d firmware -e esp32 -e esp32-compilecheck -e esp32-single-live -e esp32-single-wide-test -j2 |
| Portable shared app tests | PASS184 | swift-tests.log; sh ios/scripts/test_portable.sh |
| Reference tests | PASS51 | reference-tests.log; python3 -m unittest discover -s validation/tests -v |
| Reference replay | PASS18scenarios/77steps | python3 validation/run_scenarios.py --output /tmp/feel-175-reference |
| Compiled Swift→C++ replay | PASS2634assertions/558states | python3 validation/production/run.py --output /tmp/feel-175-production |
| Fresh cam contact/STL export | BLOCKED | OpenSCAD unavailable; existing meshes stale |
| Wider motion on one real servo | USER-REPORTED PASS | User reports successful real-life test; no measured angle supplied |
| Exact175° shaft travel / seven-servo integration | NOT VERIFIED | Requires physical measurements |
| Full V1–V4 iPhone feature acceptance | NOT RUN this revision | Shared core/protocol coverage does not establish live camera, voice, cloud or BLE acceptance |

Independent read-only review and a second host regression completed. A stale
900–2100µs replay assertion was found and corrected before compiled replay passed.
Default PWM remains off. Old calibration and production measurement schemas are
rejected. No test records were installed as physical measurements.

Next human actions: measure the unloaded servo; fit/test a regenerated matching
four-band column; record and test seven servos and power before full deployment.
Separate production three-lobe shaft remains incompatible with four-band control.

## Main deployment

Normal `esp32-single-live` build and upload PASS (hash verified), advertised as
FEEL Puck; see main-live-upload.log. One servo onGPIO32, center sector3, with
zero-band gap return. Seven-servo output is not enabled by this deployment.

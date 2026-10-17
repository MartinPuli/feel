# V3 integration with current main

V3 incorporates V1 main `b780519` through updated V2, including collapsible
camera controls and floating panels. It retains session memory,
explicit on-device voice/typed commands, one saved AR map, adaptive target taps
and QR/barcode finding. Main remains V1; V2 and V3 stay on their own branches.

## Integration changes

- Preserve V1's camera-first screen, Geist fonts, camera startup guards and puck
  connection panel. My Places opens V2 memory controls. Settings contains V3's
  Voice, saved map and feedback panel. Every floating panel retains Stop outside its scroll; collapsed controls also
  keep Stop reachable.
- Preserve V3 cancellation, map identity/relocalization checks and restored-map
  teammate restrictions. Voice commands never execute camera or barcode text.
- Adapt advanced control rows for large text and use the shared contrasting primary
  button style; update UI tests to use the actual
  sheets and verify text entry, memory guidance and Stop behavior.
- Inherit nominal 120-degree firmware/CAD and guarded seven-servo setup unchanged.
  Advanced replay now checks actual 120-degree selection / 107-degree tap, keeping
  its cadence assertions unchanged.
- Keep all three production replay checks and latest firmware checks in CI. Add
  Beacon UI tests to the shared native runner (inherited from updated V2).

## Current evidence

[Machine-readable report](evidence/v3-main/report.json) and adjacent logs record:

| Check | Result |
| --- | --- |
| Portable production Swift core | 90 tests, zero failures |
| Replay CLI build | PASS |
| Firmware host, adapter, configuration and production-record checks | PASS |
| Tooling / reference / CAD regression suites | 7 / 51 / 15 tests PASS |
| Actual CAD cam geometry | 80 checks PASS |
| V1 production replay | 2,634 assertions, 558 states PASS |
| V2 spatial replay | 444 assertions, 43 states PASS |
| V3 advanced replay | 1,753 assertions, 156 states PASS |
| Native iOS tests and unsigned device builds | First camera integration PASS; latest drawer integration in progress |

Firmware and CAD files are byte-identical to integrated main. Existing firmware
build and mesh-export evidence is inherited; it is not described as a new build.
Current firmware host regressions and actual-CAD geometry checks were rerun.
Hosted Actions remain separately subject to the documented account billing limit;
no hosted pass is claimed for this integration.

The first sandbox-only portable/CAD attempts could not access compiler caches or
CPU capabilities. They were rerun with the installed tools outside that sandbox;
the retained successful logs are the actual completed checks. Disk capacity also
required deleting completed, regenerable build caches while retaining evidence.

## Native regression repairs

The first native run found two failures, retained in the evidence directory:

1. Vision revision 2 failed to create its inference context on iOS 26.5 simulator.
   A diagnostic matrix decoded the same generated QR through the actual pixel
   buffer with CPU execution at confidence 1.0. Only the simulator request now
   selects CPU execution. The original detector assertion then passed; physical
   device defaults, image orientation and confidence/bounds checks are unchanged.
2. The typed-command test checked navigation buttons after their sheet covered
   them, then tried focusing an offscreen command field under the persistent Stop
   bar. It now follows the resulting screen and makes bounded, short scrolls until
   the actual field is visible above Stop. It types the command and verifies both
   the confirmation and the stored place. Its focused run passed.

Screenshot inspection also found a white-on-white Run command label inherited
from the old generic button style. It now uses the current shared primary style.
No microphone or speech result is mocked into a physical acceptance claim.

## Physical scope

No board was flashed and no phone app was installed. Real speech recognition,
AR-map restoration, QR camera performance, LiDAR/BLE/tactile behavior and seven
servos remain physical checks. See [VERSIONS.md](VERSIONS.md) for the user flow and
[SEVEN-SERVO-PRODUCTION.md](SEVEN-SERVO-PRODUCTION.md) for deployment requirements.

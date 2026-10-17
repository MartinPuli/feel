# Known issues and verification limits — V3

| Priority | Issue | Current handling / next action |
|---|---|---|
|Hardware gate|120° FS0307 redesign has not been physically validated|CAD/firmware now target 120°; narrower lobes increase unverified side force/print sensitivity. Default seven-servo PWM remains disabled; the opt-in single-servo demo uses a limited midpoint range. Measure travel, supply compatibility and manual/powered column behavior before enabling.|
|Hardware gate|Servo/horn/foam/guide dimensions unmeasured|Print coupon and crank rig first; CAD fit defaults do not establish physical fit.|
|Device verification|Perception accuracy, NI and complete tactile assembly unverified|Hosted foundation simulator tests passed. Local signed install, BLE receipt and user-reported small single-servo live motion followed; these do not verify seven actuators, full travel or sensing accuracy.|
|Perception limitation|Door finder is a rectangle candidate heuristic|UI labels it as a candidate; no door-class weights or accuracy claims.|
|Perception limitation|LiDAR missing/noisy/outdoor/thin-object depth|Unknown stays unknown; indoors only for demo, real sensing tests pending.|
|Protocol limitation|No timestamp/checksum/health in nine-byte packet|Reject malformed/old-sequence packets,500 ms watchdog; legal-value corruption/delayed valid packets remain undetectable.|
|Mechanics limitation|Servo transitions cross intermediate cam lobes|Do not claim static exclusive-band logic proves no transient pin motion. Observe every P1/P5 transition.|
|Hardware limitation|No position,force,current or jam sensors|Neutral/disabled output cannot prove physical return. Synthetic stall replay illustrates this limit.|
|Optional function|Nearby Interaction device support/sign/rate unknown|Both apps require real-device validation and explicit peer selection. No automatic named-person identification.|
|Environment|Swift driver child monitoring can crash under restricted /proc|Use official legacy-driver switch and directly run the compiled Linux XCTest executable; record command and exit status.|
|Device verification|V3 speech, saved-map relocalization and real-camera barcode behavior unmeasured|Native tests use lifecycle helpers, generated QR pixels and synthetic map rejection; test actual permissions, speech, rooms and camera latency on the phone.|
|Simulator compatibility|Vision barcode revisions 3/4 return no observations for the valid QR fixture on hosted iOS 26.2; revisions 1/2 decode it|Use supported revision 2 in simulator builds with normal compute selection. Device defaults remain unchanged and real camera behavior is unverified. Exact matrix: `evidence/v3/ios-ci-fourth-failure.log`.|
|Feature limit|NI camera assistance is incompatible with an initial world map|Teammate finding is disabled throughout a restored-map session; start fresh Live to use it.|
|Feature limit|One saved world map; no transform between rooms or route planning|Load in the same area, wait for verified relocalization, recalibrate and explicitly Recall. A target bearing does not establish a safe route.|
|Interaction limit|Voice accepts one explicit English/Spanish command|No arbitrary conversation or cloud recognition fallback; typed controls remain available.|
|Device verification|Adaptive cadence comfort and actuator response unmeasured|Only highlight timing changes; actual bands are preserved. Test on calibrated hardware before relying on touch.|

No known critical controller/protocol logic defect remains after current reviews;
final build and integration results belong in RELEASE-STATUS.md. This statement
does not certify Apple adapters or mechanics without their respective checks.

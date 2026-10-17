# Known issues and verification limits — V1

| Priority | Issue | Current handling / next action |
|---|---|---|
|Hardware gate|120° FS0307 redesign has not been physically validated|CAD/firmware now target 120°; narrower lobes increase unverified side force/print sensitivity. PWM remains disabled. Measure travel, supply compatibility and manual/powered column behavior before enabling.|
|Hardware gate|Servo/horn/foam/guide dimensions unmeasured|Print coupon and crank rig first; CAD fit defaults do not establish physical fit.|
|Platform verification|Simulator UI and CoreML inference accuracy not validated|Mac signed device build/install and actual iPhone→ESP32 BLE reception passed in the local setup session; camera response was user-reported. Automated UI, perception accuracy and full physical validation remain pending.|
|Perception limitation|Door finder is a rectangle candidate heuristic|UI labels it as a candidate; no door-class weights or accuracy claims.|
|Perception limitation|LiDAR missing/noisy/outdoor/thin-object depth|Unknown stays unknown; indoors only for demo, real sensing tests pending.|
|Protocol limitation|No timestamp/checksum/health in nine-byte packet|Reject malformed/old-sequence packets,500 ms watchdog; legal-value corruption/delayed valid packets remain undetectable.|
|Mechanics limitation|Servo transitions cross intermediate cam lobes|Do not claim static exclusive-band logic proves no transient pin motion. Observe every P1/P5 transition.|
|Hardware limitation|No position,force,current or jam sensors|Neutral/disabled output cannot prove physical return. Synthetic stall replay illustrates this limit.|
|Optional function|Nearby Interaction device support/sign/rate unknown|Both apps require real-device validation and explicit peer selection. No automatic named-person identification.|
|Environment|Swift driver child monitoring can crash under restricted /proc|Use official legacy-driver switch and directly run the compiled Linux XCTest executable; record command and exit status.|

No known critical controller/protocol logic defect remains after current reviews;
final build and integration results belong in RELEASE-STATUS.md. This statement
does not certify Apple adapters or mechanics without their respective checks.

## October 18 UTC — current production readiness

**Not ready for unrestricted production.** Latest source, cloud checks and remaining device/configuration gates are recorded in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md). That report supersedes the historical counts and branch/deployment statements below.

The unsafe 150 ms restoration of old pin bands after a neutral packet has been removed. Only a fresh valid command can raise them again. Angles and wiring are unchanged; this firmware has not been flashed. Shared context reads now have a verified-user server boundary, but remain disabled until FEEL's database identity is configured.

## October 17 integration limits

- Chalk MCP context results disagree with the direct engine for the same synthetic IDs. Direct queries pass; MCP parity is unresolved. See the [reproduction](evidence/chalk-context/INTEGRATION-VALIDATION.md).
- Live intent evaluation is partial and misses the 1 s target. Three measured replies clarify instead of rejecting; no invalid destination was observed. The optional service is not promoted as production-ready.
- Shared-room downloads and private last-seen queries still need an authenticated phone-facing endpoint. The new upload path is opt-in and software-tested; a real phone round trip remains unverified.
- Six-column replay retains four known synthetic limitations: narrow openings, lintels, slow detector highlights and outlier flicker. Historical seven-sector baselines were preserved.
- Real phone/headphone voice, LiDAR, restored-room tracking, UWB, BLE and tactile behavior remain separate physical gates. The iPhone was unavailable in this run.

# Known issues and verification limits — V1

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

No known critical controller/protocol logic defect remains after current reviews;
final build and integration results belong in RELEASE-STATUS.md. This statement
does not certify Apple adapters or mechanics without their respective checks.

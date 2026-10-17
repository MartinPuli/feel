# Automatic floor calibration validation

October17,2026. Implemented automatic stable classified-floor calibration,
manual fallback and matching UI/voice guidance. No firmware or wiring changes.

| Check | Status | Evidence |
|---|---|---|
| Full portable FeelCore suite | PASS195,0failures | /tmp/feel-autofloor-core.log |
| iOS simulator LanternTests | PASS134,0failures | /tmp/feel-autofloor-xcode.log |
| Signed physical iPhone build18 | PASS | /tmp/feel-autofloor-device.log |
| Independent calibration review | PASS after lifecycle fix | /tmp/feel-auto-floor-review.log |
| Installation and real-floor detection | BLOCKED | iPhone unavailable in devicectl; no physical detection claim |

Commands:

```
sh ios/scripts/test_portable.sh
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' -derivedDataPath /tmp/feel-autofloor-build -only-testing:LanternTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -destination 'generic/platform=iOS' -derivedDataPath /tmp/feel-autofloor-device DEVELOPMENT_TEAM=39D23XHM5Z CURRENT_PROJECT_VERSION=18 build
xcrun devicectl list devices
```

The first device build exhausted disk space. Only task-generated rebuildable
review/oldbuild outputs were removed; the subsequent signed build succeeded.
No user documents or app data were deleted.

The11new portable calibration tests cover floor-vs-other classification,
freshness/future timestamps, nonfinite/insufficient geometry, plausible lens
height, mounting/tracking, stability, sample continuity/count, anchor switching,
reset/latching and duplicates. Review identified and fixed a stop/interruption
restart race. Stable observations are current frames containing a retained
classified anchor, not independently repeated classifications.

Phone artifacts: /tmp/feel-autofloor-device/Build/Products/Debug-iphoneos/Lantern.app.
No camera or microphone recording was started. No physical servo sweep was run.

Next actions: reconnect/unlock phone; install signed app; observe automaticfloor
acceptance and neutral fallback in a real scene, then compare actual pins with
commanded status under supervision.

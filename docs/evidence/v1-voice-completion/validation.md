# Voice control and delivery validation

October 17, 2026. Base main `2a7b699`; V1 version 1.0.0 build 16.

## Verified behavior

- Strict voice tools control arrows, independent direction stop, synthetic cues,
  local recording and video preference. Every recording start requires an
  explicit Boolean video choice; the legacy implicit start command is rejected.
- Finder, tracking and photo-configuration changes invalidate older Where-is
  photos and answers. They cannot restore the previous target.
- Announcement delivery requires successful response completion and audio drain.
  Cancellation, mute, expiry, replacement and disconnect discard the callback.
  The policy keeps an undelivered observation eligible for retry.
- Loss/recovery announcements cancel when their supporting state changes.
  Repeated held-target reminders respect the automatic-update preference.
- Muted target questions do not queue inaudible speech or auto-select a choice.

PASS: full native suite, 132 tests, zero failures, before the final explicit
recording-argument refinement. Log `/tmp/feel-voice-completion-final-tests.log`.
Independent review covered model integration and delivery request ownership.
It found an implicit recording-video choice; the final tool contract removes it.
The follow-up review found no remaining critical/high issue in that scope.

Commands:

```sh
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -configuration Debug \
  -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' \
  -derivedDataPath /tmp/feel-drawer-sim -parallel-testing-enabled NO \
  -collect-test-diagnostics never -only-testing:LanternTests \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/feel-voice-completion-install \
  DEVELOPMENT_TEAM=39D23XHM5Z -allowProvisioningUpdates build
```

The final targeted run selects `LanternTests/VoiceNewCommandTests` and
`LanternTests/VoiceNewControlsTests` with the same simulator options.

## Device acceptance still required

Build 15 installed successfully at 14:04 EDT. iOS refused automatic launch because
the paired phone was locked. Installation alone does not prove microphone capture,
voice quality, headphones, reconnection or tactile behavior. The user was asked to
unlock FEEL and test mute, a command while muted, and unmute. Build 16 supersedes
15 with the recording-choice correction; its installation result is recorded below.

Proactive scene speech still has a three-second freshness deadline including
network latency and playback. Physical testing must verify useful lines finish
within that interval. No physical navigation or tactile acceptance is claimed.

PASS: final recording-choice suites, 10 tests, zero failures. Log
`/tmp/feel-voice-recording-choice-tests.log`. Signed build 16 PASS, log
`/tmp/feel-voice-completion-build16.log`. Build 16 installed on the paired iPhone
at 14:06 EDT and launched successfully at 14:07 EDT. Listening acceptance remains
pending the user's response; successful launch does not establish audio quality.

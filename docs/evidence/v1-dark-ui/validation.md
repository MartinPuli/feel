# Dark camera interface

October 17, 2026. V1 build 17. User requested removing the bright white UI.

Camera controls and floating panels use dark neutral surfaces, fine borders and
rounded corners. Removed hard offset shadows. Primary actions retain readable
labels; orange remains for tactile/connection state. Lantern uses dark appearance
even when the phone uses light mode. Voice, sensing and command logic are unchanged.

PASS: three existing UI tests for drawer/modals, largest text with reachable Stop,
and Assistant setup. Reviewed drawer and Settings screenshots. Text/surface
contrast is 16.58:1, secondary text 8.99:1, control borders at least 3.38:1 across
normal dark surfaces, calculated from the declared neutral color values.
Independent review found no blocking accessibility regression; added visible
pressed opacity after its minor feedback finding. Signed final build PASS.
Installed build 17 on the paired iPhone at 14:11 EDT.

Commands: `xcodegen generate --spec ios/project.yml`; Lantern `xcodebuild test`
with the existing iPhone 17 Pro simulator, selecting
`testDrawerAndFloatingPanels`, `testLargestTextKeepsStopReachable`, and
`testVoiceSetupKeepsCameraAndMicrophoneUnderUserControl`. Signed generic iOS build
used the existing team and `/tmp/feel-voice-completion-install` derived data.
Logs: `/tmp/feel-dark-ui-tests.log`, `/tmp/feel-dark-ui-final-device.log`.
No new physical sensing or headset validation is claimed.

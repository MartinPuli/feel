# V1 app design review

Current visual direction: [Vercel-inspired native refinement](V1-VERCEL-DESIGN.md).
The blue-accent description below records the earlier iteration.

October 16, 2026. Base: `feel/v1-foundation` at `cb4bf24`.
Original work branch: `codex/v1-app-design`. The user subsequently designated
`main` as V1 and requested this redesign be integrated there together with the
latest foundation. No Actions run was requested for the consolidation.

## Design read and audit

Accessible native iPhone assistance apps, preserving FEEL's name, blue accent,
physical orientation requirements and consent language. Taste informs hierarchy,
spacing and brand consistency; its landing-page imagery and web animation rules
do not apply to these native product interfaces. Foundation: SwiftUI, SF Symbols,
Dynamic Type and semantic system colors. Variance 4, motion 2, density 4.

Before: Lantern used one long column in a landscape-only app. Session buttons
scrolled away, guidance displayed raw state names, a simulated target relied on
color alone, and connection state was hidden. Beacon gave start/stop equal
priority and allowed Start to reset an active session.

## Implemented

- Shared blue action colors, semantic surfaces, 16pt panels and 12pt controls.
  Both appearances follow the system. No automatic decorative motion.
- Lantern uses two content columns at available widths of 720pt or greater.
  Smaller widths and accessibility text sizes use one column. The tactile view
  has priority, with setup and recovery messages alongside it.
- Stop remains outside scrolling content. At accessibility text sizes only Stop
  stays fixed; starting controls move into the scroll view to preserve reading space.
- Guidance distinguishes fresh depth, calibration, stale depth, invalid frames,
  stopped state and real/simulated tracking loss. Simulation remains labeled.
- Ringed target pins distinguish target bearing without relying only on color.
  VoiceOver retains the seven-column value and target-column description.
- Connection status is visible. Disconnect can cancel a pending connection.
- Beacon prioritizes explicit invitation consent and focuses the request for
  VoiceOver. Sharing controls reflect the real service running state; stopped
  controls have a distinct disabled appearance. Failures include retry guidance.
- Beacon distance-only status no longer asks its user to wait for AR direction.

Protocol, encoding, sensing thresholds, BLE transport, orientation constraints,
background stop behavior and consent decision logic are unchanged.

## Validation

See `evidence/v1-design/validation.txt` for command summaries and observed results.
Local environment: Xcode 26.6, iPhone 17 Pro simulator with iOS 26.5.

Initial Beacon test assumed the runtime reported UWB unavailable. This runtime
reports the capability as available, so that assumption failed. The corrected
test checks recoverable unsupported state OR start/stop behavior according to the
actual reported capability. Neither path proves ranging works.

An initial app-scoped screenshot cropped the landscape app incorrectly. Final
UI test evidence uses full-screen captures. Appearance is set on the simulator;
launching with an AppleInterfaceStyle preference did not reliably select dark mode.

Manual device validation remains necessary for live calibration, real BLE and
UWB connections, invitation acceptance/decline, VoiceOver interaction and low-vision
usability. Simulator tests do not establish physical safety or actuation.
The V1 design work does not alter the release status of V2 or V3.

## Next device checks

1. Open both app targets locally and review the screens with the team.
2. Test live calibration and pairing on the actual mounted iPhone and Beacon phone.
3. Verify VoiceOver, largest text and Stop with the real puck before any supervised demo.

References: [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[SwiftUI adaptive layout](https://developer.apple.com/documentation/swiftui/viewthatfits).

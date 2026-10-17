# V1 Vercel-inspired native refinement

Current Lantern interface: [camera-first build 4](V1-CAMERA-UI.md).
The descriptions below document the earlier dashboard revisions.

October 16, 2026. Based on canonical V1 `main` at `d18d13e`.
User direction: make FEEL feel closer to Vercel and install it on the iPhone.

## Design

Lantern and Beacon use official Geist Sans for interface text and Geist Mono for
puck labels and packet diagnostics. Fonts are bundled, registered for both apps,
and scale with Dynamic Type. Their pinned source, hashes and SIL OFL license are
in `ios/Shared/Fonts/`. No runtime font download is required.

The palette is monochrome, with inverse primary actions, one-pixel borders,
8pt control corners and 10pt data panels. Settings are flat sections separated
by rules; the tactile display keeps its own frame. Beacon's large icon tile is
replaced with a small symbol. The app follows light and dark system appearance.

The existing session hierarchy, fixed Stop, simulation disclaimer, target-ring
encoding, consent, accessibility labels and physical phone orientation remain.
This is a SwiftUI interpretation of Geist, without web component dependencies.
Taste direction: variance 4, motion 2, density 4. No decorative motion.

The production detector is included in local builds using the repository's
verified model checksum. App version remains 1.0.0; the initial Geist build was 2.
The simpler revision below is build 3.

## Validation

See `evidence/v1-vercel/validation.txt` for completed checks and device status.
An independent source review found no functional/accessibility regressions.
Calculated secondary-text contrast is approximately 6.49:1 in light appearance
and 8.15:1 in dark appearance; primary-action contrast exceeds 16:1.

Simulator UI checks do not establish LiDAR, BLE, UWB or physical tactile
performance. Hardware and firmware behavior are outside this visual change.

References: [Geist](https://vercel.com/geist/introduction),
[colors](https://vercel.com/geist/colors),
[typography](https://vercel.com/geist/typography),
[official fonts](https://github.com/vercel/geist-font).

## Simpler revision — build 3

The user requested fewer details. Removed the duplicate Lantern onboarding
section, decorative mode badge, panel legend and Beacon intro icon. Technical
explanations and the pin legend are under Details; Beacon connection/privacy
instructions expand on demand. Consent decisions remain explicit.

The tactile view, session controls, simulation notice, calibration, actionable
session errors and Bluetooth status stay visible. The simulation test checks
both simulation labeling and the no-hardware-movement message. Independent
review caught hidden error feedback; it was restored before final validation.

See `evidence/v1-simple/validation.txt` and screenshots for this revision.

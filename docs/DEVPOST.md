# Devpost draft — FEEL

**Tagline:** Turn nearby space into touch.

## Inspiration

Audio is valuable for understanding surroundings, but a continuous spoken stream
can compete with conversation and environmental sound. We are exploring whether
a small spatial tactile display can present nearby obstacles and selected targets
through the same interface.

## What it does

FEEL combines a LiDAR iPhone, a Bluetooth-connected ESP32, seven servos and a
7×4-pin palm display. Each column represents a direction, and one of four rows
represents distance. A tapping pin highlights a selected target. The prototype is
intended for supervised indoor exploration, with explicit tracking and connection
status on the phone.

## How we built it

We recreated the implementation from a technical handoff: a native Swift app,
ARKit depth processing, Vision/CoreML target integration, nine-byte BLE protocol,
portable C++ firmware controller, and parametric OpenSCAD parts. The simulator
runs the same Swift encoder and C++ controller as the device software, with
synthetic input and clearly labeled motor estimates. Automated tests cover malformed
packets, lost/stale input, sequence rollover, watchdog behavior and geometry.

## Challenges

Mechanical return and servo travel are not interchangeable with software commands.
The FS0307 documentation differs from the handoff's travel assumption, so physical
output is disabled until the exact servo is characterized. The door candidate is
a heuristic. LiDAR, Bluetooth, Nearby Interaction and human tactile interpretation
must be checked on actual devices.

## Validation — update with final results before submission

Link the release report and exact commit. Paste only executed test counts. List
what ran on Linux/macOS separately from what ran on hardware. If the device is not
ready, demonstrate the production replay under a visible SIMULATION label and say
which physical steps are pending. Do not use handoff test counts as this project's
results or claim navigation/collision benefits without measured evidence.

## What is new / attribution

The intended mechanical concept and HANDOFF-v7 existed before this recreation.
The implementation in this branch was written from scratch during this session;
no original CAD/firmware/app source was available. Prior preparation tooling is
preserved in git history. CoreML weights are a separately attributed Apple-hosted
YOLOv 3 model fetched by pinned revision and hash, not trained by our team.

## Next steps

Measure parts, pass manual P1–P5, calibrate one powered column, and verify real
phone-to-pin behavior. Later branches explore session-local spatial bookmarks and
advanced interaction without replacing the preserved foundation.

## Submission fields still requiring team input

Team names (max 4), repository visibility/link, build video/photos, actual hardware
results, current branch/commit, and organizer decision on pre-existing design/work.
Primary intended track: Hardware for Good. No sponsor integration is claimed.

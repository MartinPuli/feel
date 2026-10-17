# FEEL versions and branch guide

`main` remains V1. V2 and V3 are separate, progressively extended versions; neither
advanced branch is merged into V1. All three use the same nine-byte BLE protocol,
seven-column design and nominal FS0307 120-degree mapping.

| Version and branch | What it does | How to try it | Main limitation |
| --- | --- | --- | --- |
| V1 — `main` | Estimates obstacles from iPhone depth; provides object/door/exit/person finding and optional teammate ranging; sends seven column bands to the ESP32. | Allow camera access on launch (or choose Start camera), connect the puck, open Settings to enter camera height and calibrate, then move a large object through the camera sectors. | LiDAR, BLE, mounting and tactile behavior need physical validation. |
| V2 — `feel/v2-spatial-memory` | Adds named places within the current AR session: Remember, Recall, a separately set return point, and Return. | Open My Places from the camera header; within one continuous live session, remember a place, move, select it and Recall. Memory simulation offers a software-only example. | Places are cleared when the session stops or is restarted/interrupted. Direction to a place is not route planning. |
| V3 — `feel/v3-advanced` | Adds explicit typed/on-device voice commands, one saved local AR map, configurable target-tap cadence, and QR/barcode finding. | Use Voice, saved map and feedback; type `list places` or `remember Desk`. Save/Load requires a real mapped area and successful relocalization. | Speech support depends on the phone/language. Map restoration, camera code detection and tactile cadence need physical checks. |

## What V3 adds in detail

- Commands are a bounded grammar, not an open-ended conversational assistant.
  English is the default; Spanish command input is selectable. Listening starts
  explicitly, accepts final results only, and has no cloud fallback or wake word.
- Save map replaces one protected local map and its places. Load does not activate
  guidance until identity and tracking checks pass; select Recall afterward.
  Teammate ranging is unavailable for the entire restored-map session.
- Standard, Reduced and Automatic profiles change target highlighting cadence;
  obstacle bands stay unchanged. They do not measure or control contact force.
- QR/barcode payloads are display-only labels. They cannot execute commands or open
  links, and target direction still requires valid depth and tracking.

## Hardware status is separate from software status

The repository prepares seven outputs, but the recorded connected setup contains
one servo. The single-live firmware maps the camera's center sector to GPIO32.
Preparing V2/V3 branches does not upload firmware or install an iPhone app.

The seven-servo production build requires individual measurement records; a
nominal 120-degree design is not a measured travel or safe-load certification.
Passing software tests does not establish physical movement, complete seven-servo
operation, speech recognition quality or real-world map restoration.

Each branch's release report records its actual checks. Historical CI reports apply
only to their recorded commits. Current hosted Actions may be unavailable because
of the repository account's billing/spending limit; local results are identified
separately.

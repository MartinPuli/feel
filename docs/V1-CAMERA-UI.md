# V1 camera-first interface

User direction: make the app primarily a camera, connect to the puck, and show
illuminated dots for what it detects. This supersedes the two-column dashboard.
Version 1.0.0, build 4. Canonical V1 branch: `main`.

## Main screen

- The existing AR camera fills the screen. The app attempts to open it once on
  first appearance, using the normal iOS permission prompt. Stop or backgrounding
  ends the session; returning from a sheet or the background never restarts it.
- Connect puck opens discovery immediately. The user chooses a device. Closing
  the panel stops scanning without dropping an established connection.
- A compact 7×4 diagram displays the actual encoded packet. Filled dots represent
  depth bands, with a ring for the target column. It is a puck diagram, not a
  camera-image detection map or bounding boxes. Neutral is not proof of clearance.
- Stop is persistent during sensing or pending permission, including inside both
  modal panels. Start camera replaces it only when stopped.
- Calibration is still required. A visible Calibrate action opens measured height
  and mounting instructions. Calibration errors stay visible beside that action
  in Settings, as well as on the main screen.
- Target selection, simulation and technical explanations live in Settings.
  Simulation explicitly turns off the camera view and labels synthetic input;
  simulated movement is never sent to hardware.

The camera surface always uses a dark appearance for contrast over video.
Largest accessibility text gets scrollable readings with a fixed session action.
The stopped state hides the camera view, so a paused image cannot appear live.
Beacon remains the sharing app; its interface is unchanged in this revision.

## Implementation and verification

ARPerception remains the sole session/configuration/delegate owner. CameraPreview
presents that same ARSession, and the old secondary camera preview was removed.
An integration test checks that assigning this session to ARSCNView retains both
session and delegate identity. Startup ignores duplicate requests while pending.
Existing generation cancellation rejects permission callbacks after Stop.

The new UI suite covers the camera-first controls, simulation labeling, neutral
Stop, modal dismissal without restart, background/foreground without restart,
Stop inside both panels, largest text, and denied camera/unsupported LiDAR feedback.
See `evidence/v1-camera/validation.txt` and screen captures.

Simulator screenshots intentionally show a black camera-off background. They do
not establish actual LiDAR, camera rendering/orientation, calibration, BLE/UWB,
or tactile performance. Those checks require the connected mounted iPhone.

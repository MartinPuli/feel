# V2 updated from current V1 main

This branch integrates V1 `main` commit `a4c141e` into V2 Spatial Memory. The
previous V2 tip was `063c07c`. `main` remains V1; V2 is published on
`feel/v2-spatial-memory`, with V3 advanced work separate.

## What changed

- The iOS app retains current V1's camera-first screen, Geist fonts, compact tactile
  display, connection/settings sheets, larger-text layout and Stop controls.
  Normal launch requests camera access once; Stop or backgrounding does not restart it.
- My Places opens from the camera header in its own sheet with a visible Stop. Remember, select, rename, delete, Recall,
  Set return point, Return and Stop guidance retain their existing behavior.
  Memory simulation retains its movement, tracking-loss and session-reset controls.
- Places remain session-only. Stops, interruptions, resets and mode changes clear
  memory; transient tracking loss neutralizes output and preserves the same-session
  intent. No voice commands, saved world maps or other V3 features were added.
- Firmware and CAD come from current V1: nominal 120° geometry, 0/40/80/120° bands,
  13° tapping offset, 900–2100 µs nominal mapping, single-servo demo/live profiles,
  and seven-servo production preparation. Default outputs remain disabled;
  production still requires actual measurement records for all seven units.
- App marketing version is 2.0.0, build 4. Setup instructions select V2 and identify
  `main` as V1. CI retains V1 gates and the spatial replay.

## Validation

Validation is being completed in the isolated V2 integration worktree. Results
will be finalized before the integration commit. The initial native build attempt
exhausted host disk space while compiling Apple SDK modules; this was an environment
failure, not a failing behavioral assertion.

Portable firmware tests and both replays passed: 2,634 foundation assertions over
558 controller states; 444 spatial assertions over 43 controller states. Source
presence, seven tooling tests and 51 independent reference tests also passed.

## Physical limits

No device was flashed, installed or moved during this integration. Simulator tests
and unsigned builds cannot validate LiDAR accuracy, AR drift, real BLE timing,
Nearby Interaction direction, physical memory guidance or seven-servo mechanics.
Prior one-servo user observations are historical V1 evidence, not new V2 acceptance.

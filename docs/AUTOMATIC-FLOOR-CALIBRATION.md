# Automatic floor calibration

Starting Live enables horizontal-plane detection. On a device supporting ARKit
plane classification, FEEL accepts only a plane classified as floor. Unknown
planes and tables are not substituted for the floor. Camera intrinsics continue
to come from ARKit; this feature establishes floor height, not lens calibration.

## Acceptance

Normal tracking, valid mounting orientation and available depth are required.
Frames must be from the current running session, no more than250ms old, with
no future timestamp. One classified floor anchor must remain stable for at least
10distinct frame timestamps spanning1.5seconds. Gaps above250ms, anchor switches,
invalid tracking/mount/depth or more than3cm height variation reset pending evidence.
The plane must be at least0.5m wide and long, at least0.5m², and0.6–2.1m below
the camera. These are conservative engineering thresholds, not measured accuracy.

The observations are repeated fresh frames containing a persistent classified
anchor, not ten independent classifications or proof that the floor remains in
view. ARKit's classification can be wrong; real-world acceptance is still needed.

Once accepted, floor height stays fixed for the session. A manual measured-height
override remains available and is never overwritten automatically. Start/reset
and interruptions clear calibration. Stop cannot be undone by a delayed
interruption callback; inactive sessions reject queued frame calibration.
No floor means neutral guidance, never an assumed clear path or guessed height.

## Use on the phone

1. Start camera with the phone landscape-left, rear camera forward, and some
   floor visible. Move slowly; the app displays “Finding floor…”.
2. Wait for “Floor calibrated automatically”. The minimum stability window is
   1.5seconds after an eligible plane appears; total detection time can be longer.
3. If automatic detection is unavailable or cannot find a floor, enter the
   measured lens height in Floor setup and choose “Use measured height”.

This is on-device and requires no cloud connection. The seven-servo firmware
and packet format are unchanged by this app update.

## What can be tested remotely

Software tests cover filtering, stability, freshness and interruption behavior.
The assistant can build/install the app when the phone is available, read ESP32
status and log commanded pulses. Without external position feedback or a view
of the mechanism, those checks cannot establish that real pins rose/returned,
that servo travel is correct, or that walking guidance is safe. Moving scene
objects and confirming physical output still require human observation or an
appropriate camera view. This update does not run unattended physical sweeps.

## References

- https://developer.apple.com/documentation/arkit/arplaneanchor
- https://developer.apple.com/documentation/arkit/arplaneanchor/classification-2hi2p

Apple documents classified floor/table surfaces and warns classification may
arrive later than plane detection. Existing manual calibration remains the fallback.

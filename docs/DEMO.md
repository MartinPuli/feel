# FEEL demo and recovery

Use a **seated/bench live demo only after hardware bring-up passes**. Until then,
show the offline production replay: `.artifacts/production/index.html`. The app's
Simulation mode also displays synthetic feedback and intentionally sends no BLE
commands. Neither is a recording of real pins.

## 90-second demonstration

1. **0–15s:** Explain the seven directions and four distance rows. Show wrist and
   finger orientation. State whether this is live hardware or simulation.
2. **15–40s:** Move a stationary test obstacle left/centre/right or step the replay.
   Point out the nine-byte packet and one selected row per column.
3. **40–60s:** Select a target; show its highlighted column. Name the actual mode
   (chair/person model, EXIT text, or door candidate). Do not call a candidate a
   verified door. Optional Beacon only if both phones passed device tests.
4. **60–75s:** Stop sensing/disconnect or select the watchdog replay. Show neutral
   command and loss status. Explain that the controller cannot measure a jam.
5. **75–90s:** Show executed software results and physical measurements separately.
   State the prototype's indoor and mechanical limits, plus next validation step.

Spatial Memory belongs to the separate V2 demo only after its checks pass:
Remember a place, move/turn, Recall, and feel its bearing. Return indicates a
straight-line bearing, **not** a verified obstacle-free route.

For the isolated V3 software demo, open the advanced recorded replay or the app's
Memory simulation. Expand **Voice, saved map and feedback**, type `remember Desk`,
move back and type `recall Desk`. Select Reduced and show that the obstacle pins
stay unchanged while the target highlight starts quiet. The recorded replay also
shows archive rejection, inactive restore and settling gates using synthetic map
evidence. It is not footage of real relocalization. Save/Load and microphone/QR
camera demonstrations require actual device checks; use the typed fallback until
then. See ADVANCED.md for the real-device sequence and recovery requirements.

## Recovery

- Tracking/depth unavailable: stop, restore the documented mount, recalibrate.
- BLE disconnected: stop, select the exact puck, reconnect; no queued old writes.
- Motor output disabled/fault: inspect board status and measured limits; do not
  remove the gate merely for judging. Use simulation if physical checks are incomplete.
- Mechanical jam/heat/buzzing: cut servo power immediately; show recorded software.
- App/build unavailable: open the self-contained production replay and explain
  that the Apple adapter's device verification remains pending.

Prepare an offline browser copy, source commit, concise test report and an actual
backup video if hardware works. Obtain consent before recording people. Keep
simulated captures labeled and distinct from real-device footage.

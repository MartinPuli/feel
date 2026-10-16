# FEEL demo and recovery plan

**Current demo mode: SIMULATION. Physical hardware, live iPhone sensing and the original production apps are NOT VERIFIED.** A virtual pin display is a software model, not a video of functioning hardware.

## Prepare the software demonstration

From the repository root, run:

```bash
python3 -m unittest discover -s validation/tests -v
python3 validation/run_scenarios.py --output .artifacts/simulation
```

Open `.artifacts/simulation/index.html` in a browser; it works offline. Keep the matching `.artifacts/simulation/report.json`. The report shows logical pin selection and nominal angle commands, not measured physical motion. Scenario traces are computed by a specification model; no hardware I/O occurs.

A generated copy is checked in at `demo/feel-simulation.html` for offline use without rerunning Python. Its scenario fingerprint is in `docs/evidence/scenarios-summary.json`. Browser rendering and interaction were not verified in the engineering environment because no browser executable was installed; the team must open it and rehearse on its demo laptop. JavaScript syntax checks passed.

For the complete release check, use:

```bash
python3 scripts/check_sources.py
python3 scripts/run_v2_checks.py --output .artifacts/v2-checks
```

The full V2 checker is expected to return a nonzero **BLOCKED** result while the original sources are absent; a passing simulation does not override it. Follow [SOURCE-IMPORT.md](SOURCE-IMPORT.md) to recover those sources. Keep the terminal output and generated report from the same revision. Before presenting:

- [ ] The simulator starts using only checked-in code and documented prerequisites.
- [ ] The visible surface says **SIMULATION — synthetic inputs, no connected hardware**.
- [ ] Show the seven-column/four-position model, raw nine-byte packet, selected pin state and elapsed/model time where supported.
- [ ] Replay one normal obstacle case, one highlight case and one timeout/tracking-loss case that the implementation actually supports.
- [ ] Show test evidence from `TEST-REPORT.md`; distinguish executed tests from blocked original builds.
- [ ] Save a short recording/screenshots of this exact run as backup, labeled simulation and dated. A generated scenario file alone is not a recorded physical demonstration.

Do not run a nonexistent board command or imply recovered source exists. If the simulator's command/interface changes, update this checklist alongside the implementation before demo rehearsal.

## Honest 90-second script

| Time | Say | Show |
|---|---|---|
| 0–15 s | “FEEL explores spatial information through touch. The proposed palm display has seven columns and four distance positions, driven by seven servos.” | Mechanism sketch or labeled model. Say explicitly if any physical object is an unpowered part. |
| 15–30 s | “We are showing a software simulation. The original engineering handoff predates this event; its CAD, board firmware and phone apps were not in the repository we received.” | SIMULATION label and concise provenance note. |
| 30–48 s | “Synthetic inputs become this nine-byte packet. Each column can select one pin. Near-to-far distance runs from wrist toward fingers.” | Normal scenario, packet bytes and selected pins. |
| 48–63 s | “The same interface can highlight a target. This is a modeled target, not a live camera detection.” | Supported synthetic highlight scenario. |
| 63–78 s | “Now the valid input stops. Watch the modeled timeout clear the command. This checks software behavior; real pin-return time is still unmeasured.” | Actual timeout scenario and report. |
| 78–90 s | “Our next gate is a manually tested single column, then calibrated powered movement and real phone integration. We have documented the missing measurements and failure tests instead of claiming they passed.” | Release status and first three hardware actions. |

If a scenario fails, describe the observed failure. Do not edit a screenshot to imply success. This draft deliberately makes no research-statistic, clinical-effectiveness or “first ever” claim.

## Upgrade to a physical demo only after recorded passes

Required evidence: recovered source/builds; reviewed wiring; manual P1–P5; one-column calibration; seven-column load/timeout checks; confirmed phone-to-palm direction; actual live feature tests. See [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md) and [CALIBRATION.md](CALIBRATION.md).

Then replace only the beats that have real evidence:

1. Start stationary with a known obstacle and show live sensor input, transmitted packet and corresponding physical pin.
2. Move the target left/center/right and demonstrate a verified highlight. Use a door/EXIT/person only if that exact live detector has passed; use teammate-phone finding only after its two-phone direction/rate checks pass.
3. Stop the sender and show real failure behavior. Present firmware timeout and measured physical return separately.
4. A short walking task is optional, after the bench gates, in a clear supervised indoor area with a spotter. Never use unsupervised blindfolded walking as a demo shortcut.
5. Show actual test counts and failures. Keep simulation and live footage separately labeled.

**Spatial Memory:** omit unless the separate V3 branch has passed its gate and the demonstrated behavior is actually integrated. A proposed “Remember → Move → Recall → Feel” sequence is not a completed feature.

## Recovery during judging

| Failure | Immediate response | Honest fallback |
|---|---|---|
| Servo jam, heat, unexpected movement or power instability | Disconnect servo power; remove the wearer from the test | Labeled simulator; explain the observed physical failure |
| BLE or phone tracking unavailable | Stop guidance and display unavailable state | Replay a recorded real run if available, clearly labeled recorded; otherwise simulation |
| Detector cannot find the target | Stop that feature; do not substitute a scripted “live” result | A verified simpler feature or labeled synthetic target |
| Optional teammate finding fails | Omit it | Verified obstacle/target demonstration |
| Simulator launch fails | Capture the error and stop troubleshooting on stage | Dated recording or screenshots labeled SIMULATION; state that this is recorded |
| No software recording available | Explain the design and show the reports | No claim of a running demo |

## Team rehearsal / submission card

Run revision: ____ · Operator: ____ · Date/time: ____ · Demo mode: ____ · Actual command: ____

Scenario result/evidence: ____ · Backup recording: ____ · Physical results if any: ____ · Stop operator: ____

Per the supplied event summary, submit Devpost **before Sunday, October 18, 2026, 8:00 AM EDT (12:00 UTC)**. Rehearse and upload assets before the final window; confirm any changed rules with organizers. In-person judging is listed as 9:00 AM–noon. No submission or outreach is performed by this document.

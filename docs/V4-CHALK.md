# FEEL V4 — grounded commands and measurable improvement

V4 extends the validated V3 baseline `e56e141`. Main remains V1, spatial memory
remains V2, and the advanced offline features remain V3. V4 is developed on
`codex/v4-chalk` for publication as `feel/v4-chalk`.

## Product promise

Say what you mean, select a real remembered place, correct a misunderstanding,
and compare the next interpretation against the same evidence. FEEL provides
bearing and distance to a remembered position. It does not plan a traversable
route around walls, identify people by face, or certify safe travel.

Chalk has two concrete jobs: its Model Gateway runs interpretation against the
current place list, and its Evaluations platform compares decisions against
versioned cases. The backend records explicit feedback and timings. Chalk does
not automatically train or deploy a better model: FEEL supplies the task,
validation, correction policy, scoring and release decision.

## Request and action boundary

1. The user explicitly enables cloud commands and supplies the FEEL service
   endpoint and application token. The provider's Chalk key stays on the server.
2. Typed text or a final on-device speech transcript is sent with the session ID,
   place IDs/names, tracking validity, restoration state and run mode. No camera
   image, AR map bytes, audio recording or raw coordinates are required.
3. The server calls Chalk with bounded context and validates the returned action.
   Unknown place IDs, malformed actions and unsupported requests cannot become
   tactile commands. Ambiguous destinations should produce clarification.
4. The app checks that the request and sensing session are still current before
   applying a supported action through its existing memory methods. Stop and
   session changes invalidate outstanding work. Live sensor checks remain local.
5. Optional feedback retention stores the original context and explicit correction
   for replay. Without retention consent, metrics must not retain command text or
   place names. Silence is never labeled as positive feedback.

Cloud failure never means an action succeeded. Simulation remains conspicuously
labeled and never sends synthetic movement to Bluetooth. The local strict-command
path remains available when cloud interpretation is disabled.

## Hardware boundary

The user explicitly requires version-independent hardware compatibility. V4 must
preserve the existing nine-byte BLE contract, column mapping, nominal pulse
limits, timeout behavior and controller implementation. The LLM returns symbolic
intent and existing place IDs only. The local memory/perception/tactile pipeline
remains the sole source of packets sent to the unchanged Bluetooth adapter.

`python3 scripts/check_chalk_boundary.py` compares protected files against the
validated V3 baseline. CI runs it alongside behavioral tests. No firmware upload
is part of V4 installation. Source equality does not prove electrical/mechanical
safety, and a wrong intent can still select the wrong destination; those risks
are evaluated separately rather than described as impossible.

## Improvement loop

A correction identifies the intended place from the actual session, rather than
letting a model invent a coordinate. A session-scoped association may improve a
later identical request; it must not leak into another map or user session.

For broader improvement, freeze request context and labels into an evaluation
revision. Compare a baseline and candidate on the same inputs. Keep explicit
corrections out of the input for the original failed attempt; later personalized
attempts may use an already-established association. Separate those two claims.

Measure grounded action accuracy, appropriate clarification, unknown-place and
stale-context rejection, and latency. Report sample counts, failures, p50 and p95,
model/prompt versions and whether data is synthetic or consented real interaction.
Latency measures must identify their boundaries: server duration is not complete
voice-to-action duration. A faster wrong destination is not a better release.

A replay that finishes successfully can still contain failed rows. Inspect both
run-level and row-level results; preserve Chalk dataset, evaluation and run IDs.
No unreviewed prompt or model change automatically reaches a physical device.

## Hackathon demonstration

1. In Memory simulation, save two places with distinct names. Show the simulation
   label; do not describe it as physical navigation.
2. Enable the real Chalk connection and ask a natural-language recall question.
   Show the chosen existing place, response timing and resulting virtual guidance.
3. Make an ambiguous request. Show a clarification, then select the intended place
   as explicit feedback. Repeat and explain any session-scoped personalization.
4. Stop while an interpretation is pending. Verify that the late reply cannot
   restart guidance.
5. Open the recorded evaluation report. Show one successful case and one failure,
   the exact context/expected result, and a baseline/candidate comparison. Only
   claim a measured improvement if the recorded results actually show one.

This demonstrates the sponsor criteria supplied by the user: impact, use of
contextual data, and rigorous evaluation. Awards remain the judges' decision.
No messaging integration or additional sponsor dependency is part of V4.

## Dependencies and release evidence

Requires a Chalk environment with a working model connection, scoped Gateway API
key and environment ID. Evaluations require enabled dataset storage and Function
queue/authentication. Managed serverless signup may enable these by default;
verify the actual account. A browser login alone is not backend configuration.

The application service needs an authenticated HTTPS deployment for a real phone.
Local mocks prove transport/lifecycle logic only. Real Gateway requests and hosted
Chalk evaluations must be recorded separately from local unit tests. Real BLE,
LiDAR, map restoration and seven-servo validation remain separate hardware gates.

Current implementation/validation status is tracked in `V4-CHALK-STATUS.md`.

## Official references

- [Model Gateway](https://docs.chalk.ai/docs/model-gateway)
- [Evaluation quick start](https://docs.chalk.ai/docs/evaluations/quick-start)
- [Evaluations](https://docs.chalk.ai/docs/compute/evaluations)
- [Dynamic context queries](https://docs.chalk.ai/docs/compute/dynamic-chalk-queries)

Consulted October 17, 2026. SDK/environment availability must be checked against
actual execution rather than inferred from these documents.

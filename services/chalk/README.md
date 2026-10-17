# FEEL V4 Chalk service

Real Chalk Model Gateway integration with grounded intent validation, session-scoped
explicit corrections, immutable consented snapshots and measured evaluation.
No hardware commands, coordinates or route plans are produced. Existing V3 local
commands remain available when this optional service is unavailable.

## Run

Python 3.9+ standard library suffices for server and local evaluation. Configure
these environment variables outside Git (never paste secret values into reports):

- `FEEL_API_TOKEN`: random app-service bearer token, at least 32 characters.
- `CHALK_ROUTER_API_KEY`: issued Chalk Model Gateway key (not an OAuth client secret).
- `CHALK_ENVIRONMENT_ID`: Chalk environment ID.
- `CHALK_MODEL`: an available connection-prefixed model or published route; no
  hardcoded model availability is assumed.
- Optional `CHALK_GATEWAY_URL`: HTTPS base, default `https://api.chalk.ai/v1/router`.
- Optional `CHALK_TIMEOUT_SECONDS`: default 4, maximum 15; no automatic retry.
- Optional `FEEL_DB_PATH`: private persistent SQLite path.
- Optional `PORT`: default 8787.

```sh
cd services/chalk
python3 server.py
```

The service binds **127.0.0.1** only. Use an authenticated HTTPS reverse proxy to
make it reachable from an iPhone; configure body/time/concurrency/rate limits at
that proxy. Do not expose Python's development HTTP server directly on the public
internet. Configure the app with the proxy's HTTPS root and FEEL_API_TOKEN, never
the Chalk key. Provision a separate service/token/database per demo user; this is
not a multi-tenant identity service. Session IDs must be unpredictable UUIDs.

## API

See `contract.json` for exact examples. All endpoints require
`Authorization: Bearer <FEEL_API_TOKEN>` and JSON, maximum 32 KiB.

- `POST /v1/interpret`: validates context and returns an allowed decision. The app
  must revalidate request/session identity, place existence and tracking before
  applying it. Tracking loss or session change after submission invalidates it.
- `POST /v1/feedback`: requires `session_id` in body or `X-Feel-Session-ID` header,
  matching the trace. `outcome` is `correct` or `incorrect`; optional
  `corrected_place_id` is allowed only for incorrect feedback and an ID that
  existed in the consented immutable snapshot. The correction stores a phrase
  association for the same session; **it never executes an action**. Repeat
  feedback is rejected rather than silently changing the historical label.
- `POST /v1/delete-session` with `{ "session_id": "..." }`: deletes snapshots,
  metrics and learned phrase associations for that session.

Errors are `{ "error": "stable_code" }` with 400 invalid input, 401 bad token,
404 missing resource, 409 duplicate request/feedback, 502 bad gateway/model
response, 503 missing configuration or 504 timeout. No upstream response body,
credential or request text is logged. Missing configuration never returns a mock
successful decision. Exact Stop commands bypass the gateway; the app's actual
Stop control must remain entirely local as well.

Decision keys are exactly `action`, `place_id`, `name`, `message`.
Recall requires an existing ID and null name. Return_to_point requires both null
and context.has_return_point=true (omission defaults false). Remember requires a
name of at most 40 characters and null ID. Other actions require both null.
Duplicate destination names force clarification. Tracking invalid or restoring
blocks recall/remember/return_to_point. Semantic ambiguity also relies on the
model and holdout tests: schema validation does not prove intent correctness.

## Consent and retention

The app must obtain separate explicit authorization to send a request to the
cloud. `consent` controls **local server retention**, not whether inference occurs.
When false, only opaque request/session/trace IDs, action kind, latency, timestamp
and feedback outcome are stored. No utterance, place names, model message,
context or aliases are retained. Such traces cannot produce correction aliases
or replay datasets. The current utterance/context still go to Chalk/provider for
inference; their retention policies must be configured independently.

When true, the pre-feedback request/context, aliases and decision are stored in a
0600 SQLite file. Correctness labels are separate columns, never inserted into the
historical input. Explicit correction is a session-limited preference, not model
training. A stopped/new app session must use a new session UUID. Delete sessions
when the demo ends. On request/export access the service prunes traces older than
24 hours and aliases with no remaining session trace. Configure FEEL_RETENTION_SECONDS
(minimum 60, maximum seven days) to shorten this window; offline database files
need operator deletion if the service no longer runs. No raw audio/video is accepted or stored.

## Evaluation and improvement

```sh
python3 -m unittest discover -s services/chalk -v
python3 services/chalk/evaluate.py validation/chalk/holdout.json --output /tmp/feel-live-report.json
```

Run from repository root. A root object containing `cases` is also supported. The runner accepts either `{case_id,request,expected}`
or `{case_id,snapshot:{request,aliases},expected}` rows. It calls the real Chalk
Gateway, freezes inputs by SHA-256 and measures correctness, grounded IDs,
tracking guards, latency-budget success, p50/p95 and errors. Repeat with a second
configured `CHALK_MODEL` and compare the **same dataset hash**. Timing is measured
server-side inference plus validation, not microphone-to-motion latency. Timeout
and provider failures count as failures. The target budget is configurable and
not a latency guarantee. `--mock` is a fixed abstaining fake transport, prominently
labeled `MOCK_NOT_LIVE`; it is not accuracy evidence.

`evaluate.export_feedback(service)` exports only consented, explicitly labeled
examples. Incorrect feedback without a corrected reference is excluded from
accuracy scoring. Corrections become expected labels, never historical aliases.
A later interaction may legitimately contain an earlier confirmed alias. Keep
those later cases separate from held-out unseen phrases; do not claim training
success from memorizing the same corrected phrase.

### Genuine hosted Chalk Evaluations

Install `chalkcompute` and `pyarrow` in a separate environment; authenticate with
Chalk CLI and select the environment. Ask Chalk to confirm Evaluations, async
Function queue and dataset storage are enabled. Then:

```sh
python3 services/chalk/chalk_evaluation.py validation/chalk/holdout.json \
  /tmp/feel-live-report.json --name feel-v4-candidate-a --output /tmp/feel-hosted-eval.json
```

This uploads **real candidate outputs from Gateway runs** and their pinned context,
creates a Chalk Evaluation with a recorded-output task and four deployed scorers
(exact intent/destination, grounding, tracking guard, latency budget), runs it and
reads the result dataset. It intentionally does not claim new remote inference:
model calls already happened in evaluate.py. Mock reports are rejected. A hosted
SUCCEEDED status with missing or error rows fails the local gate. Publish only
when correctness and safety cases pass and measured latency is acceptable; no
automatic prompt change, training or production promotion is implemented.

Live Gateway access, actual model availability, SDK deployment and hosted scores
remain **NOT RUN until credentials/environment access are supplied**. Local unit
mocks verify contracts and failure handling, not Chalk performance.

Official sources consulted October 17, 2026:
- https://docs.chalk.ai/docs/model-gateway
- https://docs.chalk.ai/docs/evaluations/quick-start
- https://docs.chalk.ai/docs/evaluations/scorers

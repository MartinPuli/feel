# Benjamin handoff — FEEL V4 + Chalk

## Start here

The user requested publication so Benjamin can continue. V4 is based on the tested
V3 commit `e56e141`, with its V1 baseline `b780519`. Main has continued independently;
V4 does not claim to include later unrelated V1 work. V1 stays on `main`, V2 on
`feel/v2-spatial-memory`, V3 on `feel/v3-advanced`, and this work is on
`feel/v4-chalk`. The historical `feel/v1-foundation` remote branch was deleted only
after verifying it was entirely contained in main (`2c2ae84` at the check).

```sh
git fetch origin
git switch --track origin/feel/v4-chalk
```

Use a clean checkout; do not overwrite work from another branch. See
[V4 architecture and demo](V4-CHALK.md), [service setup](../services/chalk/README.md)
and [actual validation status](V4-CHALK-STATUS.md).

## What exists

- iOS optional Chalk panel under Settings, separate cloud-sharing and retention
  opt-ins, HTTPS service configuration and Keychain application-token storage.
- Typed/final voice requests with current session place IDs, tracking state and
  explicit return-point availability. Stop remains local.
- Guarded application through existing local memory methods. Late replies are
  rejected after cancellation/session changes, stale tracking or a four-second
  response deadline. Remember rejects a phone displacement over 20 cm while waiting.
- Python authenticated service calling the real Chalk Model Gateway. Validated
  symbolic actions only; no coordinate generation, routes or raw servo commands.
- Explicit correction feedback, session-scoped phrase associations, immutable
  consented pre-feedback snapshots, bounded retention and session deletion.
- Production-path replay, latency/correctness scoring, a genuine Chalk SDK hosted
  evaluation stage, and an HTML comparison report generator.
- Twenty-four authored synthetic acceptance cases. These are not recorded users,
  hardware tests or evidence of model accuracy. Mock transport results are labeled.

## Hardware boundary — user requirement

Do not change ESP32 pins, servo pulse limits, CAD, nine-byte BLE protocol, tactile
encoder or the Bluetooth writer to add intelligence. Chalk selects an intent and
existing destination; the current phone pipeline determines packets. No firmware
flash is required for this integration. Run:

```sh
python3 scripts/check_chalk_boundary.py
```

The guard checks 67 protected baseline files. Existing source equality does not
prove the servo is currently moving: the user's unresolved physical issue remains
separate. Seven-servo production validation is still pending.

## Immediate blocker: Chalk account

The official `https://chalk.ai/hackharvard` signup reached an eligibility screen:
"Your email must end in .edu". The attempted Gmail account could not claim this
link. No environment, API key or model has been configured. Obtain an eligible
account or ask the Chalk team to enable the participant's account. Do not bypass
eligibility or invent credentials. Nothing has been sent to a mentor/team member.

After access:

1. Select the actual Chalk environment and confirm a working model connection.
   Obtain a scoped Gateway API key, environment ID and available model ID.
2. Configure the variables from `services/chalk/README.md` outside Git. The iPhone
   receives only FEEL_API_TOKEN, never the Chalk key. Configure provider retention
   independently; the app's retention toggle controls our server storage only.
3. Run one real request, then the live acceptance suite. Check unexpected outputs
   and error cases before describing the feature as working with Chalk.
4. Authenticate Chalk CLI, verify dataset storage/Function queue/evaluations, and
   run hosted scoring. Record dataset/evaluation/run IDs and row errors.
5. Deploy the service behind HTTPS, connect the phone, and test the actual
   voice-to-action flow. The service is a one-user demo instance, not multitenant.

## Verification commands

```sh
python3 -m unittest discover -s services/chalk -v
python3 -m unittest discover -s scripts/tests -v
python3 scripts/check_chalk_boundary.py

# Requires actual Chalk credentials in the environment:
python3 services/chalk/evaluate.py validation/chalk/holdout.json \
  --output /tmp/feel-live-report.json

# Use a separate Python 3.12 environment for the pinned official SDK:
python3 -m pip install -r services/chalk/requirements-evaluation.txt
python3 services/chalk/chalk_evaluation.py validation/chalk/holdout.json \
  /tmp/feel-live-report.json --name feel-v4-candidate-a \
  --output /tmp/feel-hosted-eval.json

# Candidate alone does not imply improvement; add a measured --baseline to compare:
python3 scripts/chalk_report.py /tmp/feel-live-report.json \
  --output /tmp/feel-chalk-report.html

# Full native iOS regression gate (Mac with installed Xcode + XcodeGen):
python3 scripts/fetch_model.py
bash scripts/check_ios.sh
```

If the requirements filename changes, follow the service README/source. The hosted
stage scores recorded real Gateway outputs; it does not execute fresh remote
inference or train model weights. Keep expected labels out of original inputs.
Use a new holdout if these cases become tuning examples. A successful hosted job
can contain failed rows: inspect them, do not rely solely on its status.

## Demo and claim boundaries

Show current places → natural request → existing destination → feedback → replay
comparison. Show cancellation and a missing destination, not just the happy path.
If using Memory simulation, keep its label visible; it never drives physical BLE.
Actual model quality/latency and physical end-to-end movement have not been proven
by mock tests. No automatic self-training, deployed prompt promotion, obstacle-free
route planning or face recognition is implemented. No award is guaranteed.

## Offline update

Read [Offline commands](OFFLINE-COMMANDS.md). Supported local phrases now bypass
Chalk even when enabled; use an unresolved phrase when demonstrating cloud
feedback. Connectivity errors enter local-only mode with an explicit future-command
retry button. This is a finite phrase grammar, not a trained local language model.

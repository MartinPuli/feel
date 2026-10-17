# FEEL Where-is (Chalk)

## Where Chalk is used

- **Every model call goes through Chalk's Model Gateway.** The iPhone app's `where_is`
  tool (`ios/Lantern/Services/WhereIsService.swift`, `ChalkGateway.swift`) posts the
  camera photo and the question to `{host}/v1/router/chat/completions` with the gateway
  key and `X-Chalk-Env-Id`; the model is `openai/gpt-6.1-sol` by default and can be
  changed in the app's Where-is setup without a rebuild. The Python client here
  (`feel_chalk/gateway.py`) uses the same route for checks and evaluations.
- **Chalk Evaluations prove the tool.** `feel_chalk/where_is_eval.py` uploads labeled
  venue photos as a Chalk dataset, deploys the gateway call as the task, and scores every
  row with three custom scorers: `points_correctly` (box centre inside the labeled box, or
  a correct "not found"), `reply_is_well_formed` (obeys the JSON contract) and
  `false_found` (claimed to see something that is not there: the dangerous error for a
  blind user). Running it twice with `--model` compares `gpt-6.1-sol` against the 20×
  cheaper `gpt-6-luna` in the Chalk dashboard.
- **The contract is shared.** `protocol/where-is-prompt.txt` and
  `protocol/where-is-cases.json` are the single prompt and parser cases that both the
  Swift app and the Python evaluation are tested against, so the thing being evaluated is
  the thing the phone runs.

Status (2026-10-17 02:30): gateway verified end to end from this machine and from the app
in the iOS Simulator (self-test with a sample photo). The evaluation code is written and
unit-tested; the Chalk run itself is **blocked** until someone runs `chalk login` and
collects venue photos (see "Run the evaluation").

## Scaffold notes

The user asks "Where is the registration desk?". The phone sends one camera frame
and the question through **Chalk's Model Gateway** to a vision model. The model
returns a box in the photo, or says not found. The phone looks up LiDAR depth at
the box centre, pins that spot in the AR world, and the puck taps toward it.
**Chalk Evaluations** score how often answers point at the right thing and how
often the model correctly says not found, on labeled venue photos.

No web app is involved. The iPhone calls the gateway directly; evaluations run
from this folder and are read in Chalk's dashboard.

## What exists

| Piece | File | State |
|---|---|---|
| Shared prompt and parser cases | `protocol/where-is-prompt.txt`, `protocol/where-is-cases.json` | Done; both languages are tested against them |
| Gateway client, settings | `feel_chalk/gateway.py`, `feel_chalk/config.py` | Done (standard library only) |
| Answer parser, request body, scoring rule | `feel_chalk/where_is.py` | Done, unit-tested |
| Connection check | `check_connection.py` | Done |
| Evaluation | `feel_chalk/where_is_eval.py`, `feel_chalk/images.py` | Written, unit-tested; the Chalk run needs venue photos and an Evaluations-enabled environment |
| Shared prompt, request body and parser | `ios/Shared/FeelCore/Sources/FeelCore/WhereIs.swift` | Done, unit-tested; no networking, so FeelCore stays portable |
| iPhone request path | `ios/Lantern/Services/ChalkGateway.swift`, `WhereIsService.swift` | Done; posts the body with the gateway key and `X-Chalk-Env-Id`, 12 s timeout, then the on-device fallback |

In the app, the `where_is` voice tool captures the current ARKit frame as a JPEG
(long side at most 1024 px, quality 0.6), posts it through `ChalkGateway`, looks up
depth at the box centre and holds the target until it is reached, cancelled or
replaced by a new ask. Only targets in front of the camera within about 4 m can be
shown on the puck.

## Setup (things only you can do)

1. Sign in at https://chalk.ai/hackharvard with your HackHarvard account.
2. In the dashboard, **Model Gateway → Routing → Connections**: check a vision-capable
   provider connection exists (add one if the hackathon environment has none).
3. **Model Gateway → Access → API keys**: create a key scoped to that connection. Copy it; it is shown once.
4. Note your **environment ID**.
5. `cp chalk/.env.example chalk/.env` and fill in the three values. `.env` is git-ignored;
   the repo must go public, so never paste the key into code.
6. For evaluations: install the CLI (`curl -s -L https://api.chalk.ai/install.sh | sh`),
   run `chalk login`, then `chalk environment <environment-id>`. Ask the Chalk team on
   Slack whether Evaluations and the Function queue are enabled in your environment.

## Run the evaluation

1. `curl -s -L https://api.chalk.ai/install.sh | sh`, then `chalk login` (opens a browser)
   and `chalk environment bnsb82aac313`. Ask the Chalk team on the event Slack if the
   first run reports Evaluations or the Function queue as disabled.
2. Take 20–30 photos at the venue from chest height with teammates' consent and no
   bystanders' faces. Save them under `chalk/data/photos/` (git-ignored).
3. Label them in `chalk/data/labels.jsonl`, one JSON object per line as in
   `evals/labels.example.jsonl`; at least a third of the rows should ask for something
   that is **not** in the photo (`"box": null`).
4. `python3 evals/validate_labels.py data/labels.jsonl` → "N rows valid".
5. `.venv/bin/python -m feel_chalk.where_is_eval data/labels.jsonl --model openai/gpt-6.1-sol`,
   then again with `--model openai/gpt-6-luna`. Photos are re-encoded on upload the way
   the phone sends them (long side at most 1024 px, JPEG quality 0.6). The output ends
   with the evaluation, suite and run ids; read the three scores per run in the Chalk
   dashboard and record them here with those ids.

## Check the connection

```sh
cd chalk
python3 check_connection.py          # reachability, key, model; no tokens used
python3 check_connection.py --chat   # also one tiny text request
python3 -m unittest discover -s tests -v
```

Exit 0 = all passed, 1 = a failure, 2 = blocked on setup. The check never sends photos.

## Privacy and safety

Photos leave the phone only when the user asks, and may include other people.
Keep evaluation photos to consented team captures in `chalk/data/` (git-ignored).
A found target indicates direction only, not a clear path. Malformed or unsure
replies must never produce a tap.

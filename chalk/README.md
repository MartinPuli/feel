# FEEL Where-is (Chalk) — scaffold, not wired into the app yet

The user asks "Where is the registration desk?". The phone sends one camera frame
and the question through **Chalk's Model Gateway** to a vision model. The model
returns a box in the photo, or says not found. The phone (still to build) looks up
LiDAR depth at the box centre, pins that spot in the AR world, and the puck taps
toward it. **Chalk Evaluations** score how often answers point at the right thing
and how often the model correctly says not found, on labeled venue photos.

No web app is involved. The iPhone calls the gateway directly; evaluations run
from this folder and are read in Chalk's dashboard.

## What exists

| Piece | File | State |
|---|---|---|
| Shared prompt and parser cases | `protocol/where-is-prompt.txt`, `protocol/where-is-cases.json` | Done; both languages are tested against them |
| Gateway client, settings | `feel_chalk/gateway.py`, `feel_chalk/config.py` | Done (standard library only) |
| Answer parser, request body, scoring rule | `feel_chalk/where_is.py` | Done, unit-tested |
| Connection check | `check_connection.py` | Done |
| Evaluation | `feel_chalk/where_is_eval.py` | Stub; needs photos and an Evaluations-enabled environment |
| iPhone request/parse | `ios/Shared/FeelCore/Sources/FeelCore/WhereIs.swift` | Done, unit-tested; no app UI or networking call yet |

Still to build in the app: a "Where is…" button or voice question, JPEG capture of
the current ARKit frame, the gateway call, depth lookup at the box centre
(`ARPerception` already does this for door detections), and a target that persists
until reached or cancelled (current detections expire after 500 ms). Only targets
in front of the camera within about 4 m can be shown on the puck.

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

# FEEL Where-is: a `where_is` tool for the existing assistant, through Chalk — design

Date: 2026-10-17 (Saturday of HackHarvard). Devpost deadline: Sunday 8 AM ET.
Supersedes `2026-10-16-feel-voice-agent-design.md`: `main` already has an automatic
voice assistant (xAI Grok Voice realtime, tools in `ios/Lantern/Services/VoiceCommand.swift`,
executed by `LanternModel.performVoiceCommand`). This design adds one tool to it.

## Intent

A blind user wearing FEEL says "Where is the registration desk?" The assistant calls
`where_is`. The app takes one camera frame, sends it with the question through
**Chalk's Model Gateway** to a vision model, places the answer in the room with LiDAR
depth, and the puck taps toward that spot until the user reaches it, cancels, or
tracking is lost. When the puck cannot show it (behind, off to the side, beyond 4 m),
the assistant speaks a coarse direction. **Chalk Evaluations** score how often answers
point at the right thing and how often the model correctly says "not found" on labeled
venue photos. That is the Chalk sponsor entry: an agent tool on real-world data, with
a rigorous evaluation.

## Base

Branch `feel/chalk-where-is` = `origin/main` (2c2ae84) + the committed Chalk scaffold
(`chalk/`, `protocol/where-is-*`, `FeelCore/WhereIs.swift`). Connection to Chalk is
verified: `openai/gpt-6.1-sol` answered a real image request with a correct box and a
correct "not found" in under 4 s.

## Goals

1. `where_is(thing)` as a Grok function tool; the assistant confirms at once ("Looking
   for the desk."), and the result arrives seconds later as a spoken observation through
   the existing proactive-announcement path.
2. A held target: placed once in world coordinates, re-expressed every tick relative to
   the current camera pose, driving the puck through the unchanged nine-byte packet.
3. Coarse spoken direction when the puck cannot show the target.
4. Chalk gateway settings entered once in the existing Assistant modal and stored in
   Keychain, like the voice settings. No key in the repo or the app bundle.
5. Chalk Evaluation on labeled venue photos, plus a second run on a cheaper model for
   the pitch's cost/accuracy comparison.
6. README section "Where Chalk is used".

## Non-goals

Own speech pipeline, hold-to-talk button, judge view, agent routing evaluation
(Grok does routing on xAI's side), V2/V3 memory tools, GPS friend finding, Siri.

## Anti-goals

- Obstacle sensing is never reduced; `where_is` only adds a target.
- No guidance from a malformed, unsure or unverifiable model reply.
- A photo leaves the phone only when `where_is` runs; never on `get_status` or timers.
- No secrets in the repo. No hardware claim without a device test.

## Constraints

- iOS 16, SwiftUI, XcodeGen `ios/project.yml`; `FeelCore` keeps building on Linux (no
  UIKit/ARKit/URLSession/Security in it). `sh ios/scripts/test_portable.sh` and
  `bash scripts/check_ios.sh` stay green; V1 UI test identifiers stay valid.
- Packet, firmware, `TactileEncoder.encode` unchanged.
- Chalk Model Gateway: `POST {host}/v1/router/chat/completions`, headers
  `Authorization: Bearer <key>` and `X-Chalk-Env-Id`. No `temperature`.
- Where-is request timeout 20 s. Image long side ≤ 1024 px, JPEG quality 0.6.
- Puck field ±45° and 4 m; reached radius 0.5 m. Announcements go through
  `GrokVoiceSession.announce`, which already throttles to one per 5 s and stays quiet
  while the user speaks.

## Tool contract (decided)

`VoiceCommand.tools` gains:

```
where_is(thing: string)
"Find one thing the user names that is not in find_target's list, such as the
registration desk, a water fountain or the stairs. Takes one camera photo and points
the pins at it when found. Confirm once; the result arrives a few seconds later as an
observation. Call get_status to check progress."
```

`VoiceCommand.decode` → `.whereIs(String)`; `thing` is trimmed, 1–60 characters, no
control characters, exactly one argument. Instructions gain two lines: in Conversation
Flow, "For a thing not in find_target's list, call where_is with a short description;
it uses one camera photo, and the result comes later as an observation." In Guardrails,
"A where_is result is a model's reading of one photo, never a confirmed object."

`performVoiceCommand(.whereIs(thing))` is synchronous and returns:

| Condition | Result |
|---|---|
| `mode != .live` | `error: "Camera is not live. Ask the user whether to start it."` |
| Chalk not configured | `error: "Where-is needs Chalk setup in Assistant settings."` |
| `guidanceState != .live` | `error: "Sensing isn't ready. Calibrate or wait for tracking, then try again."` |
| otherwise | starts the lookup; `status: "Looking for the <thing> with one camera photo. The result arrives as an observation in a few seconds; call get_status to check."`, `pending: true` |

Outcome handling, on the main queue, by `LanternModel.handleWhereIs(_:)`:

| Outcome | Effect | Spoken line (via `announce`, not gated by the "Useful updates" toggle) |
|---|---|---|
| placed | `heldTarget` set; next tick's observation phrase announces it through the existing target-acquired path | "The <thing> was 3 meters to your right." (existing `VoicePhrasing` format, with the thing's name) |
| not visible | nothing held | "I couldn't see a <thing> in the photo." |
| no usable depth | nothing held | "I see the <thing>, but it's too far to point at." |
| failed (timeout, offline, malformed reply) | nothing held | "I couldn't look just now. Try again." |

If `announce` cannot speak at that moment, the line is kept in `whereIsNotice`, which
`get_status` returns as `where_is`, so the assistant can relay it when asked.

## Held target (decided)

`HeldTarget { position, label, worldEpoch, setAt }` in `FeelCore`.
- `observation(pose:now:worldEpoch:)` → `TargetObservation` stamped `timestamp: now`,
  confidence 1, the thing as label; nil when the epoch differs, the pose is invalid,
  the bearing is outside ±45°, or the distance band is 0.
- `relative(pose:)` → full-circle bearing (−180..180, left negative) and horizontal
  distance. `reached(pose:)` = distance < 0.5 m.
- `spokenDirection(pose:)`: |b| ≤ 45 and distance > 4 → "<thing> ahead, about N
  meters."; |b| > 135 → "<thing> is behind you."; b < 0 → "<thing> is to your left.";
  else "<thing> is to your right."; nil when the puck shows it.
- In `tick()`: the held observation takes precedence over finder and teammate targets.
  After encoding: reached → clear and announce "You're at the <thing>."; a changed
  `worldEpoch` (ARKit restart with reset tracking, interruption) → clear and announce
  "Lost tracking. Say it again."; otherwise, when the observation is nil but the target
  exists, announce `spokenDirection` (throttled by `announce`).
- Cleared silently by `stop()`, by `find_target`, and by a new `where_is`.
- `PerceptionFrame` gains `worldEpoch`, incremented by `ARPerception.start` on every
  `session.run` with `.resetTracking`.

## Where-is pipeline (decided)

1. `ARPerception.snapshot(completion:)` on the AR queue: `session.currentFrame` with
   normal tracking, valid mount and `sceneDepth` → `FrameSnapshot { timestamp,
   worldEpoch, pose, scaled intrinsics, DepthGrid, jpegBase64 }`. JPEG from
   `capturedImage` through `CIImage`/`CIContext`, long side ≤ 1024, quality 0.6.
   Nil when any input is missing (no photo is taken).
2. `WhereIsService.find(thing, snapshot, completion)`: question "Where is the
   <thing>?", `WhereIs.requestBody`, `ChalkGateway` with 20 s timeout, `WhereIs.parse`,
   `WhereIsPlacement.place(answer:snapshot:)`. A new call cancels the one in flight.
3. Placement: box centre (top-left fractions) → depth pixel `(cx·width, cy·height)` →
   `DepthGrid.medianDepth` (the existing 5×5 confidence-filtered rule, moved from
   `ARPerception`) → `unproject` → `worldPoint`.

## Chalk settings on the phone (decided)

`ChalkConfiguration { apiHost, routerApiKey, environmentId, model }`, valid when the
host is HTTPS with no credentials/query, the key is ≥ 16 characters without
whitespace, the environment ID is 1–64 characters, and the model is non-empty.
Stored by a generic `KeychainStore<Value: Codable>` (service
`org.feel.hackharvard.chalk`, account `gateway`); `VoiceConfigurationStore` is
re-implemented on the same generic. Entered in the Assistant modal (`VoiceSetup`)
under a "Where-is setup" heading: host (prefilled `https://api.chalk.ai`), environment
ID, key (secure field), model (prefilled `openai/gpt-6.1-sol`), Save, Forget.
`get_status` reports `where_is_available`.

## Evaluation (decided)

`chalk/feel_chalk/where_is_eval.py` (exists) on `chalk/data/labels.jsonl` with 20–30
consented venue photos, at least a third of them with the asked-for thing absent. Two
runs under one suite: `openai/gpt-6.1-sol` and `openai/gpt-6-luna`. Report pointing
accuracy, correct-not-found rate and false-found rate per model in `chalk/README.md`
with the run IDs. Needs the Chalk CLI, `chalk login`, `chalk environment bnsb82aac313`
and Evaluations enabled (ask the Chalk team if the first run is refused).

## Left to the builder

CIImage scaling details; exact SwiftUI layout of the setup fields; the custom-scorer
signature per Chalk's docs; the remaining dataset rows; copy of the two instruction
lines if the model misroutes in testing.

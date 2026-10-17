# FEEL V4 — voice agent, Where-is and judge view: design

Date: 2026-10-16 (Friday night of HackHarvard). Devpost deadline: Sunday 8 AM ET.

## Intent

A blind user cannot use FEEL's screen while wearing it: the phone sits on the chest,
screen inward. V3 already has push-to-talk speech and spoken replies, but only for exact
phrases ("find exit"). V4 lets the user say what they want in their own words. An agent
maps the request to one of the app's existing abilities (tools), confirms in a few words,
and the puck does the rest. "Where is X?" adds finding anything the user can name, placed
in the room with LiDAR. A judge view makes the invisible parts (what was heard, what the
agent chose, what the pins show) visible during the 3-minute judging demo.

Chalk's Model Gateway serves every model call; Chalk Evaluations prove the agent routes
requests correctly and that Where-is points at the right thing. That is the Chalk
sponsor entry ("a data-driven agent, and prove it works").

## Base and branches

- Build on `origin/feel/v3-advanced` (V1 perception/BLE + V2 spatial memory + V3 voice,
  maps, adaptive taps, barcode). New branch `feel/v4-agent`; merge `feel/chalk-where-is`
  (Chalk client, Where-is contract, `WhereIs.swift`).
- Risk: the team's original app (Ethan's, uncommitted) may be the demo app. Everything in
  `FeelCore` is UI-free Swift and ports; the `Lantern` UI work is specific to this branch.

## Goals

1. Spoken request → one tool → spoken confirmation (≤12 words) → puck guidance.
2. Deterministic first: the existing V3 grammar handles exact commands offline; the model
   is called only when the grammar does not match.
3. Where-is: photo + question → vision model → box → LiDAR depth → a target held in world
   coordinates until reached, cancelled, or tracking is lost. When the puck cannot show it
   (outside ±45°, behind, beyond 4 m), speak a coarse direction instead.
4. Judge view: one main screen (status strip, large puck, Heard/Did/Said, hold-to-talk);
   everything else behind a Setup sheet. Large text, VoiceOver labels kept.
5. Chalk evaluations: agent routing (tool + args accuracy, no disallowed tools) on ~40
   utterances; Where-is pointing accuracy on labeled venue photos.
6. README "Where Chalk is used".

## Non-goals (roadmap slide only)

GPS far-field friend finding, Find My (not available to third-party apps), routines and
calendar learning, fire-alarm detection, approaching-object pulse, Siri/App Intents wake
phrase, firmware pulse mode (belongs to whichever firmware the demo uses), shared maps.

## Anti-goals

- No tool can reduce obstacle sensing; the agent only adds or clears targets.
- No guidance from a malformed, uncertain or unverifiable model reply. Malformed → fixed
  spoken fallback, pins unchanged.
- No photo leaves the phone except on an explicit Where-is request.
- No secrets in the repo (it must go public). No claim that anything works on hardware
  without a device test.

## Constraints

- iOS 16, Swift 5.9+, SwiftUI, XcodeGen `ios/project.yml`. `FeelCore` must keep building
  and testing on Linux: no UIKit/ARKit/URLSession in it.
- Nine-byte packet and firmware unchanged.
- Chalk Model Gateway, OpenAI-compatible `POST {host}/v1/router/chat/completions` with
  `Authorization: Bearer <key>` and `X-Chalk-Env-Id`. Replies are plain JSON text (not
  native tool calling), so any provider behind the gateway works and both languages parse
  the same contract.
- V3's UI test identifiers (`memorySimulation`, `targetStatus`, `commandText`,
  `runCommand`, `voiceStatus`, `commandNotice`, `placeName`, …) stay valid.

## Agent contract (decided)

Shared files, tested from both Swift and Python:
- `protocol/agent-prompt.txt` — the system prompt (below).
- `protocol/agent-cases.json` — reply parser cases.

System prompt (exact copy):

```
You are FEEL's assistant for a blind user wearing a chest camera and a palm display of pins. The pins always show nearby obstacles; you cannot change that. You choose exactly one tool for what the user asks, then confirm in a few words.
Tools:
- find: kind is one of obstacles, door, exit, chair, person, teammate, barcode. Points the pins at that kind of target.
- where_is: thing is a short description of what the user wants to find. Uses the camera to find it.
- remember: name is a short name for the current spot.
- recall: name is a saved place to point to.
- return: points back to the return point.
- list_places: reads out the saved places.
- stop: stops finding targets. Obstacles stay on.
- status: reads out the current state.
- ask: question is what you need the user to clarify.
- none: nothing here can do what was asked; explain in say.
Rules: use "find" when the request matches one of its kinds; use "where_is" for anything else that could be seen. Use "ask" when the request is ambiguous. Never guess. "say" is at most 12 words, in the user's language.
Reply with one JSON object and nothing else: {"tool": "<tool>", "args": {...}, "say": "<confirmation>"}
```

Runtime context, rendered identically by Swift and Python and sent as the first user
message, followed by the utterance as the second:

```
Context:
language: en
finder: obstacles
floor calibrated: yes
puck connected: no
saved places: my seat, entrance
teammates: Sarah
camera available for where_is: yes
```
(`saved places` and `teammates` print `none` when empty.)

Reply rules: `tool` must be one of the ten names; `args` validated per tool (`kind` in
the enum; `name` 1–40 characters; `thing` 1–60 characters; `question` 1–120); `say` is
required text of 1–120 characters; extra args are ignored; a code fence around the JSON
is tolerated. Anything else is malformed.

Grammar path: a final transcript is first given to V3's `VoiceIntentParser`. A match
becomes the same decision with a fixed confirmation (English copy below; Spanish is the
builder's translation). Only an unmatched transcript goes to the model.

| Decision | Confirmation |
|---|---|
| find obstacles | "Obstacles only." |
| find door / exit / chair / person / teammate / barcode | "Looking for doors." / "Looking for exits." / "Looking for a chair." / "Looking for a person." / "Looking for your teammate." / "Looking for a code." |
| where_is X | "Looking for the X." |
| remember N | "Remembered N." |
| recall N | "Pointing to N." |
| return | "Going back." |
| list_places | the existing V3 list reply |
| stop | "Stopped. Obstacles still on." |
| status | composed: "Live, tracking OK, puck connected, finding exits." |
| fallback (malformed, timeout, offline) | "I didn't catch that. Try: find exit, or: where is the desk." |

`stop` clears the held target, stops memory guidance, and sets the finder to obstacles.
`where_is` when the camera is unavailable (not live, tracking not normal, no Chalk config)
speaks "I can't look right now." without calling the model. A new utterance cancels an
in-flight model call. Model call timeout 12 s; Where-is 20 s.

## Where-is pipeline (decided)

1. On `where_is(thing)`: take a snapshot on the AR queue: current frame as JPEG (long side
   ≤ 1024 px, quality 0.6, base64), the depth grid and confidence, scaled intrinsics,
   camera pose, timestamp and the AR session epoch. Speak the confirmation at once.
2. `POST` with `WhereIs.requestBody`; parse with `WhereIs.parse` (existing).
3. Found → box centre (top-left fractions) → depth pixel `(cx·width, cy·height)` → median
   depth (existing 5×5 rule) → unproject → world point → `HeldTarget`. No usable depth →
   speak "I see it but it's too far to point at." Not found → "I can't see a X from here."
4. Every 10 Hz tick while live: the held target's observation (timestamp stamped `now`,
   confidence 1) is the encoder's target, taking precedence over finder detections.
5. Cleared when: `stop`; reached (horizontal distance < 0.5 m → "You're at the X."); AR
   session epoch changes (interruption, restart → "Lost tracking. Say it again."); a new
   Where-is request.
6. Spoken coarse direction, at most every 3 s, only when the puck cannot show the target
   (bearing b in −180..180, left negative): |b| ≤ 45 and distance > 4 → "X ahead, about N
   meters."; |b| > 135 → "X is behind you."; b < 0 → "X is to your left."; else "X is to
   your right." Inside the field and within 4 m: say nothing, the pin shows it.

## Judge view (decided)

Main screen, top to bottom: status strip (mode chip LIVE/SIM/STOPPED; tracking OK/lost;
puck connected/not; "Obstacles ON" always); large `PuckView`; agent panel with three
lines "Heard: …", "Did: find exit (grammar | model | fallback) · 1.8 s", "Said: …";
full-width Hold-to-talk button (press starts listening, release finishes; VoiceOver
custom actions "Start listening" / "Finish"). A Setup sheet holds Live/Simulation/Stop,
camera height and calibration, finder picker, puck connection, teammate panel, command
language and typed command, memory and map panels, packet notes. Dark background, large
bold text, existing colours (blue obstacle, orange target, red for problems).

## Chalk pieces (decided)

- Phone config `ios/Lantern/ChalkSecrets.plist` (git-ignored; `ChalkSecrets.example.plist`
  committed) with `apiHost`, `routerApiKey`, `environmentId`, `model`. Missing file →
  model path disabled, grammar still works, status says "Chalk not configured".
- `chalk/feel_chalk/agent.py`: same prompt, context rendering and parser as Swift.
- `chalk/evals/agent-routing.jsonl`: ~40 rows `{"utterance","language","expected_tool",
  "expected_args"}`. Scorers: tool match, args match, allowed-tool safety.
- `chalk/feel_chalk/where_is_eval.py` (exists) on `chalk/data/` photos labeled in
  `chalk/data/labels.jsonl` (git-ignored; consented team captures only).
- README section "Where Chalk is used": gateway for every model call; evaluations for
  routing and pointing accuracy; datasets of utterances and labeled photos.

## Left to the builder

Exact SwiftUI layout and spacing; CVPixelBuffer → JPEG conversion method; the Spanish
confirmation strings; the remaining ~28 routing-dataset rows (paraphrases of the 12 given
in the plan); timer mechanics for the 3-second spoken cadence.

## Roadmap ideas (for the pitch, not this weekend)

Far-to-near friend finding (GPS then UWB), follow-a-guide, end-of-queue, routines and
calendar-aware targets, learning which rows a user confuses (V3 adaptive taps is the
seed), fire-alarm → exit, approaching-object pulse, take-me-back (V2 has it), shared
volunteer-tagged maps, Siri wake phrase.

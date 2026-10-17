# FEEL + Chalk

Figures: [FEEL at a glance](diagrams/feel-system.svg) · [one Where-is request](diagrams/where-is-path.svg) ·
[the evaluation loop](diagrams/chalk-eval-loop.svg) · [memory and venue knowledge](diagrams/chalk-context.svg) ·
[sensing to pins](diagrams/sensing-to-pins.svg) · [room memory](diagrams/room-memory.svg).

## Product direction

FEEL is an assistive camera and voice app for blind people. Its assistant should speak briefly, act on permitted commands, recognize uncertainty and remain useful when connectivity fails.

Use Chalk for model routing, reproducible evaluations and selected context services. Keep immediate controls, tracking validation and haptic packet generation on the phone.

This document consolidates research and source inspection from October 17, 2026. Proposed features below are not implemented unless explicitly marked. Account observations describe the last recorded checks, not continuous monitoring. Main is V1; V4 remains separate.

## Current state

| Component | Verified scope |
|---|---|
| Chalk gateway | Configured with two restricted OpenAI models; generic text and synthetic-image requests succeeded |
| Trace privacy | Default prompt/completion content logging disabled in Chalk traces |
| Voice | Existing direct OpenAI Realtime connection; audio does not pass through Chalk |
| Photo Where-is | Cloud request and local reply/depth validation exist in source |
| Local perception | Vision paths for EXIT text, people and rectangle-based door candidates |
| Local speech recognition | Limited target-word recognition associated with a V-sign interaction |
| Evaluation code | Photo validation and scorers exist; no verified real-photo model comparison |
| Production limits | Quota backend blocked configuration; authorized support report submitted |
| Hosted evaluation | Generic smoke run submitted; completion remains unverified in the recorded evidence |

No production model winner has been established. Physical sensing, headphone delivery and haptic performance need separate device tests. General local object detection requires model weights that were not found in the inspected iOS tree.

## Useful additions

| Priority | Addition | User benefit | Required work |
|---|---|---|---|
| First | Local voice controls and speech | Stop, mute, repeat and supported searches without internet | Local command grammar, microphone coordination, spoken results and device tests |
| First | Comparable evaluations | Avoid regressions when changing prompts or models | Correct metrics, shared deadlines, independent test cases and error review |
| Next | Agent context | Speak when relevant information changes without repeating cues | Authenticated context queries, timestamps and phone-side validity checks. **Chalk side implemented** on `feel/chalk-track` (`chalk/feel_context`: features, resolvers, named queries, `feel_chalk/context.py`); waits for the Postgres data source |
| Next | Downloadable venue information | Read previously downloaded accessibility information without internet | Reviewed sources, local storage, expiry and update handling |
| Later | Consented object history | Explain where and when an object was last seen | Ownership, retention, deletion and uncertainty handling. **`ObjectHistory` implemented** (latest confirmed find, relative-time sentence); the phone write path and the `last_seen` tool are pending |
| Later | Room memory | Point the pins at a place found on an earlier visit as soon as the room's printed tag is recognized, instead of a 2–12 s photo round trip | A printed tag as the room frame, local and shared storage, honest past-tense wording. **Implemented in software** on `feel/chalk-track`: FeelCore `RoomFrame` and `RememberedTarget`, a per-tag anchor store, `where_is` answering from memory with "say photo", `found_it`, Chalk `Anchor`/`RoomMemory` with the `room_anchors` query (shared rows only). Not yet: the phone's write to Supabase, a download of the shared memory, and any device test of the tag recognition or the cue |
| Later | External services | Extend the personal assistant through selected tools | Per-user authorization and independent action checks |

## Evaluations and model selection

Compare the configured candidates on identical inputs, prompts and task definitions. Freeze a separate test set before tuning. Split photos by capture session and location so near-duplicate images cannot leak into both development and evaluation.

Measure each task separately:

- **Object finding:** present-target localization, correct object instance, false-found count divided by absent-target cases, malformed replies and missing responses.
- **Voice actions:** requested versus executed action, clarification, stop, mute and rejected unsafe proposals. Mute should suppress audio while preserving listening and authorized tool execution.
- **Spoken responses:** usefulness, brevity, interruption behavior and delivery time. Human listening tests remain necessary.
- **Source-based answers:** retrieved evidence, supported claims, preserved conditions, source dates and appropriate abstention.

Fix the current photo report's false-found denominator before selecting a model. Add per-case timing, usage and resolved model identifiers. The evaluation and phone currently configure different request timeouts; implement a shared absolute usable-response deadline before comparing their latency.

Reject unacceptable behavior first. Then compare speed and measured cost among acceptable candidates. Keep timeout and error cases in the report, inspect disagreements, and include retries in cost. A completed cloud job does not establish model quality.

Chalk provides versioned [evaluations](https://docs.chalk.ai/docs/compute/evaluations) and [scorers](https://docs.chalk.ai/docs/evaluations/scorers). Use deterministic checks for actions and labels, with calibrated human review for subjective qualities. Its routing judge chooses a backend; shadow routing does not generate both candidate answers for comparison. [Model Gateway](https://docs.chalk.ai/docs/model-gateway).

## Real data

Use consented FEEL captures for localization and phone integration. Public [VizWiz-VQA](https://vizwiz.org/tasks-and-datasets/vqa/) examples can help evaluate answerability for images taken by blind people, but their question-answer labels do not supply FEEL bounding boxes or LiDAR truth. Preserve attribution and keep benchmark results separate.

For venue knowledge, begin with reviewed official sources such as [Harvard campus accessibility](https://accessibility.harvard.edu/campus-access). Store source URL, retrieval time, content version and effective dates where available. A temporary restriction must override a general schedule. Documented accessibility does not establish that a path is currently clear.

Chalk's [historical context queries](https://docs.chalk.ai/docs/compute/dynamic-chalk-queries) can support replaying what the agent knew at a past moment. FEEL still needs source verification and user/session isolation.

## Without internet

Chalk's [offline store](https://docs.chalk.ai/docs/offline-stores) stores historical data in cloud infrastructure. It does not run an assistant on a disconnected phone.

Use Chalk's [scheduled queries](https://docs.chalk.ai/docs/scheduled-query) to prepare approved venue data and its [cache controls](https://docs.chalk.ai/docs/query-caching) to manage server-side freshness. FEEL must implement downloading and reading a local copy.

A first local venue pack should contain searchable text, source references, version and expiry metadata. Replace it atomically after a successful update. Explain when time-sensitive information cannot be confirmed. On reconnection, refresh data without replaying old commands.

The offline assistant needs local spoken results as well as local command recognition. Some current Where-is announcements still use the cloud voice path. Apple's on-device speech recognition also depends on actual device/locale support and permissions. [Apple Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

## Acceptance checks

- Start without internet and explain available capabilities once.
- Lose connectivity mid-answer without leaving stale audio or pending actions active.
- Execute supported stop/mute commands locally and preserve mute through recovery.
- Reject expired information and unsupported object searches honestly.
- Reconnect after changing tasks without executing an old request.
- Verify actual speech assets, headphone routing, battery use and supervised device behavior.

## Implementation order

1. Correct evaluation reporting and add timing/usage evidence. **Implemented in software** on `feel/chalk-roadmap`: denominators per metric, per-row status/elapsed time/resolved model/usage, and one absolute 12 s deadline shared by the phone and the evaluation. Not yet exercised against real photos or a hosted run.
2. Complete local command and spoken-result behavior, then test loss of connectivity.
3. Resolve hosted evaluation execution and quota enforcement; run the approved comparison dataset.
4. Add reviewed venue packs and bounded agent context. **Venue pack implemented in software** on `feel/chalk-roadmap`: Python builder, hashed and validated format, expiry and restriction rules, atomic phone storage, HTTPS download, the `venue_info` voice tool and a VoiceOver list. Not yet done: reviewed real venue content, hosting, a Chalk scheduled query that prepares the source, agent context, and device tests.
5. Select models from held-out results and validate on the phone before rollout.

Added on `feel/chalk-track` (October 17, evening): a `--local` evaluation mode that runs the hosted task and scorers on a Mac through the gateway with the same report shape, a synthetic dataset generator, and a recorded 12-row local run ([evidence](evidence/chalk-synthetic/)). Chalk-built venue packs (`Venue.pack`) reuse the local builder, so both produce identical bytes.

## Detailed evidence

- [Production configuration and blockers](CHALK-PRODUCTION.md)
- [Product opportunities](CHALK-PRODUCT-OPPORTUNITIES.md)
- [Evaluation and model-selection research](CHALK-EVAL-RESEARCH.md)
- [Offline capability research](CHALK-OFFLINE-RESEARCH.md)

No new deployment, model call or dataset upload was performed to produce this consolidated document.

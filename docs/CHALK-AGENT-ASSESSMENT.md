# Chalk assessment for FEEL

Reviewed October 17, 2026 against V1/main at `82cd684`, official Chalk agent guidance, and authenticated read-only MCP queries. This assessment deploys nothing and changes no account configuration. Recommendations are proposed work, not completed features. V2–V4 remain separate.

## What the account actually contains

The configured MCP server responds successfully. This inspection used its HTTP interface with existing credentials; a native Chalk tool namespace was not available in this agent session. Every environment query explicitly selected Feel production, `flnyc749e8d9`, because `whoami` reported no default environment.

| Check | Observed result | Meaning |
|---|---|---|
| Environment listing | One accessible production environment | Do not assume a staging environment exists |
| Named datasets, limit 20 | `infrastructure-echo-smoke`, completed revision | Generic infrastructure data; not a FEEL photo benchmark |
| Functions, limit 20 | `infrastructure_echo` and `infrastructure_exact_match`, version 1 | Smoke functions registered; no FEEL task returned |
| Feature graph | No active deployment found | No active feature deployment is available to inspect |
| Existing evaluation operation lookup | Not found | Completion remains unverified |
| Query listing by existing evaluation run ID | Empty | Does not prove success, failure, cancellation or deletion |
| Official documentation search | Search and full-page reads succeeded | Agents can obtain current Chalk guidance through MCP |

The earlier gateway image smoke remains valid evidence of transport only. Gateway operation does not establish feature-store readiness. Quota enforcement remains blocked in the last recorded account checks; it was not retested here.

The current [evaluation overview](https://docs.chalk.ai/docs/compute/evaluations) explicitly requires support to enable Evaluations and the async Function queue, and says a new environment needs an active deployment. Confirm those prerequisites before another hosted run. The missing deployment is a verified prerequisite gap, **not a proven cause** of the earlier timeout. No new support message or evaluation was submitted.

## Five additions, in implementation order

### 1. A trustworthy evaluation baseline

**Benefit.** Select models based on FEEL errors and usable response time instead of generic demos.

**Already present.** V1 photo preflight, JSON validation, center-hit scoring and a false-found indicator in `chalk/feel_chalk/where_is_eval.py`. Two gateway candidates were previously tested for image transport. A real-photo comparison is not verified.

**Missing work.** Give cases stable IDs and capture-session provenance. Fix false-found rate to divide by absent-target cases, while separately reporting malformed and missing replies. Freeze independent test cases before tuning. Record resolved model, prompt version, per-case elapsed time, retries and usage. Center-hit alone does not establish correct instance selection or useful box overlap. Add deterministic voice-action cases and human listening reviews separately.

**Dependencies.** Consented labeled photos, reviewed metric thresholds, hosted execution prerequisites above, and working admission limits before load testing.

**Latency and cost.** Evaluation is outside the live phone path. Budget fresh inference by cases × candidates × repetitions, plus retries and any model-based scorers. No reliable dollar estimate exists without measured usage and verified prices. For completed runs, investigate rescoring saved outputs when only a scorer changes; do not mistake rescoring for fresh model comparison.

**Acceptance.** Absent, present, malformed, timeout and wrong-instance fixtures yield explicit counts and denominators. Identical frozen inputs reach both candidates. Every row is accounted for, including failures. A completed cloud run is not automatically a quality pass.

### 2. Model selection by task, with measured limits

**Benefit.** Spend inference time where it improves object finding, while keeping immediate voice controls responsive.

**Already present.** Gateway model restrictions and image transport. Voice audio uses OpenAI Realtime directly; it does not pass through Chalk. No FEEL model winner has been established.

**Missing work.** Start with explicit task-to-model configuration based on item 1. Add sanitized latency/error/usage telemetry and a shared absolute usable-response deadline. The phone's configured 12-second request timeout and Python gateway's 60-second timeout are not equivalent end-to-end deadlines. Bound retries and fallback within the remaining budget; do not retry valid “not found” just to obtain a positive answer.

**Dependencies.** Held-out evaluation results, resolved quota support request and server-side or individually revocable user provisioning.

**Latency and cost.** Measure p50/p95 including failures and retries. Additional routing or fallback calls add delay and spend. A shadow routing decision does not generate both answers and cannot replace comparison inference. [Gateway documentation](https://docs.chalk.ai/docs/model-gateway).

**Acceptance.** Cancellation or task changes discard late replies. Budget exhaustion fails clearly. Model changes pass the same benchmark. Stop and mute do not depend on gateway availability.

### 3. Small, authenticated context queries

**Benefit.** Give the assistant relevant preferences and recent cues so it can avoid repetition and explain uncertainty.

**Already present.** Phone session state and local tracking checks. The inspected Chalk environment has no active feature deployment.

**Missing work.** Define the smallest context contract: authenticated owner/session, permitted preference fields, task ID, observation time, expiry and source. Keep unknown values nullable. Use SQL or feature expressions for simple reads; use Python resolvers only for procedural transformations. Use query-time-aware timestamps for historical replay. Request metadata is not an authorization boundary. These choices follow Chalk's [online resolver skill](https://github.com/chalk-ai/agent-prompts/blob/c594e22572df8fdca6ab4d3f4ad6ef205b308e5e/skills/writing-online-resolvers/SKILL.md).

**Dependencies.** Active deployment, authenticated backend ownership, retention/deletion rules and isolated validation before production.

**Latency and cost.** Query on meaningful task changes, not on each camera frame. Cache only fields whose freshness permits it. Keep depth processing, haptic encoding and immediate controls on the phone.

**Acceptance.** Cross-user queries fail; expired or out-of-order observations cannot become current guidance. Historical replay uses only information available at the requested time. Missing context never becomes a fabricated safe direction.

### 4. Reviewed venue packs for offline use

**Benefit.** Read downloaded accessibility information when the phone loses internet.

**Already present.** Local sensing paths and limited target-word recognition. No verified downloadable venue pack or general offline voice assistant. Some Where-is speech still depends on the cloud.

**Missing work.** Ingest approved venue sources with attribution, revision and expiry. Prepare a compact pack through scheduled processing; implement download, atomic replacement and local lookup in iOS. Complete local command recognition and spoken results independently. Chalk's historical/offline store is cloud infrastructure, not an on-device runtime. [Offline stores](https://docs.chalk.ai/docs/offline-stores), [scheduled queries](https://docs.chalk.ai/docs/scheduled-query).

**Dependencies.** Reviewed source rights and accuracy, phone storage/version contract and actual speech/locale availability on the device.

**Latency and cost.** Refresh server data and packs at a justified cadence; downloaded reads need no live Chalk request. Measure pack size and refresh cost before expanding venues. No offline availability claim until tested on a disconnected phone.

**Acceptance.** Cold start in airplane mode reads the downloaded pack. Interrupted downloads preserve the last valid pack. Expired closures/schedules are identified as unconfirmed. Reconnection never executes old commands. Venue information never implies a currently obstacle-free route.

### 5. A consented regression loop

**Benefit.** Turn observed failures into repeatable tests without silently collecting a person's camera or voice history.

**Already present.** Chalk trace-content logging was disabled in the recorded configuration. V1 lacks a verified product feedback-to-evaluation pipeline. V4 feedback code is separate and is not evidence of a V1 feature.

**Missing work.** Collect minimal version, outcome, timing and error-category metadata. Capture images/audio only through a separate explicit consent flow with retention and deletion. Review eligible failures before adding them to a versioned evaluation dataset. Keep a frozen test set separate from newly collected development examples.

**Dependencies.** Ownership, consent and deletion contracts; usable evaluation execution; an assigned reviewer for subjective voice/accessibility results.

**Latency and cost.** Keep logging off the immediate control path, bounded and retry-safe. Storage and evaluation cost grow with retained cases; sample deliberately. Existing trace privacy settings do not govern provider retention or separately uploaded evaluation datasets.

**Acceptance.** Default events contain no photo, audio, transcript or credential. Deletion propagates to retained copies. A reviewed failure becomes a regression case without contaminating the frozen test set. Report failures before and after guards separately.

## Reusable instructions for the next agent

1. Read this assessment, `FEEL-CHALK-ROADMAP.md` and the relevant source before claiming a feature exists. Main is V1.
2. Use [Chalk's documentation index](https://docs.chalk.ai/llms.txt) and MCP `search_docs`; read full pages after searching. Consult the official [agent prompt](https://github.com/chalk-ai/agent-prompts/blob/c594e22572df8fdca6ab4d3f4ad6ef205b308e5e/BASE_CHALK_PROMPT.md) and only relevant skills. Reference revision is pinned here; check upstream before future implementation.
3. Inspect account state with an explicit environment ID. Do not infer a deployment or successful eval from registered functions. Never print credential headers or function environment variables.
4. Distinguish read-only inspection from deployment, uploads and model calls. Some SDK function wrappers deploy when constructed; sandbox tooling can provision resources. Do not execute examples merely to inspect them.
5. For implementation, start with local evaluation metric fixtures. Then resolve hosted prerequisites, use approved data and preserve evidence. Test resolver logic locally and integrate in isolation before production.
6. Keep local stop/mute, tracking validity and haptic commands independent of Chalk. Verify hardware and headphone behavior on the actual phone; cloud results cannot prove them.

## Evidence and next steps

Read-only inventory checks completed at approximately 21:17 UTC on October 17, 2026. The evaluation documentation and run-filter lookup were checked again during this assessment. Only the summarized inventory above is committed; raw responses and credentials are excluded.

Next engineering step: repair V1 evaluation reporting with deterministic local fixtures. Next hosted step: confirm deployment/async-queue/evaluation enablement and quota enforcement, then inspect the existing run rather than blindly resubmitting it. Next human input: a consented photo set and device listening feedback when those tests are ready.

No application code, cloud resource, model routing policy or production setting was changed by this assessment.

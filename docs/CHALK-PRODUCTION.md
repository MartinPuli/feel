# Chalk production setup — October 17, 2026

**Public production release: BLOCKED.** The Feel gateway routes requests, and its trace-content policy is now configured. Quota enforcement is disabled by the managed service. Venue accuracy, device provisioning and the separate V4 deployment are still unverified.

## Account configuration

| Gate | Status | Evidence |
|---|---|---|
| Team/environment | PASS | Feel / Default / production (`flnyc749e8d9`) |
| Provider and model restrictions | PASS | FEEL OpenAI; existing key still restricted to `openai/gpt-6-luna` and `openai/gpt-6.1-sol` |
| Trace content policy | PASS, saved and reloaded | Sampling enabled, default rate 1, default content logging false, conversation floor 0, no match/outcome overrides |
| Request/concurrency limits | BLOCKED | Creating the proposed 30 requests/minute, burst 5 policy failed because `ROUTER_QUOTA_BACKEND` is disabled |
| Support escalation | SENT with explicit user authorization | Chalk confirmed submission and email follow-up; [request text](evidence/chalk-production-20261017/SUPPORT-REQUEST.md) |
| Hosted dataset upload / function registration | PASS | Three generic rows uploaded; echo task and exact-match scorer registered |
| Hosted evaluation result | BLOCKED: completion unverified | Local 180-second wait timed out; remote run still RUNNING at 19:51:44 UTC, with no results or terminal error |
| Synthetic image transport | PASS, 2/2 | Generated solid-blue 64×64 JPEG accepted by both models; not venue accuracy |
| Real photo evaluation | NOT RUN | Consented labeled venue dataset still needed |
| Phone/hardware | NOT VERIFIED | Current configuration not provisioned or physically exercised in this task |

The policy preserves trace sampling while disabling default prompt/completion content in Chalk traces. It does not change provider retention policies, previously stored records or evaluation dataset storage.

## Controls requested from Chalk

Initial single-device pilot limits: 30 requests/minute with burst 5, and 2 concurrent requests, scoped to the existing app key. Neither policy is claimed active. The request policy could not be created, so the concurrency policy was not attempted against the same disabled backend. No key was replaced or broadened; no paid plan or external cloud account was purchased.

Do not put a token usage budget or tokens/minute rule on the camera key. Current [Chalk gateway documentation](https://docs.chalk.ai/docs/model-gateway) states those rules reject image/audio/video requests before dispatch. Use request/concurrency admission and an independently configured provider spending control for this workload. No provider spending cap was changed here.

## Infrastructure smoke

The isolated script uploaded only three generic `alpha`, `beta`, `gamma` rows and a standalone echo/scorer source. No repository code, camera images, place context or FEEL credentials were included in its function bundle. SDK-managed runtime identity is separate from FEEL provider secrets.

- Dataset: `c19e60f4-6da7-4767-988b-353624c0e229`
- Evaluation: `cmvcszzug03uq013eju3pcaw7`
- Run: `3ed17030-a278-41ab-9358-dfe93439d3d7`
- SQL execution: `ed6d858a-26ba-4646-baca-43ebabfbb8e2`
- Function replicas: configured minimum 0, maximum 1 per function.

The local timeout report retains its original evidence. Its `execution_status: failed` describes the local check catching `TimeoutError`; subsequent remote status must be read separately. Do not interpret this as terminal remote failure or as a model-quality evaluation. Do not submit another run merely to poll this one.

## Synthetic image transport

Exactly two generic image requests were sent after the privacy policy was saved. A freshly generated 64×64 solid-blue JPEG was paired with a one-color question and a 64-token output cap. Both selected models returned `Blue` (1.799 s and 1.943 s). This confirms image transport with the existing key; it does not evaluate object localization or camera/depth integration. [Results](evidence/chalk-production-20261017/vision-smoke.json).

## Application gates outside account setup

V1 keeps a scoped router key in the phone Keychain. Public distribution must not embed or share one spending key across users; use individually revocable provisioning or an authenticated backend. Venue photo accuracy and phone-side depth/tracking/cancellation checks must pass before release claims.

The V4 text service remains a separate single-user demo deployment. Public multiuser use needs authenticated ownership of every session, bounded HTTPS ingress/concurrency, a production server, persistent private storage, atomic request deduplication and sanitized failure telemetry. Its current shared token must not be treated as tenant isolation. V4 was not merged into V1 during account setup.

## Next actions

1. Resolve the quota-backend support request, apply the proposed RPM/concurrency limits, and verify actual admission/rejection behavior.
2. Provide and approve a consented labeled venue dataset, then run the two-model evaluation and inspect all failures.
3. Connect the unlocked iPhone for provisioning and supervised live tests; deploy and validate V4 separately if it is part of the release.

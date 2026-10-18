# FEEL / Chalk integration validation

Checked October 17, 2026 local time (October 18 UTC), environment `flnyc749e8d9`.
Read-only cloud inspection and existing synthetic context queries. No new deployment,
model inference, dataset upload, device recording or third-party message was performed.

## What actually passed

| Boundary | Current evidence | Result and limit |
|---|---|---|
| Native Chalk MCP identity and graph | Authenticated; 110 feature definitions returned | PASS for discovery. An active context graph exists; earlier reports saying there was no deployment are historical. |
| Direct FEEL context client → Chalk engine | Five existing synthetic queries and 12 assertions in `direct-validation-20261018.json` | PASS: keys have two finds, missing laptop abstains, venue pack has four entries and matching hash, room has two targets/three visits/three journeys, path has two progress points. This is seeded-data behavior, not a real user's location or a safe route. |
| Native MCP → context engine | Identical environment and synthetic keys; `mcp-validation-20261018.json` | FAIL for parity: keys/room incorrectly appear empty, path says `no target`, venue pack reports a future retrieval timestamp. A repeated keys lookup also returned zero. |
| Local context/gateway/evaluation code | `/tmp/feel-chalk-context-sdk/bin/python -m unittest discover -s chalk/tests -v` | PASS: 135 tests, zero skipped. Includes the ten resolver tests previously skipped without chalkpy. Network transports are mocked in this suite. |
| Integrated intent/feedback backend | `/tmp/feel-chalk-eval-inspect/bin/python -m unittest discover -s services/chalk -v` | PASS: 36 tests, including real loopback HTTP authentication. No live Chalk inference. |
| Model Gateway | Local request/parser/error tests; previous live evidence is separate | NOT RUN live in this check. Context-query success does not prove model routing, vision accuracy or voice latency. |
| Hosted Chalk Evaluations | Two generic functions, one named smoke dataset; old run-ID lookup empty | NOT VERIFIED. No completed FEEL hosted score was found by this inspection. An empty query listing does not prove failure or explain the earlier timeout. |
| Native phone offline behavior | Local grammar, local spatial memory, downloaded packs are separate from Chalk | NOT TESTED on a phone in this check. Chalk's offline queries are cloud historical processing, not disconnected phone execution. |

The isolated SDK environment used `chalkpy[postgresql] 2.163.1`, `chalkcompute 2.13.7`,
`pyarrow 26.0.0` and `Pillow 12.2.0`, all pinned by the repository. Expected
failure-path tests print example “incomplete” evaluation messages; the unittest
result is 135 passed, not a claim of a successful live evaluation.

## Reproducible MCP discrepancy

Both paths explicitly used environment `flnyc749e8d9` and the existing configured
credential. Example input is `object_history.id =
00000000-0000-0000-0000-000000000001:keys`.

- Native `run_online_query`: `finds_count=0`, `last_place=null`.
- `feel_chalk.context.query`: `finds_count=2`, `last_place="kitchen table"`.
- Native venue query: `VenuePackError: entry accessible-campus-map: retrieved_at is after the pack was built`.
- Direct venue query: four entries retrieved at `2026-10-17T20:00:00Z`, a later
  generated timestamp, and a valid payload SHA-256.

A fresh direct probe at `2026-10-18T02:47:20.052877Z` returned query ID
`cmvd860af01lh0g3ufsorg04j` from deployment `cmvd45tlw09ul013elnsmpc1o`.
The matching MCP call completed at `2026-10-18T02:47:39.877Z` and again returned
zero finds; it exposed no query/operation ID, deployment ID or query timestamp.
See `direct-query-provenance-20261018.json` and
`mcp-query-repeat-20261018.json` for exact inputs, outputs and returned metadata.

The direct client follows the engine host in the OAuth grant and sends
`X-Chalk-Deployment-Type: engine` (`chalk/feel_chalk/context.py:68–79`). The MCP
result does not expose its effective query time, deployment ID or operation ID.
A time, engine or deployment mismatch is a hypothesis, **not an established root
cause**. The direct checks prove the synthetic records exist; do not reseed the
database or weaken timestamp validation to hide the discrepancy.

Metadata lookup confirms direct-query deployment `cmvd45tlw09ul013elnsmpc1o`
succeeded at `2026-10-18T00:58:55.151Z`; its source hash is
`e63f364d1ebc1d4065a016c1f8d0b3556cb91dcfa702d5424890058d396652e4`.
The older first deployment `cmvcxuyh706o1014wlikl4fyj` also has a successful record.
Neither metadata lookup establishes which deployment MCP reached.

## Separate local bug fixed, not deployed

`chalk/feel_chalk/venue_pack.py:84` rounded the build clock down to whole seconds
before comparing entry retrieval timestamps. A legitimate `.400000` retrieval
followed by a `.600000` build was rejected as future data.

The patch compares the original timezone-aware instants and retains existing
whole-second wire formatting. A truly future `.800000` retrieval still fails;
a naive build timestamp is now rejected. Two regression tests failed before the
patch and pass afterwards. The shared golden pack/hash remains unchanged. This
subsecond bug does **not** explain the observed MCP-versus-direct discrepancy.
No resolver deployment was changed. The live engine still runs its previously
deployed source, not this local timestamp patch.

## Product integration gaps

1. **Phone upload versus download:** remote `main` commit `88c3900` now wires
   confirmed finds, anchors, room maps and journeys into a signed-in Supabase
   writer (`ios/Lantern/Services/SupabaseWriter.swift:131–145`). The earlier
   “all upload functions are empty” assessment is obsolete. However,
   `RoomMemory.fetchSharedStructure` remains empty at that revision (line 105).
   Upload wiring is not proof of a phone → database → Chalk → phone round trip.
2. **Authenticated context reads:** the CLI accepts an arbitrary user ID
   (`chalk/feel_chalk/context.py:98–100`) under a service credential. Keep that
   credential off the phone. A production API must derive user scope from the
   authenticated session before exposing private last-seen context.
3. **Sharing choices:** at `88c3900`, `SupabaseWriter` documents shared room
   uploads by default (`:105–107`). The integrating owner was alerted to require
   an explicit opt-in and verify the resulting behavior in its own gate. This
   report does not claim that default has already been repaired.
4. **Public intent service:** `services/chalk/server.py:248–251` is still a
   loopback development HTTP server. Its isolated credentials and concurrency
   checks do not replace production HTTPS ingress, identity provisioning,
   distributed deduplication or deployment validation.
5. **Evaluations and release decisions:** named inventory contains only
   `infrastructure_echo`, `infrastructure_exact_match` and
   `infrastructure-echo-smoke`. No candidate model is promoted by these tests.
   Retain raw decision failures, guard interventions, latency and consented
   correction outcomes when evaluating the real product.

Useful assistant context is the user's own last confirmed find, the age and source
of venue facts, and shared room information only with permission. Keep current
tracking, Stop, obstacle processing and tactile output local. Revalidate context
before applying any cloud-selected action. Past sightings must never be spoken
as confirmed present locations.

## Feedback draft for Chalk — not sent

We tested FEEL's deployed context features using the same synthetic inputs through
MCP and our direct engine client. The direct client returned two confirmed finds
for “keys” and a valid venue pack. MCP returned no finds and rejected the pack
because its retrieval time appeared to be in the future. We reproduced the keys
difference twice, but cannot see the effective query time or deployment in the
MCP response.

Could online-query responses include the environment, deployment, effective time
and operation ID, with a conformance check against the SDK? That would help us
distinguish an empty dataset from a routing or time mismatch. Similarly, a hosted
evaluation readiness check and an inspectable terminal status would make it much
easier to understand stalled or missing runs. Graph discovery and documentation
search through MCP were useful throughout this investigation.

## Next checks

1. Resolve or explain native MCP/direct-engine parity using the attached
   synthetic inputs; preserve the time guards.
2. Validate the merged phone's upload consent, authenticated context download,
   and an end-to-end round trip with the connected iPhone.
3. Complete a hosted evaluation run with row-level results before comparing
   models or claiming production evaluation readiness.

Official time semantics consulted through MCP:
[Chalk time](https://docs.chalk.ai/docs/time),
[temporal consistency](https://docs.chalk.ai/docs/temporal-consistency).

## Integration follow-up

The integrated phone code now addresses the `88c3900` upload review: upload and public-sharing consent default off, missing venue skips spatial records, and token refresh/retry is bound to the originating login and consent generation. Eight regression tests were added; the merged app suite passed 268 native tests and 12 UI tests. Physical upload round-trip validation remains pending.

A bounded live intent evaluation is now recorded in [INTENT-EVALUATION.md](INTENT-EVALUATION.md): it does not convert the local or context checks above into a hosted evaluation result. The production model route was unchanged.

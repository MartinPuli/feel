# Independent review — greenfield V1

Reviewed October 16, 2026 by an agent with read-only ownership, separate from the
Swift, firmware and CAD authors. The lead engineer integrated cross-layer fixes.
The earlier reference-model review is preserved in
`REVIEW-PREPARATION-HISTORICAL.md`; it does not review this production source.

| Finding | Resolution / verification |
|---|---|
| Old BLE callbacks and same-peripheral reconnect could restore stale state | Callback identity and serialized disconnect/reconnect; source re-reviewed |
| Cached camera-relative target survived phone rotation | Cache world position and reproject against each current camera pose; portable rotation tests |
| Queued AR/Vision results survived session/finder changes | Session and finder generations reject outdated results |
| NI target removal/suspension/reconnect could retain old guidance or inhibit new ranging | Clear world target, validate active token/session, replace token on restart and clear old suspension latch; source review |
| PWM failure could leave a previous channel active | Detach all outputs on failure; preflight every channel before updates; host tests and enabled-path compilation |
| JSON decoding could bypass packet invariants | Validated custom decoding; malformed JSON packet regression cases |
| Integration replay compared an acceptance counter with a Boolean | Assert command result explicitly; invalid cases assert the precise rejection reason |
| Replays shared neutral-gap state after reset and buffered Swift stdout | Explicit controller RESET; immediate line-oriented stdout |
| CAD checked the wrong band-3 tap angle | Actual firmware angles 21/37/138/154; 78 geometric assertions |
| Dependency caches could masquerade as project source | Ignore build/cache directories in source checks; regression test |
| Model download and CAD tool regressions absent from full runner | Both are mandatory available checks |
| Concurrent CAD renders shared temporary files and invalidated hashes | Output-directory lock, unique temporaries, isolated fast builds, competing-writer regression; final sequential export |

The reviewer independently executed the 38 production firmware cases and 17 CLI
commands. Final source review found no remaining critical/high defect in the
reviewed paths and no obvious Apple API/deployment mismatch. This is bounded
review, not a guarantee that all defects are absent. Actual Apple framework
compilation and simulator/device execution are still blocked by the missing Mac
platform; parser/source review is not a substitute.

The lead engineer also exercised the production replay and actual-STL viewers in
headless Chromium, including controls and mobile width, and visually inspected
screenshots. The final consolidated executed results are in `TEST-REPORT.md` and
`evidence/v1/`. All servo, electrical, BLE-radio, sensing and tactile validation
remains physical work.

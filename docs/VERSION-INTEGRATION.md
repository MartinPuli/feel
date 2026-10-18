# Useful V2–V4 features in main

The user requested useful V2, V3 and V4 functions in main. This supersedes the earlier branch-isolation instruction. Historical branches are preserved. The integration started from main `5b82895` and includes the newer `88c3900` phone-upload changes. Shared application files were adapted instead of replaced with older branch versions.

## Integrated behavior

| Origin | Function | Availability in the integrated app |
|---|---|---|
| V2 | Session bookmarks: remember, list, rename, delete, recall, return point and stop | Assistant → Saved places, and realtime voice tools. Requires fresh pose in the same session. |
| V2 | Remember → move → recall simulation | Assistant → Simulate saved places; voice tools can start, move, turn and lose/recover tracking. Synthetic packets never drive BLE movement. |
| V3 | Save and restore ARWorldMap with bookmarks | Assistant → Saved room, and voice tools. Protected local storage; matching map marker, actual relocalization and fresh settled poses are required. Loading a map never starts recall. |
| V3 | Finite English/Spanish local voice commands | Assistant → Commands without internet. Explicit local capture pauses online voice; typed commands also work. A downloaded on-device recognizer is required for microphone use. |
| V3 | Barcode finder | Finder selector and `find_target` voice tool. Payload is sanitized display text; it is never executed. |
| V3 | Standard/reduced/automatic tactile highlights | Local commands panel and voice tool. Changes highlight cadence; obstacle bands and reserved wire slot remain unchanged. |
| V4 | Guarded cloud intent service | Assistant → Chalk commands. Optional HTTPS service root and app credential required; sharing and retention are separate choices. Not preconfigured as a public production service. |
| V4 | Correct/incorrect feedback, correction, deletion and eval tooling | Chalk commands panel and `services/chalk`. Session/principal isolation, immutable snapshots and raw/post-guard scoring. Corrections never execute an action. |
| New main | Phone finds, room anchors/maps and journeys to Supabase | Assistant → Cloud memory, or explicit-consent voice tools. Uploads and sharing default off. Requires signed-in session and selected venue; no invented fallback venue. |
| New main | Local journey export | Cloud memory → Export journeys to Files, or `export_journeys`. No upload. |

Existing camera-first UI, OpenAI realtime voice, room-tag memory, local journeys, venue packs, authentication, photo-request deadline/cancellation and six-active-column wire format remain in place. Public sharing and cloud interpretation are optional and do not enable themselves.

## Review fixes

- Cancelled map saves cannot overwrite the previous saved room after background serialization.
- Saved-room restoration blocks pointing/hand-sign guidance and teammate discovery bypasses.
- Local microphone ownership includes authorization and final-result processing; later typed commands supersede earlier pending transcripts.
- Recall preserves live obstacle bands and supplies obstacle observations to the existing voice policy without changing its preferences.
- New-main uploads require consent. Consent withdrawal stops pending work; delayed token refresh cannot restore a signed-out account or overwrite a different login. Concurrent expired uploads share one refresh.
- A real selected venue replaces the previous fabricated demo fallback.
- Venue-pack freshness compares exact timestamps before wire formatting; genuine future retrievals remain invalid.

## Chalk evidence and context

[Validation report](evidence/chalk-context/INTEGRATION-VALIDATION.md) records five direct-engine synthetic context cases, twelve assertions, 135 Python tests with the pinned SDK and 36 intent-service tests. MCP and direct queries returned different results for the same seeded inputs; the discrepancy is reproduced with query/deployment provenance and is not attributed to a guessed cause.

[FEEL integration notebook](https://chalk.ai/projects/cmvcr1tjd02rv013ec55n2w6f/environments/flnyc749e8d9/notebooks/cmvd80k640bwm013e8kk1epp0) contains product context, evaluation criteria and sanitized feedback. It is documentation, not an automatically injected model prompt. No message to Chalk staff was sent for this validation.

## Remaining product gaps

These are explicit limits, not implemented features:

- `RoomMemory.fetchSharedStructure` is still a placeholder. None of the older V2/V3/V4 branches contains an implementation to port. Reading private context on the phone requires an authenticated server endpoint that derives user scope; service credentials must stay off the phone.
- The intent service is a loopback development server. Production HTTPS ingress, per-user credential provisioning and distributed deployment checks remain necessary before enabling it broadly.
- Hosted FEEL evaluation completion is not verified. Local tests and direct context queries do not prove hosted evaluation or live vision accuracy.
- The timestamp fix is local source; the existing Chalk engine deployment was not replaced in this work.
- Real headphones/microphone, LiDAR, cross-session relocalization, BLE, Nearby Interaction and tactile usability need physical validation. Simulator results do not prove those behaviors.

## Reproduction

```sh
cd ios/Shared/FeelCore
swift test --scratch-path /private/tmp/feel-integration-full-core
cd ../..
xcodegen generate
xcodebuild -project Lantern.xcodeproj -scheme Lantern \
  -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' \
  -derivedDataPath /private/tmp/feel-version-integration-build \
  -only-testing:LanternTests -only-testing:LanternUITests CODE_SIGNING_ALLOWED=NO test
cd ..
sh firmware/test/run_host_tests.sh
python3 simulation/run.py --repeat 3 --no-web
/tmp/feel-chalk-context-sdk/bin/python -m unittest discover -s chalk/tests -v
/tmp/feel-chalk-eval-inspect/bin/python -m unittest discover -s services/chalk -v
```

Use an installed simulator rather than assuming that identifier exists on another Mac. Release and test reports record final observed results. No device installation is claimed by this integration document.

## Additional branch findings

`replay-pin-diagnostics` (`6d41c62`) adds useful six-column diagnostics and a replay viewer; its additive diagnostics are integrated with strict reserved-slot checks and preserved historical baselines. See [six-column validation](../simulation/SIX-COLUMN-VALIDATION.md).

`ethan/cad` unique commit `48774f0` remains separate. It mixes perception changes, seven-sector geometry labels, new scenes and snapshot comparison. Its snapshot viewer also needs request-generation and recording-identity checks. Importing it wholesale would replace tested six-column behavior. These features are not described as active in main.

The older V2/V3/V4 branch refs remain preserved. V4-Ben's earlier features were already present in main. The live intent evaluation is [recorded separately](evidence/chalk-context/INTENT-EVALUATION.md); strict contract and latency targets are not reported as passing.

`claude/strange-swartz-7b6d9b` (`1a8945b`) appeared during the final fetch. It adds phone context reads, but currently embeds a Chalk client-credentials bearer in the app build and accepts feature/user identifiers on the client. Short expiry does not make that bearer user-scoped. It is not merged into this release: the authenticated server-boundary prerequisite above still applies. Its existence is recorded rather than reporting those reads as active.

## October 18 — Ethan dot-tracking integration

`origin/ethan/cad` at `765027e` was already merged into remote main by `9fe722a`.
Local main was fast-forwarded from `c71fc01` to `8b0789c`; recovery ref
`codex/before-ethan-dot-sync-20261018` preserves the previous local tip.
Historical branches and pre-existing untracked files were retained.

The merge adds the turning-triggered `PathWave` dot, stable depth sectors,
brief offscreen target retention, replay comparisons and CAD refinements.
The merge's adaptation keeps the wave in slots 1–6, reserves b0, disables GPIO32,
and leaves the existing servo angle and pulse settings unchanged.

Review found that the subsequent `d92cdac` held-drop feature could restore stale
pins after a tracking-loss neutral command followed by packet loss. The focused
controller fix and regressions from `a1f4313` were applied without importing that
branch's unrelated work: neutral remains neutral until a fresh packet raises it.
The new regression failed before the correction (43/44 controller tests).
Phone-timed taps and the path wave remain available; a lost restoring packet can
extend a neutral interval. No firmware was flashed. See the latest release entry
for commands, results and physical-validation limits.

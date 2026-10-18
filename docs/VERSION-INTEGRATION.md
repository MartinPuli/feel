# Version feature integration

The user explicitly requested the useful V2, V3 and V4 functions in main. This supersedes the earlier instruction to keep those features out of V1. The historical branches remain preserved. Integration starts from main `5b82895`; shared application files are adapted rather than replaced with older versions.

## Acceptance scope

- [ ] Session bookmarks: remember, list, rename, delete, recall, return point; reachable from voice and accessible controls; fresh pose/session enforcement.
- [ ] Deterministic memory simulation: remember, move, recall and tracking-loss recovery, without BLE output.
- [ ] Saved ARWorldMap: capture, protected local storage, restore/relocalization gate, delete; never activate guidance merely by loading coordinates.
- [ ] Local finite voice commands and typed fallback: EN/ES, stop/mute/unmute, single microphone owner, cancellation/background handling and local speech.
- [ ] Generic barcode finder, display-only sanitized payload, current camera-to-depth path and tests.
- [ ] Standard/reduced/automatic tactile highlighting while preserving obstacle bands and the six-column ABI.
- [ ] V4 command service, authenticated session ownership, bounded requests, guarded interpretation and explicit phone configuration/consent.
- [ ] V4 feedback, corrections/deletion, evaluation tooling and raw/post-guard reporting.
- [ ] Connect remaining useful shared-memory/journey/context paths, or provide explicit evidence explaining any unresolved external dependency; do not count empty functions as implemented.
- [ ] Preserve current room-tag memory, journeys, venue packs, authentication, camera-first UI, voice controls, deadlines and cancellation.
- [ ] Local builds, portable/native tests, independent review and regression checks; record physical validation separately.
- [ ] Publish the validated integrated work to main and verify remote contents.

No completion is claimed by this checklist. Existing consent and deployment settings remain separate from adding implementation. Real microphone, headphones, LiDAR, relocalization, BLE and tactile behavior require device verification.

## Working state

Integration branch: `codex/integrate-version-features`, worktree `/private/tmp/feel-version-validation-main`.
Source ports and application wiring are in progress. Current reports under `/private/tmp/feel-version-integration-*` are development logs until a reviewed milestone records exact results.

# Independent V3 review

A separate read-only reviewer inspected production voice, persistence, cadence,
native AR/coordinator lifecycle, local storage and the advanced replay. The
author applied fixes; root independently exercised the compiled production paths.

Resolved findings:

- Correct audio-session category/options for on-device recording.
- Bound native transcripts by Unicode scalars, including combining marks, to
  match the parser; do not accept an apparently short but unbounded string.
- Reset the 0.5-second relocalization settling interval after an observation gap
  over 250 ms. Root reproduced the old early-ready result in the production CLI;
  the direct test and cross-layer regression now cover that exact case.
- Invalidate a pending save and clear its busy flag when an AR interruption
  changes the world session, so a stale completion cannot strand Save/Load.
- Disable NI teammate finding in restored-map sessions because camera assistance
  requires a compatible AR configuration without an initial world map.

Verified in review: snapshot/map coordinate binding, strict bounded envelopes,
secure ARWorldMap marker validation, serial atomic protected local writes,
backup exclusion, no automatic map load or recall, timeout without new frames,
background/Stop generation guards, adaptive band/sequence preservation and the
simulation return paths before BLE transmission. QR/OCR labels never reach the
command parser.

No unresolved critical/high finding remains in this reviewed scope. The reviewer
did not run V3 builds or tests; actual execution belongs to TEST-REPORT.md and its
evidence. Review and simulation do not validate a real microphone, AR world,
camera, BLE/UWB radio, servo, mechanism or tactile experience.

The same independent reviewer inspected the later simulator-only barcode CPU
policy. It uses a public, deprecated VNRequest property, leaves device request
construction unchanged, and preserves the actual Vision payload, confidence and
bounding-box assertions. No concrete API or test-integrity defect was identified;
the review itself does not establish that the native rerun passes.

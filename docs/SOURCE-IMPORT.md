> HISTORICAL PREPARATION DOCUMENT. Original source recovery is no longer required. The user authorized the greenfield V1 recreation; see BUILD-HANDOFF.md.

# Restore the real V2 project before engineering sign-off

The target repository was empty at the start of this session. The attached handoff says **55 changed/new paths were uncommitted** on October 15. The original folder is essential. A ZIP of `git archive HEAD` alone would omit those changes.

## Fastest path

Ask the person holding the working project for the complete source folder or its actual repository URL. Include the working, uncommitted files and retain Git history separately if possible. Upload the archive into this conversation; the agent can inspect and integrate it without asking the team to resolve Git conflicts manually.

Required areas:

- `HANDOFF-v6.md`, `docs/BUILD-HANDOFF.md`, `docs/PROTOCOL.md`, original README files and research.
- `cad/` including parameters, build scripts, geometry and mesh-check tools; existing printable `stl/` if available.
- `firmware/` including source, host tests, build configuration and library versions.
- `ios/` including Lantern, Beacon, Shared, tests, XcodeGen configuration, model resources and their licenses/provenance.
- Any repository-specific skills/instructions, dependency lock files, and relevant original build logs.

Exclude secrets, provisioning profiles, private signing keys, personal sensor recordings, dependency caches and derived build output. Do not exclude model resources merely because they are binary: the detector may depend on them. Identify anything too large to upload, with its source and checksum.

## Preserve both histories

On the original machine, first inspect `git status --short` and `git log -5 --oneline`. Save a backup outside the project before changing it. Do not reset, clean, discard untracked files, force-push, or rewrite timestamps to disguise pre-event work.

The preparation repository now has its own bootstrap commit and `feel/v2-preparation` branch. Import the original project into a separate integration branch and compare overlapping files. Keep the original history as a branch or bundle; do not overwrite it with this preparation history. The easiest safe handoff is an archive plus the original Git repository/bundle where available.

## Resume checklist for the engineer

1. Read every newly supplied instruction and all missing required docs. Inventory dependencies and models. Save the source commit and working-tree diff as the baseline; identify pre-event files.
2. Run `python3 scripts/check_sources.py`. This checks presence, not implementation quality. Adjust filename assumptions only to match the actual original tree, with a documented reason.
3. Run `python3 scripts/run_v2_checks.py --output .artifacts/v2-checks`. It runs available checks and records missing ones as **BLOCKED**, exiting 2. A failing command exits 1. No flash/signing commands are invoked.
4. On a compatible Mac, inspect `xcodebuild -list` and installed destinations. `scripts/check_ios.sh` uses a real available simulator, never a fabricated device name. Confirm the actual scheme names against the imported project before running. Linux cannot execute Xcode, ARKit or the original iOS tests.
5. Replace the reference model's provisional policies with comparisons against production. Add `validation/adapters/run_contract_tests.sh` which executes the **actual Swift encoder and C++ firmware decoder** on `validation/fixtures/protocol_vectors.json`; do not copy the Python model into a second pseudo-production adapter.
6. Add and run the actual ESP32 and ESP32-S3 builds from the imported configuration. Resolve exact library/Xcode versions from existing pins before installing/upgrading tools. CI currently has host/CAD and macOS hooks, but does not pretend a PlatformIO board build ran.
7. Review invalid/stale input, BLE reconnect and backpressure, sequence handling, timers, calibration persistence, AR transforms, CoreML output, target lifetime and VoiceOver. Run the existing tests **before** changes, then add regression tests for real defects.
8. Only after relevant builds, original and new tests, the production-backed simulator, contract checks and independent review pass may V2 be called software ready. Create V3 from that exact reviewed commit on a separate branch; preserve V2.

## Documents preserved without changes

`AGENTS.md` is the supplied engineering instruction file. `HANDOFF-v7.md` is the supplied `HANDOFF-v7 (1).md`. `HACKHARVARD-2026.md` is the supplied **updated** event document, normalized to the requested canonical filename. Original content hashes are in `docs/evidence/baseline.json`.

None of the quoted historical test counts have been reproduced here. No private viewer link or other unprovided repository was treated as executable source.

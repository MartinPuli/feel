# Public app publication — October 31, 2026

The founder selected public publication of the iPhone app and private retention
of the new hardware designs. This commit imports only the `ios/` tree from local
snapshot `f749f07`, plus this publication record. It does not import that
snapshot's commit ancestry, hardware studies, concept images or budget files.
The full snapshot is retained locally on `codex/private-device-20261031` for
private archival in `MartinPuli/feel2`.

## App changes

- Accessible task controls and compact camera home with nonvisual equivalents.
- Shared typography and spacing, preserving Dynamic Type and control targets.
- Bounded spatial mesh inspection and explicit diagnostic simulation states.
- Updated app, core and UI tests.

## Verification

Before splitting publication destinations, the full snapshot passed:

- `sh ios/scripts/test_portable.sh`: 411 tests, zero failures.
- `sh firmware/test/run_host_tests.sh`: exit 0; 44 controller tests passed,
  with additional CLI and contract checks.
- `sh firmware/bench-travel/test/run_host_tests.sh`: PASS; this separate bench
  project is not included in the public app update.

The public app tree is identical to the tested snapshot's `ios/` tree.
No fresh full iOS simulator suite, signing, installation, board flashing or
physical tactile validation was performed for this publication. Existing
production hardware configuration is unchanged. Earlier reports retain their
original dates and scope; passing software tests does not prove mobility safety.

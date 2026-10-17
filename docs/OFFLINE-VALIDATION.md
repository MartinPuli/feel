# Offline integration validation — 2026-10-17

Scope: V4 local-first command understanding and connectivity-failure behavior.
The published V2/V3 branches and V1 main are not targets of this change.

| Check | Result |
| --- | --- |
| `swift test --package-path ios/Shared/FeelCore` | PASS: 90 tests |
| `bash firmware/test/run_host_tests.sh` | PASS: 41 controller tests plus CLI, board/configuration, adapter, single-servo and production guard suites |
| `python3 scripts/check_chalk_boundary.py` | PASS: 67 protected files unchanged |
| Native LanternTests | PASS: 45 tests; final parser suite also PASS: 4 tests |
| Changed-scope credential-pattern scan | PASS: no matching private key / common token patterns; not a comprehensive secret audit |
| Independent source review | Wrong remembered-name precedence and inconsistent punctuation fixed; empty-name paraphrase edge also addressed |
| CodeRabbit | BLOCKED: no trusted CLI executable found on PATH or checked standard installation locations. No CodeRabbit review was run |
| Final unsigned iPhone build | PASS; no installation/signing/flash |
| Real iPhone, BLE and servo test | NOT RUN for this update |
| Real Chalk requests and hosted evaluations | NOT RUN; account/service configuration still required |

An initial native test exposed local recall selecting a destination while tracking
was unavailable (physical packet remained neutral). The new command path rejects
memory actions before selection unless a fresh valid pose exists; the regression
assertion remains in the suite. Tests were rerun successfully after that fix.

Review also corrected `remember this place as Entrance` saving the entire suffix
as the name. Exact and polite versions now save `Entrance`, with regression cases.
The new parser emits existing intents only. No model weights, network dependency,
firmware uploads, GPIO changes, pulse changes or physical calibration changes are
part of this update. Existing V2 memory / V3 lifecycle tests execute in the V4 app.

The feature is a finite grammar, not a local LLM. A future model milestone and a
physical offline test procedure are in [Offline commands](OFFLINE-COMMANDS.md).
No test result here establishes perfect code or verified physical navigation.

Test result summaries: [core](evidence/v4-offline/core-tests.txt),
[native app](evidence/v4-offline/native-tests.txt),
[final parser](evidence/v4-offline/parser-tests.txt). Full local logs remain in
`.artifacts/ios/offline-*.log` and `/tmp/feel-offline-core.log`.

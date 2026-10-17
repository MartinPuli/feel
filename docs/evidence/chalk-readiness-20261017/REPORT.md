# Chalk readiness audit — October 17, 2026

## Scope

Fetched origin and pulled V1 main in an isolated checkout. Main was already current at `4f3f8e5`. Work is isolated from the original checkout's in-progress firmware changes. V2–V4 were not merged into V1.

## Remote evidence

Read-only checks repeated around 19:34 UTC using the installed Chalk CLI in the selected Feel production environment:

| Command | Result |
|---|---|
| `~/.chalk/bin/chalk router doctor` | PASS: all router checks passed (2 checks) |
| `~/.chalk/bin/chalk dataset list --json` | Empty object; no dataset listed |
| `~/.chalk/bin/chalk eval list --json` | `evaluations: null`, `score_summaries: null` |

`routing-smoke.json` preserves the earlier two authorized generic text results at 19:20 UTC. It is historical evidence, not a new run. No photos, repository context or new inference requests were sent during this audit.

At 19:37 UTC, the corrected `check_connection.main()` ran with `/tmp/feel-chalk-eval-inspect/bin/python`, loading the existing ignored configuration without printing it. All five diagnostics passed: reachable gateway, key lists two models, configured model listed, SDK installed and CLI logged in. No `--chat` flag was used, so no inference was sent.

## Corrections

- Connection diagnostics only generate tokens with explicit `--chat`, including when the configured model is absent from the listing.
- Python and Swift share 23 parser fixtures, including null optional fields and malformed absent-target boxes.
- Stale claims of universal Chalk routing and proven evaluation quality were removed. Current configuration is distinguished from historical simulator results.
- Architecture, data paths, evaluation metrics and remaining integration steps are documented in `docs/CHALK-IMPLEMENTATION.md`.

## Limits

Hosted evaluations, current-key photo accuracy, phone provisioning and physical hardware remain unverified. A dataset listing is not proof of functioning evaluation workers. Existing V4 command-service code remains separate and undeployed in this audit. Local tests cannot establish model accuracy or physical performance.

## Local validation of the changes

| Check | Result |
|---|---|
| `/tmp/feel-chalk-eval-inspect/bin/python -m unittest discover -s chalk/tests -v` | PASS, 34 tests |
| `/tmp/feel-chalk-eval-inspect/bin/python -m unittest discover -s chalk/tests -p test_eval_runner.py -v` | PASS, 11 runner tests independently |
| `xcrun xctest -XCTest FeelCoreTests.WhereIsTests ios/Shared/FeelCore/.build/debug/FeelCorePackageTests.xctest` | PASS, 3 tests against 23 shared cases, using the existing compiled test bundle |
| Actual `python -m feel_chalk.where_is_eval` with `--preflight` and a locally generated synthetic image | PASS; execution NOT_RUN, quality NOT_ASSESSED, cloud SDK not imported |
| `git diff --check` | PASS |

Pinned SDK inspection used Python 3.13.14, chalkcompute 2.13.7, pyarrow 26.0.0 and Pillow 12.2.0 in a temporary virtual environment. It verified function deployment arguments, dataset references, wait options and result fields without deploying anything.

The runner now validates/decode-checks every image before SDK use, records input and prompt hashes, propagates the selected host/model, refuses to overwrite report/source files, and persists run identities and sanitized row scores. Failed, timed-out or incomplete executions return nonzero. Quality remains explicitly NOT_ASSESSED after a complete execution until its results are reviewed.

An independent read-only agent review checked the connection diagnostics, documentation, evaluation data validation, result checks and actual SDK compatibility. No blocking findings remained. Python fake-SDK tests exercise orchestration failures; they do not prove a real deployment succeeds.

No iOS source, firmware or CAD implementation changed. No new native app build or full V2–V4 regression run was required for these Python/evidence changes; the earlier version validation remains separate historical evidence.

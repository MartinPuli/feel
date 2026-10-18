# FEEL production readiness — 2026-10-18 UTC

**Decision: NOT READY for unrestricted production.** Useful branch functionality is consolidated on top of upstream main `27a5abc`; older branches remain preserved. Software verification and a working voice-token service do not establish physical sensing, tactile reliability or a complete authenticated memory round trip. Until release scope is confirmed, treat this as an invited-pilot candidate.

## Latest main synchronization — October 18

Merged the new Ethan pin diagnostic (`3646d27` via `c0c0c8e`) and the user's
GPIO25 calibration (`70854ab` via `f733c4c`). GPIO25 first-band nominal position
is 29 degrees with the existing +307 microsecond trim and 2648 microsecond cap.
This is configured behavior, not a new physical measurement. Six active columns,
reserved b0, GPIO32 off and the neutral/failsafe correction are preserved.

The pin diagnostic now correlates hold acknowledgements with the final sequence,
output readiness and highlight, keeps cleanup packets from replacing hold evidence,
and attempts neutral cleanup after write failures/cancellation. Negative LiDAR
bearings parse correctly. Serial acknowledgement is explicitly not final-band proof.
The new suite passed 21 tests, alongside the full firmware host gate.

Optional account-authenticated voice is available behind `FEEL_VOICE_AUTH_MODE=supabase`.
The default remains demo, so current voice and Chalk gateway usage require no new
Supabase connection. Production builds cannot recover old demo codes; logout and
account changes stop audio/tools. Server admission verifies the account and reserves
shared user/global minute/day quota before upstream calls. No SQL, policy or auth-mode
change was applied remotely. All 41 server tests and 15 PostgreSQL/WASM checks passed;
independent database connections and real project configuration remain unverified.
See [SQL evidence](../services/voice-token/sql/LOCAL-VALIDATION.md).

User-provided environment values were normalized into ignored local files. The
Chalk client secret is excluded from phone configuration and Git. Cloud memory
remains off until explicit consent and configuration. No provider keys were added
to source. The voice service was deployed as `dpl_HtGhtRExwaGd36c1HTbdtrMEW6wy`
with the existing runtime configuration preserved.

Read-only Chalk context checks again passed five synthetic cases and 12 assertions
(`/private/tmp/feel-production-sync-chalk.log`). These use seeded records, not live
phone observations. Build-configuration regressions passed four tests, including
atomic failure and excluding demo credentials in optional signed-in mode.

A broad replay run hit a full disk. Generated synthetic recordings and temporary
build caches were removed while retaining source and reports. The final replay ran all 35 scenarios three times each: 30 PASS, 5 KNOWN, 0 FAIL.
It ran scenarios individually and discarded only regenerable synthetic recordings.
Final native validation passed all 301 tests and completed successfully. The selected
`esp32-six-live` firmware rebuilt successfully with current GPIO25 calibration; its
binary and upload instructions are in [ESP32-PROGRAMMING.md](ESP32-PROGRAMMING.md).
The deployed voice probe returned 401 without authorization and 200 with a valid
ephemeral credential using the existing setup; no audio was sent.

## What changed

- Adapted shared room context and private find history from `claude/strange-swartz-7b6d9b` behind a verified-user server proxy. Explicit read consent is separate from upload/sharing consent. No Chalk service token is embedded in the phone.
- Added voice and accessible panel controls for cloud reads and last-seen history. Account/consent/venue changes revoke shared guidance and pending replies; clearing a shared floor prior preserves live observations.
- Fixed a P1 firmware regression: a safety-neutral packet can no longer raise stale bands after 150 ms of silence. A fresh valid packet is required. No servo angles, pulse values or electrical settings changed; no firmware was flashed.
- Fixed replay request races, incorrect tap-band scoring and missing public snapshots in static builds.
- Evaluated all 20 movement fixtures from the other branch with six-sector geometry. Seventeen join the default suite. Three conservative filter-latency failures remain visible in `simulation/pending-scenarios`, with unchanged acceptance thresholds.

A concurrent local-main commit `e0dba1b` was also integrated, preserving its Ethan dot-tracking evidence, protocol clarification and updated safety baselines. It adds no different production source behavior beyond the already verified safety fix. A post-merge replay run again returned 30 PASS / 5 KNOWN / 0 FAIL, including both corrected safety baselines.

The V2 session-memory, V3 saved-room/local-command and V4 guarded-intent features previously ported to main remain present. See [feature inventory](VERSION-INTEGRATION.md) and [branch/regression evidence](../simulation/PRODUCTION-REGRESSION-20261018.md). Integration is selective: older core implementations and app-embedded service credentials were not merged over newer code.

## Verified gates

| Area | Status | Evidence |
|---|---|---|
| Native app/unit integration | PASS | 301 tests, zero failures; `/private/tmp/feel-production-auth-native-final.log`. Initial validation/date-fixture failures were corrected; all assertions retained. |
| Simulator UI | PASS | 12 tests, zero failures; `/private/tmp/feel-production-native-tests.log`. UI ran on the simulator, not the phone. |
| iPhone target compilation | PASS | `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`; `/private/tmp/feel-production-device-build.log`. Unsigned build, not an installed app. |
| Portable core | PASS | 396 tests, zero failures; `/private/tmp/feel-production-core-final.log` |
| ESP32 board builds | PASS | All five configured environments compile: `esp32`, `esp32s3`, both enabled-output compilechecks and `esp32-six-live`. Pinned PlatformIO/NimBLE dependencies; no flashing. |
| Firmware host logic | PASS | 44 controller tests plus adapter/config/CLI suites; neutral regression reproduced before fix |
| Packet-to-pin simulation | PASS | 24 paths; simulated actuator state only |
| Default scenario replay | PASS with limitations | 35 scenarios ×3 deterministic; 30 PASS / 5 KNOWN / 0 FAIL; reserved slot violations zero |
| Additional receding-person acceptance | FAIL | Three explicit candidates retain a nearer band longer than their geometric labels permit; no false-clear observed in those fixtures |
| Replay scorer / web | PASS | Five scorer tests, 11 web tests, static build and published-snapshot readback |
| Chalk Python / intent backend | PASS | 135 / 36 tests, zero skips; `/private/tmp/feel-production-chalk-tests.log`, `/private/tmp/feel-production-intent-tests.log` |
| Voice + context server regression | PASS | 41 tests; `/private/tmp/feel-production-auth-server.log` |
| Production OpenAI credential exchange | PASS | Anonymous request 401; correctly provisioned iPhone-shaped request 200 with ephemeral credential. No secret logged and no speech/audio sent |
| Direct Chalk synthetic context | PASS | Five cases / 12 assertions, unchanged seeded records; no model inference or seed writes |
| Phone installation / headphones / tactile sensing | BLOCKED / NOT VERIFIED | Paired iPhone 17 Pro reports `unavailable`; no installation or physical acceptance claimed |
| CAD export/contact validation | BLOCKED | OpenSCAD is unavailable. Eight portable CAD checks pass; exported meshes and cam contact simulation remain unverified. |
| Public-production release | BLOCKED | Configuration, durable admission limits, authenticated end-to-end and physical gates below |

The first HTTP voice probe used Python's form/JSON body handling and correctly received `body_must_be_empty`. Repeating with the actual native client's bodyless POST succeeded, both before and after deployment. This was a probe mismatch, not an observed iPhone voice regression.

The added network tests exposed an existing Journey test timestamp initialized when XCTest constructed test objects, before execution. It now initializes at first use within each test. A new shared-memory fixture uses a whole-second date consistent with its stored format. Neither fix relaxes assertions. Raw control characters are now rejected before object-name normalization.

## Deployment and configuration

The existing `feel-v1-voice` Vercel project now serves the tested source at [the production alias](https://feel-v1-voice.vercel.app). Deployment `dpl_HtGhtRExwaGd36c1HTbdtrMEW6wy` is READY. The prior context smoke checks established that `/context` and `/api/context` reject anonymous requests with 401 and return `context_not_configured` (503) for a syntactically valid bearer while required configuration is absent. Existing OpenAI voice configuration was preserved.

A deployment attempt briefly created an unconfigured project named `voice-token`; that project and its deployment were removed. The final deployment uses the verified existing FEEL project identity. No new credential values were installed or printed.

Sanitized observations are under [evidence/production-20261018](evidence/production-20261018). The [FEEL Chalk notebook](https://chalk.ai/projects/cmvcr1tjd02rv013ec55n2w6f/environments/flnyc749e8d9/notebooks/cmvd80k640bwm013e8kk1epp0) also records this context boundary and the remaining end-to-end checks. No message was sent to Chalk staff.

Local source tests use mocked upstream Auth/Chalk responses; those tests do not verify production authentication. The independent direct-engine fixture checks prove the existing Chalk resolver path, not an iPhone upload/read round trip.

### Release blockers

1. **Optional cloud-memory activation.** The existing FEEL project is `kgdtplktjdqomdvssdbm`, identified from Chalk and confirmed by user-provided configuration. Its public URL/key and the existing voice/Chalk gateway settings are now provisioned in ignored local build configuration. No account/database was created. The user asked to keep Chalk usable without a Supabase login; cloud uploads/reads remain opt-in. Server-side context activation still needs a reviewed engine origin, room allowlist and authenticated round-trip verification. The unrelated connector project `executionos` was not used. [Configuration contract](../services/voice-token/CONTEXT.md).
2. **Real authenticated round trip.** Verify sign-in → explicit consent → one owned synthetic find → write ownership/RLS → Chalk lookup → phone response. Include logout, expired session, consent withdrawal and room access rejection. Cloud read tokens currently fail closed on expiry and rely on existing sign-in/refresh; private test/device IDs are not migrated to real user IDs automatically.
3. **Public access and cost controls.** The existing voice endpoint uses a provisioned shared demo access code; instance-local rate caps are not distributed quotas. The photo gateway is also provisioned on the phone. Optional user-bound admission and shared PostgreSQL quota support are now implemented and tested locally, but are not activated. Public release still needs a deployed identity/quota configuration, provider spending controls and a reviewed client credential boundary. The optional intent service remains a local development backend, not a deployed public endpoint.
4. **Physical acceptance.** Install on the connected, unlocked phone and verify voice interruption, mute/unmute, headphones, offline fallback, real tracking loss/relocalization, BLE neutral/failsafe and the tactile assembly in a supervised clear indoor space. No simulation proves those behaviors. The firmware safety fix must be reviewed and deliberately flashed before claiming it is running on hardware.
5. **Known evaluation limits.** Direct Chalk/MCP parity remains unresolved. The earlier text holdout was partial and missed the 1-second latency target; no new quality promotion is claimed. Five default simulation limitations and three receding-person candidates remain documented. The local venue timestamp correction has not been deployed to Chalk.

## Version gates

| Area | Status |
|---|---|
| V2 software | PASS for local software gates; cloud activation remains blocked |
| V2 simulation | PASS with the explicitly documented known/pending cases |
| V2 physical hardware | NOT VERIFIED |
| V3 software | PASS for native/core checks; no device acceptance claim |
| V3 physical hardware | NOT VERIFIED |

## Commands and reproduction

```sh
cd ios
xcodegen generate
xcodebuild -project Lantern.xcodeproj -scheme Lantern \
  -destination 'platform=iOS Simulator,id=2CEF5AB6-CC8C-4F3F-898F-AB4A7335DFFD' \
  -derivedDataPath /private/tmp/feel-version-integration-build \
  -only-testing:LanternTests -only-testing:LanternUITests CODE_SIGNING_ALLOWED=NO test
cd Shared/FeelCore
swift test --scratch-path /private/tmp/feel-production-core-final
cd ../../..
sh firmware/test/run_host_tests.sh
python3 simulation/pin_diagnostics.py
python3 simulation/run.py --repeat 3 --no-web --no-build
python3 -m unittest discover -s simulation/tests -v
npm --prefix web test
npm --prefix web run build
(cd services/voice-token && node --test)
PYTHONPATH=chalk /tmp/feel-chalk-context-sdk/bin/python -m unittest discover -s chalk/tests
/tmp/feel-chalk-eval-inspect/bin/python -m unittest discover -s services/chalk -v
```

Use an actually installed simulator and SDK environment on another machine. Secret-bearing deployment and live checks are intentionally absent from copyable commands.

## Next three human actions

1. Review the [ESP32 programming handoff](ESP32-PROGRAMMING.md), confirm the classic board and approved power setup, then explicitly authorize upload when ready.
2. Connect and unlock the iPhone to install and verify the current voice/Chalk build; cloud memory may stay disabled.
3. Complete supervised voice/tracking/BLE/tactile acceptance after programming; confirm release scope before enabling public access.

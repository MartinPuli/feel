# Current blockers and limitations

No production software bug is claimed fixed: the original software was not supplied. Model defects found during review are tracked in `REVIEW.md` with the retest result.

| ID | Severity / state | Evidence or reproduction | Owner / next action |
|---|---|---|---|
| SRC-01 | Release blocker — OPEN | Initial GitHub contents request returned “This repository is empty”; branches were `[]`. `python3 scripts/check_sources.py` exits 2. | Source holder/team: upload original working folder, including uncommitted files, tests and model resources. See `SOURCE-IMPORT.md`. |
| IOS-01 | Release blocker — OPEN | Linux runner has no Swift/Xcode/XcodeGen/simctl. No original iOS source or model is present. | iOS engineer: restore project, inspect pins/schemes, run simulator and unsigned device builds on compatible macOS. |
| CONTRACT-01 | Release blocker — OPEN | Python model is independent of absent Swift encoder and C++ decoder. `validation/adapters/run_contract_tests.sh` intentionally does not exist. | Integrator: bind fixture vectors to production implementations, reconcile edge cases, rerun actual firmware host/board builds. |
| MECH-01 | Physical blocker — OPEN | No supplied CAD source, parts, FS0307 datasheet/measurements, powered column or P1–P5 record. | Hardware team: recover CAD, measure exact units, perform staged bring-up and record results. No guessed mechanical changes. |
| SENSOR-01 | Physical blocker — OPEN | No real LiDAR/BLE/UWB/detector run or physical angle-sign test in this session. | Phone/hardware team: stationary mapping, failure tests and supervised indoor integration. |
| PROTO-01 | Contract limitation — OPEN | Nine assigned bytes contain no application timestamp/checksum. A corruption that still forms a valid packet, or a delayed valid packet, is not detectable from those bytes alone. | Integrator: verify real transport behavior and stale-input handling; preserve the V2 wire format unless the team deliberately versions both ends. |
| POLICY-01 | Specification uncertainty — OPEN | Handoff omits exact range endpoints, field of view, neutral selection, ordering policy, stale-data limits and timing. Model choices are labeled in `validation/README.md`. | Integrator: compare original source/docs and replace assumptions with audited behavior. |
| EVENT-01 | Submission blocker — OPEN | Opening summary does not confirm pre-existing-work eligibility. Prior work is explicitly described in the October 15 handoff. | Team: obtain organizer guidance; record answer in `ELIGIBILITY.md`. |
| V3-01 | Gate dependency — NOT STARTED | V2 software has not passed; starting V3 would violate the requested priority gate. | Lead engineer: branch from an actually passing V2 commit after blockers resolve. |

Do not interpret a neutral pin pattern as confirmation of safe or empty space. The wire format does not distinguish sensor uncertainty from “no obstacle selected”; an app needs an explicit unavailable state and must stop presenting directional guidance when its inputs are unreliable.

CI includes a deliberately failing source-presence gate until the real project is imported. A passing **Specification model only** job is not a V2 release approval. The future macOS/firmware jobs require alignment with the actual project and compatible tool versions; those builds have not been validated here.

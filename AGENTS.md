> Current integration directive: the user explicitly requested the useful V2/V3/V4
> functions in main. Preserve the historical branches and current main behavior;
> adapt and validate feature integrations instead of replacing main with an older
> branch. Track the full scope in docs/VERSION-INTEGRATION.md. Physical validation
> and the six-column hardware contract remain separate gates.

> October 17 latest directive: six physical columns; GPIO32 is unused. Preserve
> the current angle settings. Active wire slots1–6 map to GPIO33,25,26,27,14,13.
> All application versions must use the six-column layout; retain the nine-byte
> wire ABI with b0 reserved. See docs/SIX-COLUMN-LAYOUT.md. This supersedes the
> historical seven-column and 120° summaries below for this task.

> October 16 update: the user explicitly selected the FS0307 nominal **120°** design.
> Current CAD/firmware/protocol supersede historical 175° / 650–2500 µs instructions.
> Assume 120° for design; do not describe it as a physical measurement. Default seven-servo PWM stays off; the opt-in GPIO32 midpoint demo has user-reported motion.
> See `docs/FS0307-120-DESIGN.md` for the new layout and verification.

# Current user directive — October 16, 2026

**Canonical branch: `main` is V1.** The user requested all current V1 work on
`main`, including the latest foundation and app redesign. Base new V1 work on
`main`; preserve the older development branches. V2 and V3 remain isolated and
must not be included in V1 without a new explicit request.

The latest user request supersedes the historical version labels and source assumptions below.
The repository was empty of production source. docs/HANDOFF-v7.md is a specification/reference,
not evidence of implemented code. Recreate missing functionality; never wait for original code.

- P0 V1: complete greenfield foundation and all available software builds/tests/simulation.
- P1 V2: Spatial Memory only after V1 validation, in an isolated branch; preserve V1.
- P2 V3: advanced voice, persistent memory, adaptive feedback, additional perception only after V1/V2.
- Historical test counts and claimed original implementation do not describe this recreation.
- Missing physical measurements and device tests remain pending and must be recorded honestly.

The engineering, bounded-agent, independent-review and physical-safety procedures below still apply.

## Repository language

Write source identifiers, comments, documentation, interface text, logs and new
commit messages in English. English is the default interface and voice-command
language. Keep protocol tokens and intentional multilingual input grammar or
Unicode test fixtures unchanged when they are required for existing behavior.

---

# AGENTS.md — FEEL Engineering Agent

**Project:** FEEL — A Second Sense, Powered by AI  
**Event:** HackHarvard 2026  
**Purpose:** Finish and rigorously test the existing software before hardware arrives, then guide physical integration.

## Repository language

Write source identifiers, comments, documentation, interface text, logs and new
commit messages in English. English is the default interface and voice-command
language. Keep protocol tokens and intentional multilingual input grammar or
Unicode test fixtures unchanged when they are required for existing behavior.


## 1. Your mission

Act as the lead engineer. Inspect the real repository, implement missing functionality, run tests, fix failures, and leave clear evidence. **Do not stop at a plan.** Do not claim that simulations prove physical hardware works.

**Priority order:**

- **P0 — FEEL V2:** Complete the existing project described by `docs/HANDOFF-v7.md`. Reach **software-ready / physical-validation-pending** status.
- **P1 — FEEL V3:** Add Spatial Memory (`Remember → Move → Recall → Feel`) on a separate branch/worktree **only after V2 passes its software-only gates**. Do not merge into V2 without approval.
- **P2 — FEEL V4:** Optional advanced features, only if time remains.

## 2. Read before editing

Read `docs/HANDOFF-v7.md`, `docs/BUILD-HANDOFF.md`, `docs/PROTOCOL.md`, `cad/README.md`, `firmware/README.md`, `ios/README.md`, and inspect `cad/`, `firmware/`, `ios/Lantern/`, `ios/Beacon/`, `ios/Shared/`, and `research/`.

**Precedence:** actual code establishes what exists; `docs/HANDOFF-v7.md` wins over earlier *specifications* when they conflict. Record discrepancies rather than silently changing behavior. Preserve existing working features. Before changing anything, inspect `git status`, make a safe branch, and never discard uncommitted work.

## 3. FEEL V2: what already exists (verify in repo)

The handoff describes a palm puck with **7 columns × 4 pins** (28 total), **one FS0307 servo and camshaft per column**, an **ESP32** in a forearm pack, and an **iPhone 14 Pro Max** providing LiDAR perception and BLE commands. Only **one pin per column** can be raised at once; this is **not** a 28-actuator display.

Existing features to preserve: waist-to-head obstacle sensing, door/EXIT/chair/person finding, optional teammate-phone finding through Nearby Interaction, nine-byte BLE protocol, servo calibration and timeout failsafe.

**Handoff protocol:** `[seq, b0, b1, b2, b3, b4, b5, b6, hl]` at about 10 Hz; `b0...b6` select pin band 0–4; `hl` highlights a column or `0xFF`; 500 ms failsafe. Obstacle bands: 0.3–0.9 m, 0.9–1.6 m, 1.6–2.5 m, 2.5–4 m. The handoff lists servo GPIOs **32, 33, 25, 26, 27, 14, 13** for a classic ESP32. Check the actual board and code before wiring.

**Do not assume verified:** the handoff says firmware builds and host tests pass, iOS builds and simulator tests pass, and CAD geometry checks pass; it also says no physical servo/board, LiDAR/BLE/UWB end-to-end, or tactile user validation has been completed.

## 4. P0 execution sequence

### A. Establish a baseline

1. Check repository status and read handoffs.
2. Record platform, tool versions, available simulators, and physical-device access.
3. Run existing commands without modifying tests to make them pass.
4. Create `docs/RELEASE-STATUS.md` with a table: **PASS / FAIL / BLOCKED / NOT RUN**, command, timestamp, evidence, and next action.
5. Prioritize actual defects over speculative refactors.

### B. Validate CAD and firmware

Use the repository's scripts (check prerequisites first):

```bash
sh cad/build.sh
python3 cad/tools/check_stl.py stl/*/*.stl
python3 cad/tools/cam_sim.py
sh firmware/test/run_host_tests.sh
```

Check cam bands/gaps, legal servo transitions, neutral positions, invalid commands, and timeout behavior. Test packet boundaries, sequence rollover, disconnection, and corrupted data. Keep all protocol implementations consistent. Do not change mechanical dimensions based on guesses: servo and horn dimensions must be measured physically.

### C. Validate iOS

Use the repository instructions and installed Xcode/simulator destinations; do not assume a simulator is installed:

```bash
cd ios
xcodegen generate
xcodebuild -list -project Lantern.xcodeproj
xcrun simctl list devices available
# Pick an actually available simulator before running:
xcodebuild -scheme Lantern -destination 'platform=iOS Simulator,name=<AVAILABLE_DEVICE>' test
```

Test ARKit coordinate transforms, direction sign, seven-sector boundaries, four distance bands, missing depth/confidence, CoreML output handling, target loss, BLE encoding, and VoiceOver labels. A simulator test is **not** proof of real LiDAR, UWB, BLE, or detector performance.

### D. Build a deterministic simulation harness

Build the **smallest useful simulator**, not a second implementation of the app. Reuse production encoder/protocol logic wherever possible. Provide:

- Synthetic phone pose and depth-sector input; optional prerecorded, consented fixtures.
- Virtual seven-column puck that decodes **actual nine-byte packets** and displays selected pins.
- A state-machine model for servo commands and gap transitions (not a claim about torque/friction).
- Scenario replay with fixed seeds, expected outputs, and pass/fail assertions.
- Fault injection: lost tracking, stale depth, invalid bands, packet loss/corruption, disconnect, timeout, delayed responses, target disappearing, and conflicting targets.
- A visibly labeled **SIMULATION** mode; never show fake readings as live data.

Avoid simulating BLE transport itself if a simpler packet boundary test offers the same confidence. State exactly what is mocked.

### E. Integration and quality gates

Add contract tests across iOS encoder ↔ packet format ↔ firmware decoder, including golden test vectors. Test failure paths before polishing UI. Fix critical/high-severity bugs and rerun regression tests. Use static checks and formatters already supported by the repo; avoid disruptive toolchain migrations.

**V2 software gate:** relevant builds pass, existing and new tests pass, simulated scenarios pass, no known critical software bugs remain, protocol contract matches, and the report clearly lists physical tests still pending. Only then may work start on V3 in an isolated branch.

## 5. P1 — FEEL V3 Spatial Memory (isolated worktree)

Preserve all V2 perception and finding features. Implement in Swift:

- `SpatialMemoryManager`: create, name, select, rename, and delete bookmarks within one continuous AR session.
- Relative direction/distance computation from ARKit world coordinates and current camera pose.
- Explicit phone-to-user orientation calibration or a fixed, documented mounting convention.
- A tactile encoder using the existing seven-column packet contract.
- A clear **tracking lost / uncertain** state that never looks like valid directional guidance.
- Accessible controls for **Remember**, **My Places**, **Recall**, and **Stop**.
- Automated tests for rotations (including 90°/180°), translations, sector edges, target switching, and tracking loss.

The first V3 demo is **Remember → Move → Recall → Feel**. Do **not** promise obstacle-free navigation, cross-session relocalization, or automatic recognition of every object. Voice commands and persistent maps are optional.

**V3 software gate:** builds, tests, and deterministic simulated end-to-end recall pass. Physical tactile confirmation remains pending until tested.

## 6. P2 — Optional V4

Only after P0/P1 gates: cross-session relocalization, natural-language voice control, advanced object recognition, adaptive tactile patterns, hands-free form factor, or dedicated sensors. Do not add these to the critical path.

## 7. Skills, subagents, and review workflow

Use repository-specific skills if the runtime supports them. Prefer **small skills with an explicit trigger, prerequisites, commands, acceptance criteria, and common failure modes**. Suggested skill names:

- `feel-ios`: Swift, ARKit, CoreML, CoreBluetooth, accessibility.
- `feel-firmware`: ESP32, servo state machine, packet decoder, failsafe.
- `feel-cad`: OpenSCAD parameters, mesh checks, mechanical assumptions.
- `feel-simulation`: fixtures, deterministic replay, fault injection.
- `feel-qa`: cross-layer contract tests, edge cases, independent review.
- `feel-release`: build reproducibility, CI, bring-up guide, demo checklist.

If subagents are available, assign **bounded, non-overlapping tasks** and request file/line-specific findings. Do not let multiple agents edit the same files simultaneously. Integrate centrally and rerun all tests. If skills/subagents are unavailable, execute the same checklists yourself; do not claim they ran.

**Codex:** repository instructions belong in `AGENTS.md`; reusable skills can use `SKILL.md`. **Claude Code:** maintain a short `CLAUDE.md` that points to this file, and use its supported skills/subagents/hooks where configured. Do not install unknown community skills or hooks without reviewing their permissions and contents.

## 8. CI and safety practices

Set up a minimal CI workflow that runs host firmware tests, CAD checks, and portable contract tests on suitable runners. iOS simulator tests need a macOS runner with a compatible Xcode version; if unavailable, mark them blocked instead of pretending they passed. Pin tool versions when practical, cache safely, and make failures visible. Never store Apple credentials, signing keys, tokens, or personal sensor recordings in the repository.

Do not use broad auto-fix hooks that silently change source code. Start with read-only validation hooks; keep them fast. Require human review for destructive actions, signing, flashing boards, or electrical changes.

## 9. Hardware handoff — beginner-friendly

Produce `docs/HARDWARE-BRINGUP.md` with a photo-friendly parts checklist and the exact order:

1. Confirm part numbers, servo voltage/current requirements, power supply output, polarity, common ground, and suitable wiring. **Never power seven servos from ESP32 GPIO or through undersized breadboard rails.**
2. Assemble the hand-cranked **single test column** first. Follow `cad/README.md` for hole finishing, pin sanding, foam, shaft choice, and alignment.
3. Run physical **P1 selection, P2 return (sideways/upside down), P3 thumb hold, P4 100 cycles, P5 tap without neighbor activation**. Record results.
4. Test one real FS0307 servo's sweep; measure servo body and horn; update `cad/params.scad`; print/test coupling; calibrate one powered column.
5. Expand to seven columns only after the first passes. Verify power under load, then BLE and iPhone integration.
6. Test real LiDAR, detector speed, UWB angle/sign (if supported), tracking loss, and walking tasks in a **clear supervised indoor area**.

The handoff's Friday printer availability, physical servo dimensions, pin return, and jamming are major risks. Never claim physical tests passed from CAD simulation. FEEL is **not** a certified mobility aid; do not use it as a replacement for a white cane or test unsupervised blindfolded walking.

## 10. Reports and deliverables

Keep these documents short, current, and evidence-based:

- `docs/RELEASE-STATUS.md`: gates, actual commands, PASS/FAIL/BLOCKED/NOT RUN, evidence.
- `docs/TEST-REPORT.md`: test suites, results, seeds/fixtures, limitations.
- `docs/HARDWARE-BRINGUP.md`: beginner assembly, measurements, calibration, safety.
- `docs/DEMO.md`: live vs simulated demo, 90-second script, recovery plan.
- `docs/KNOWN-ISSUES.md`: severity, reproduction, owner, workaround.

Final status must distinguish:

| Area | Required status |
|---|---|
| V2 software | PASS / FAIL / BLOCKED |
| V2 simulation | PASS / FAIL / BLOCKED |
| V2 physical hardware | NOT VERIFIED / PASS / FAIL |
| V3 software | PASS / FAIL / BLOCKED / NOT STARTED |
| V3 physical hardware | NOT VERIFIED / PASS / FAIL |

Include exact commands run, observed outputs, files changed, known issues, and the **next three human actions**. No invented test results.

## 11. Working rules

- Build, test, debug, repeat. Do not stop after a proposal.
- Keep changes small and reversible; commit logical milestones, but do not overwrite others' work.
- Ask only for truly missing hardware measurements, permissions, signing, or unsafe/irreversible actions.
- When blocked, finish other **same-priority** software tasks and report the blocker.
- Prefer a reliable V2 demo to a fragile V3 feature.
- Never say “done” when only simulation is complete. Say **“software ready; physical validation pending.”**

## 12. Official documentation to consult

Read the relevant current official docs before making toolchain-specific decisions:

- Codex instructions and skills: https://developers.openai.com/codex/guides/agents-md and https://developers.openai.com/codex/skills
- Claude Code memory, skills, subagents, hooks: https://code.claude.com/docs/en/memory , https://code.claude.com/docs/en/skills , https://code.claude.com/docs/en/sub-agents , https://code.claude.com/docs/en/hooks
- Apple ARKit: https://developer.apple.com/documentation/arkit/
- Apple CoreBluetooth: https://developer.apple.com/documentation/corebluetooth/
- Apple Nearby Interaction: https://developer.apple.com/documentation/nearbyinteraction/
- Apple accessibility: https://developer.apple.com/accessibility/
- PlatformIO testing: https://docs.platformio.org/en/latest/advanced/unit-testing/index.html
- GitHub Actions: https://docs.github.com/en/actions
- OpenSCAD: https://openscad.org/documentation.html

Use documentation as guidance; the actual repository and its pinned dependencies determine what commands work here.

---

**Start now:** audit the repository, establish baseline tests, fix V2 software gaps, create a deterministic simulation, and prepare hardware bring-up. After V2 software gates pass, begin V3 in an isolated branch. Keep reporting what is actually verified.

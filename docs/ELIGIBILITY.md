# HackHarvard eligibility and provenance

**Organizer approval is unresolved. No message has been sent and no submission has been made by this engineering session.** The supplied `HACKHARVARD-2026.md` summarizes the opening ceremony; it does not establish permission to compete using pre-event work.

## What predates this engineering work

`HANDOFF-v7.md`, dated October 15, 2026, describes a developed mechanical design, firmware, iOS apps, prior host/simulator tests and research. It explicitly says those changes were uncommitted. The repository supplied for this session did not contain those implementations. Their absence from GitHub does **not** turn the ideas, designs or code into new hackathon work.

| Item | Provenance | Verification in this session |
|---|---|---|
| FEEL concept, 7 × 4 single-pin-per-column mechanism, nine-byte protocol | Supplied pre-event handoff and instructions | Documented design intent; not a new invention by this session |
| Original CAD/STLs, ESP32 firmware, Lantern/Beacon apps and research | Reported by October 15 handoff | Original source missing at audit; prior build/test claims not reproduced |
| `AGENTS.md`, `HANDOFF-v7.md`, `HACKHARVARD-2026.md` | Supplied by the user | Inputs, not newly authored implementation |
| Portable specification model, tests, simulation and integration preparation | Newly authored in this engineering session | Use exact commit history and `TEST-REPORT.md` for scope/results; do not substitute for missing hardware/app verification |
| Physical assembly, sensor demonstrations and user feedback | No evidence supplied to this session | NOT VERIFIED until team records actual work |

Maintain this distinction when original files are recovered: preserve their provenance and authorship, and describe weekend changes separately. Do not rewrite dates or imply that a fresh import commit is the original creation date.

## Questions for an organizer

| Question | Organizer / time / answer / evidence |
|---|---|
| May we use the pre-event concept, CAD, firmware, iOS apps or printed prototype? Which portions must be rebuilt, excluded or disclosed? | ____ |
| What exact work can be judged, and where should we disclose earlier work and AI-assisted engineering? | ____ |
| Are there special Hardware for Good requirements and moving-part/demo safety restrictions? | ____ |
| May one project enter multiple tracks/challenges? | ____ |
| What are the judging rubric, Devpost fields, video format/length, repository visibility and required artifacts? | ____ |
| Is there a separate overall prize, and if so what are its eligibility rules? | ____ |
| Have the submission deadline, in-person requirements or venue access changed since the opening slides? | ____ |

Do not import 2025 rules or infer organizer approval from an accepted registration. If pre-event implementation is disallowed, ask whether a clearly separated new contribution can be judged. Do not silently relabel older work.

## Ready-to-use disclosure draft

> FEEL builds on a concept and engineering handoff prepared before HackHarvard. That handoff describes a 7 × 4 tactile-pin mechanism, CAD, ESP32 firmware, iPhone apps and earlier software tests. Those original implementations were not present in the GitHub repository provided for this engineering session, so we could not reproduce their reported results. During this session we created the software preparation and deterministic simulation documented in our commit history and test report. We distinguish those simulated results from physical tests; no physical verification is claimed without recorded evidence. Please confirm what work is eligible and how you would like the pre-existing work disclosed.

Update the paragraph with recovered-source provenance and **actual weekend work**, then obtain the team's review before sending or publishing it.

## Submission checks from the supplied event summary

- [ ] At most four teammates, correctly attributed.
- [ ] Primary track: Hardware for Good, subject to organizer eligibility guidance.
- [ ] Devpost submitted **before Sunday, October 18, 2026, 8:00 AM America/New_York (EDT; 12:00 UTC)**, unless organizers announce a change.
- [ ] In-person judging: Sunday 9:00 AM–noon; closing: 3:00–4:00 PM, per the supplied summary.
- [ ] Off-site work arranged: the supplied summary says the venue closes at 8:00 PM nightly.
- [ ] Public claims, source disclosure, screenshots/video and actual test records reviewed by the team.

This file records unresolved questions; it is not a ruling on eligibility.

# FEEL — Devpost draft

**Draft only; not submitted.** This version is truthful for a software-preparation demo. Update it with measured physical results only after they exist. Confirm organizer guidance in [ELIGIBILITY.md](ELIGIBILITY.md) before publishing. Deadline in the supplied event summary: **October 18, 2026, before 8:00 AM EDT**.

## Project name and short description

**FEEL — spatial information through touch**

A tactile perception prototype designed around seven servo-driven columns and 28 pins. The current demonstrable work is a deterministic software model and failure-testing preparation; physical hardware and the original iPhone integration remain unverified.

## Inspiration

We want to explore how spatial information can reach someone through touch while leaving hearing available. FEEL's proposed palm interface represents direction across seven columns and near-to-far distance across four pin positions. The project builds on an engineering handoff written before HackHarvard; we disclose that history separately from the work completed during the event.

## What it does

The design uses one servo and cam per column, so **only one of the four pins in each column can be raised at a time**. The intended iPhone system senses obstacles and finds targets; a nine-byte packet tells an ESP32 which pin to select in each column and which column to highlight.

The software demonstration uses synthetic inputs and a virtual puck. It exercises packet validation, state transitions and failure handling. It does not show real LiDAR, Bluetooth radio delivery, servo force, tactile usability or walking safety. Consult the committed test report for the exact implemented scenarios and observed results.

## How we built it

The original handoff specifies an iPhone 14 Pro Max, ARKit/LiDAR, ESP32, seven FS0307 servos and a printed cam mechanism. It reports prior CAD, firmware and iOS work, but those source files were absent from the repository supplied for this engineering session.

We worked from the available specification to prepare a portable protocol/model implementation, reproducible software checks, deterministic scenarios, and staged hardware integration instructions. Each newly written component is identified in the repository; it should not be confused with recovered production software. The software tests model intended behavior, while the hardware checklist makes outstanding physical measurements and acceptance tests explicit.

## Challenges

Recovering the missing implementation is necessary to verify the complete V2 system. A valid packet cannot establish that a printed pin returns, a servo has enough usable travel, or a phone reports the correct physical direction. The mechanism requires measured fit, unloaded servo characterization, manual return/endurance checks and one-column powered validation before expanding to seven columns.

## What we can demonstrate now

An honestly labeled **SIMULATION** of the tactile command path, with executable software evidence and explicit unknowns. State exact results from `docs/TEST-REPORT.md` when finalizing this field; do not copy the historical handoff's test counts as newly reproduced results.

## What we learned

The most useful next step is a verified single column. Reliable pin return, correct direction, stable power and a safe timeout matter more to this demo than extra features. We also learned to keep modeled behavior separate from hardware measurements and user feedback.

## What's next

Recover the original sources; complete manual P1–P5 testing; measure the actual servo and horn; calibrate one powered column; then validate all seven columns with the real phone. Spatial Memory remains a separate future stage until V2's software gate passes. No cross-session memory or obstacle-free navigation is claimed.

## Provenance and limits

- **Pre-existing:** FEEL concept and supplied handoff; original CAD/firmware/iOS work described by that handoff. Its earlier test claims are unverified in this session.
- **New work:** the committed specification model, simulation, tests and preparation artifacts described in the current README and release report. Record actual commit IDs and dates before submission.
- **Physical verification:** none in this engineering session. Any later claim needs a dated record, setup and evidence.
- **Product limits:** indoor research prototype; not a certified mobility aid or a replacement for a white cane. No clinical benefit, novelty-first claim or universal object-recognition claim.
- **AI assistance:** disclose the engineering agent's code/documentation contributions and the human team's implementation, review and hardware work accurately.
- **Eligibility:** pre-event-work policy awaits organizer confirmation.

## Submission assets to fill in

| Field | Team input |
|---|---|
| Repository | https://github.com/MartinPuli/hackharvard |
| Exact submitted branch/commit | ____ |
| Team members / roles / attributions | ____ |
| Actual technologies used by the submitted implementation | ____ |
| Demo video link and recording date | ____ |
| Screenshot of visibly labeled simulation | ____ |
| Physical photos and measured results, only if obtained | ____ |
| Test-report commit and exact observed results | ____ |
| Earlier source authors / licenses / recovered locations | ____ |
| Organizer eligibility response | ____ |
| Devpost required fields and track confirmation | ____ |

Use [DEMO.md](DEMO.md) for the 90-second script. Remove blanks or replace them with “not available”; never fill them with assumed results. Do not select sponsor challenges without their required integration. No overall prize is assumed.

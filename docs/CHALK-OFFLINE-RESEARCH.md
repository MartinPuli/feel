# Chalk and FEEL without internet

October 17, 2026. Documentation research and source inspection only. No offline mode, data pipeline or synchronization service was deployed.

## What offline means

Chalk's offline store is historical feature storage in a cloud warehouse. Offline queries support historical analysis and batch workloads. It is not an iPhone database or an on-device model runtime. A phone without connectivity cannot reach that store or the Model Gateway. [Offline store](https://docs.chalk.ai/docs/offline-stores).

The useful architecture for FEEL is a local core with optional cloud context. Chalk can prepare and update data while connected; FEEL must implement the download, local storage, expiry rules and disconnected behavior.

## Useful Chalk features

| Capability | Proposed FEEL use | What still belongs in FEEL |
|---|---|---|
| Feature caching and per-query freshness | Reuse stable venue information and preferences without recomputing each question | Download a bounded, versioned local snapshot; reject expired facts |
| Scheduled queries | Refresh approved venue information before users need it | Authenticated distribution and a user-visible download status |
| Stream resolvers | Ingest an authorized venue update feed, if one exists | Delivery to connected phones, conflict resolution and local expiry |
| Historical context | Replay a failure using what the agent knew at that time | Consented capture, dataset curation and reproducible offline-mode tests |
| Per-feature storage controls | Avoid persisting transient location/scene data in feature stores | Separate policies for logs, provider requests, datasets and phone storage |

Chalk's cache lives in its online store. `max_staleness` controls reuse; a query can request fresher values. This reduces server work but does not create a device cache. Setting an age limit also cannot prove that an upstream source was correct. [Query caching](https://docs.chalk.ai/docs/query-caching).

Scheduled queries run feature pipelines and can populate the online or historical store. They could produce the inputs for a venue pack; packaging and downloading that pack would be new FEEL code. [Scheduled queries](https://docs.chalk.ai/docs/scheduled-query).

Stream resolvers consume sources such as Kafka, Kinesis or Pub/Sub. They do not themselves notify an iPhone or supply live building information. Start with scheduled refreshes unless a useful authorized event source actually exists. [Streams](https://docs.chalk.ai/docs/streams).

Features can independently disable `store_online` and `store_offline`. Those settings do not erase earlier data or control other logging systems. Configure them before introducing sensitive context features. [Feature storage](https://docs.chalk.ai/docs/feature-caching).

## Proposed venue pack

A downloaded pack would contain reviewed place names, accessible-entry descriptions, source URLs, evidence dates, effective/expiry dates, schema version and integrity metadata. Keep the first version textual, searchable locally and readable through local speech. A local conversational model is not required for this first step.

Use atomic replacement so a failed download leaves the previous valid pack intact. Keep account-specific content isolated and remove it on sign-out. Never cache a cloud claim that the user's immediate path is clear. Saved object observations must retain their timestamp and must not become current directional guidance after tracking/session changes.

Without connectivity, speak a short status once, preserve mute, and answer only from supported local capabilities. If a time-sensitive fact is expired, say it cannot be confirmed. On reconnection, refresh context without replaying old find/move commands. A consented feedback queue can upload later with stable event IDs and deduplication; never queue raw audio or photos by default.

## What the phone already contains

- Local AR/depth processing and Vision detection paths exist. `ObjectDetector.swift` includes EXIT text, person detection and rectangle-based door candidates. General object detection requires `FEELDetector.mlmodelc`; no bundled detector or language-model weights were found in the inspected iOS tree. A rectangle is only a door candidate.
- `KeywordListener.swift` requires on-device recognition support and sets `requiresOnDeviceRecognition = true`. It listens for a target word associated with a V-sign interaction. This is not a general always-listening offline assistant.
- `RealtimeVoiceSession.swift` has local speech output for fallback feedback, but its conversational assistant uses a network session. Local speech output alone does not provide local understanding of spoken commands. `LanternModel.swift` routes Where-is result announcements through the cloud assistant with a bounded pending retry; this path still needs local spoken output for an offline release.
- Where-is has an on-device fallback after specified cloud failures. That does not make all object queries available without a suitable bundled detector.

These are source findings, not device results. Apple requires `supportsOnDeviceRecognition` before an on-device speech request can work. Availability must be checked on the actual phone and locale. [Apple Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

## Recommended first offline release

Prioritize a small local command grammar for stop, mute, unmute, repeat and available finder modes, with local spoken feedback. It must work without a gesture trigger and share microphone ownership cleanly with the online assistant. Keep ordinary accessible controls available when speech recognition is unavailable. Confirm required assets and permissions before presenting offline voice as ready.

Then add the downloadable venue pack. Leave general offline conversation and broad object recognition for a separately measured implementation. Chalk provider fallback can help when a reachable provider fails; it cannot recover a disconnected phone.

| Test to run | Expected behavior |
|---|---|
| Start without internet | Local capabilities start; unavailable cloud functions are explained briefly |
| Lose internet during speech | Stop stale audio, preserve mute and hand microphone ownership to the local path |
| Say stop or mute offline | Execute locally without waiting for reconnection |
| Ask about an expired entrance restriction | Do not present it as current |
| Search for an unsupported object | State the limitation instead of reporting fabricated detection |
| Reconnect after changing target | Discard old requests; do not execute queued commands |
| Restart with a cached pack | Load only a complete, compatible snapshot and retain source dates |
| Missing speech assets or permission | Expose an accessible recovery path; do not claim listening |

Phone tests must separately check headphone routing, battery/thermal behavior and recognition reliability. When testing airplane mode with the puck, account for Bluetooth's actual enabled state. No physical or offline acceptance test ran during this research.

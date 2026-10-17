# FEEL voice control - Build Plan

## 0. Who this is for
- Users who need the camera and tactile feedback without reading or navigating menus.
- The current V1 requires taps to select targets and inspect status.
- Success means speaking a request, having the existing app execute it, and hearing a brief response grounded in current sensing state.
- Scope includes the native iOS interface, audio transport and a small authenticated token service. Existing ARKit/BLE behavior remains the source of truth.

## 1. Three-phase breakdown
| Phase | Theme | Features included | Forward-look detail level |
|---|---|---|---|
| 1 | Core loop | Grok microphone input, spoken output, validated commands, current sensing status, camera-first voice control | Full below |
| 2 | Completeness | Permission recovery, interruptions, offline/error states, secret handling, tests, installation | Complete before publication |
| 3 | Depth and delight | Quiet state feedback, captions, accessible modal setup, visual review | Refine after the working loop |

All phases belong to V1/main. No V2/V3 branch is imported. AppBuilder's component-state, permission, security and motion guidance applies to the existing SwiftUI implementation; a React Native rewrite and Android expansion are outside this request.

# Phase 1 detailed plan

## 2. Backend
No database, RLS tables or storage buckets are needed. Authenticated POST /session mints a short-lived xAI client secret. XAI_API_KEY stays on the server. The phone stores the service access credential and HTTPS endpoint together in Keychain. Tokens remain in memory. The service bounds requests, expires tokens and redacts upstream failures. Audio goes directly to xAI only during a user-started voice session; camera images do not leave the phone.

## 3. Screen inventory
| Screen | Purpose | Owner-view | Data source |
|---|---|---|---|
| Existing camera | Automatic assistant readiness, listening/speaking state and latest caption | Device user | GrokVoiceSession |
| Existing Settings modal | Voice service setup and permission recovery | Device user | Voice configuration and Keychain |
| Existing connection modal | Explicit puck selection, also accessible through voice | Device user | BluetoothPuck |

## 4. Navigation flow
Complete one-time service setup and grant microphone permission. The assistant then starts automatically when FEEL opens; no Talk button is required. Voice can start/stop the camera, select a supported target, report current status, calibrate using a supplied measured height, and discover/select a puck. Existing manual controls remain reachable. Stop ends camera and tactile output while the assistant keeps listening. Pause assistant explicitly ends microphone capture. Backgrounding stops recording and sensing; returning resumes the assistant unless explicitly paused. Camera restart still requires a request.

## 5. Component needs
Voice control uses existing monochrome Geist tokens and 48-point touch targets. States include idle, permission request, connecting, listening, thinking, speaking, error and missing setup. The caption is bounded and does not become a chat screen. Setup validates HTTPS and credential presence; errors offer retry or system Settings.

## 6. Edge cases to handle explicitly
Handle denied permission, missing setup, invalid/expired token, missing network, remote close, malformed/duplicate tool calls, canceled permission callbacks, unsupported camera, stale sensing, simulation labeling and Bluetooth discovery with no devices. Never infer a safe route from neutral pins. Target announcements use current readings only. Calibration must use a user-supplied measurement.

## 6b. Architecture and performance checklist
Keep audio conversion off the main UI thread, bound pending audio sends/playback, and isolate frequently changing voice state in a small view. Use native AVAudioEngine and URLSession without a new SDK. One coordinator owns session cancellation and audio lifetime. Tool decoding is a separately tested allowlist.

## 6c. Lifecycle and pre-launch checklist
Microphone permission begins on configured app startup or one-time setup. The app keeps the screen awake while sensing or listening. Headphone removal pauses capture with a spoken explanation; reconnection restores it unless explicitly paused. Interruptions resume only when iOS allows it. Network failures get three bounded retries. No background microphone or persisted transcripts. Internet is required for Grok; local camera and Stop remain available. Native crash logs remain the debugging source; no new analytics SDK. English UI with spoken responses matching the user's language. Push notifications and store submission are outside this installed-device update.

## 6d. Security checklist
No xAI key in the app or repo. HTTPS token service, Keychain service credential, ephemeral token in memory, fixed xAI WebSocket destination, no credential logging. Validate every action and numeric parameter before executing. Ignore results from canceled sessions.

## 6e. Store publishing checklist
Not an App Store submission. Document the new audio/data flow before any later store submission. No user accounts or server transcript storage are added.

## 6f. Motion and delight checklist
Use existing restrained panel transitions and named fast voice-state feedback. Respect Reduce Motion. No decorative waveforms claiming audio activity that did not occur.

## 7. Open questions for the user
A usable xAI credential and reachable HTTPS token service are required for live Grok verification. The user has been asked where an existing credential is stored. Local transport/action tests and the app build can proceed without claiming a live conversation.

## References
- https://github.com/ruchitrshah/AppBuilder-Skills
- https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech
- https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens

## Blind-first revision

The user's October 17 correction makes the assistant the default interaction,
not an opt-in Talk button. Foreground activation, audible readiness, distinct
Stop versus Pause assistant commands, spoken permission/route recovery, and
idle-timer ownership are required. The small status control remains accessible
through VoiceOver as a recovery and pause mechanism. FEEL's wordmark has no
background; the LIVE label is removed. Simulation stays explicitly labeled.

Community references reviewed as text, without installing hooks or scripts:
- https://github.com/RobStrayer/voice-agent-skills/blob/main/plugins/voice-foundations/skills/voice-turn-taking/SKILL.md
- https://github.com/RobStrayer/voice-agent-skills/blob/main/plugins/voice-foundations/skills/voice-audio-frontends/SKILL.md

Applied principles: one response owner, playback cancellation on interruption,
rejection of delayed response audio/tools, bounded buffering, native echo
cancellation, and separate physical headset/speaker verification. Proactive
speech is event-driven, deduplicated and quiet while the user speaks. Scene
observations expire after three seconds and are cancelled immediately when
tracking or target validity is lost. Completed hardware actions remain factual
in the returned tool results; interrupted speech does not undo them.

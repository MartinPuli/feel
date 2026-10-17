# V1 personal voice assistant

FEEL is designed to be used by a blind person without finding a Talk button.
After one-time provisioning and microphone permission, the assistant starts
when FEEL opens and says when it is ready. The camera remains the main screen.
The wordmark has no background or LIVE badge. Simulation remains labeled.

## Interaction

Speak through the phone or its connected headset. Interrupt FEEL at any time.
Supported requests include starting the camera, finding a door candidate, EXIT,
chair, person or teammate, reading sensing/connection status, floor calibration
with a supplied measured height, discovering and selecting a puck, and opening
settings. Teammate sharing still uses the existing consent flow.

**Where is X?** For things outside the fixed target list, the assistant calls
`where_is`. FEEL takes one camera photo, sends it with the question through
Chalk's Model Gateway to a vision model (default `openai/gpt-6.1-sol`), places the
answer with LiDAR depth, and keeps the pins pointing at that spot until you arrive,
say stop, pick another target, or tracking resets. When the pins cannot show it,
FEEL says a direction instead ("desk is to your left"). Enter the Chalk gateway
settings once under Assistant settings → Where-is setup; they stay in Keychain. A
photo leaves the phone only for this request. The result is a model's reading of
one photo, not a confirmed object.

“Stop” stops sensing and sends neutral tactile output while the assistant keeps
listening. “Pause assistant” or “stop listening” ends microphone capture. The
VoiceOver-accessible status control can resume it. Each modal exposes separate
Stop camera and Pause assistant actions when applicable.

Useful updates are enabled by default and can be turned off in Assistant
settings. FEEL announces target acquisition/loss, unavailable sensing and puck
loss from actual app state. Updates are deduplicated, separated by at least five
seconds and suppressed while the user speaks. Target-loss announcements wait
600 ms to avoid momentary detector gaps. No periodic conversational polling.

Scene-bearing speech expires after three seconds or immediately on invalid
tracking/target state. Stale audio and tools from interrupted responses are
ignored. Status replies without a scene observation, such as calibration or
permission recovery, remain speakable. Neutral pins never establish a clear path.

## Lifecycle and audio

The screen stays awake while sensing or listening. Leaving or locking the app
ends camera capture and microphone streaming. Returning resumes the assistant,
unless explicitly paused, but does not restart the camera. This implementation
is foreground listening, not a background wake-word service.

Removing a headset pauses capture and announces the reason. Reconnecting it
restores the assistant unless paused. iOS interruptions resume only when the OS
permits it; media-services reset rebuilds the session. Transient voice failures
have three bounded retries and audible failure feedback. Idle sessions renew
after fifteen minutes without interrupting an active turn.

Native AVAudioEngine uses voice processing, Bluetooth HFP routing and PCM16
24 kHz mono. Audio queues and transport messages are bounded. Real echo behavior,
headset microphone selection and perceived interruption latency require device
validation; mocked tests do not establish those properties.

## One-time provisioning

The service in [services/voice-token](../services/voice-token/README.md) exchanges
a server-only xAI API key for short-lived Grok Voice tokens. Deploy it behind a
trusted HTTPS proxy, configure its separate phone access token, then enter the
service /session URL and that access token in Assistant settings. Neither the
xAI key nor any usable credential is bundled with the app. Both phone settings
are stored in Keychain. Audio streams directly to xAI; camera images stay local.

The production token endpoint is `https://feel-v1-voice.vercel.app/session`.
A Voice-only Grok Inference key is configured in Vercel and expires November 16,
2026. The server and real Sal readiness audio have been verified. Build 8 was
provisioned and launched on the unlocked iPhone at 01:24 EDT on October 17.
The user confirmed that FEEL hears them and responds. Headset routing,
interruptions and cold-relaunch persistence still need physical checks.

Debug builds accept an explicit paired developer launch with
`FEEL_PROVISION_VOICE=1`, `FEEL_VOICE_ENDPOINT` and `FEEL_VOICE_ACCESS_TOKEN`.
Only the separate service token is supplied; never an xAI key. With devicectl,
provide these through the caller environment prefixed by `DEVICECTL_CHILD_`,
not command-line values. Validation and a successful Keychain save are required.
An invalid explicit setup fails closed instead of using previous settings.
Release builds ignore this mechanism. UI tests skip provisioning. Relaunch
normally afterward to verify persistence without the environment.

## Validation and review

See [validation evidence](evidence/v1-voice/validation.txt). The code review
covered response ownership, stale observations, error recovery, audio lifecycle
and blind-first controls. No unresolved P0/P1 findings remained in that review.
An initial simulator run crashed in Apple's AXSpeech/TextToSpeech framework.
The app now creates its local synthesizer only when it actually speaks, avoiding
TTS initialization in mocked sessions. Subsequent tests are recorded separately.

The [build plan](V1-VOICE-PLAN.md) records the reviewed AppBuilder and voice skill
sources. Community scripts and hooks were not installed. Native SwiftUI and the
existing sensing/BLE implementation were retained. V2/V3 were not imported.

## Next physical checks

1. Reopen FEEL normally and confirm the assistant starts without setup again.
2. Check spoken camera/target/Stop commands, pause, VoiceOver access and
   invalid-state recovery on the unlocked iPhone.
3. Repeat with the intended headphones, including interruptions, disconnect,
   reconnection and locking. Test sensing/tactile behavior separately with supervision.

## Build 7 voice refinement

The assistant status control now lives as a 48-point icon in the top toolbar.
Its modal contains captions, recovery and pause/resume controls. The camera
center stays empty; automatic foreground listening remains unchanged.

Grok uses Sal at its default speed. The prompt asks for result-first responses,
usually one sentence of 3–12 words, with one follow-up question only when needed.
Readiness is “I'm here.” Repeated introductions and offers to help are removed.
Proactive observations use normal distance units and relative sides, preserve
possible-door uncertainty and use past tense to acknowledge sample-to-speech
latency. Local fallback prefers the highest-quality installed English voice.

The [voice cases](evidence/v1-voice-polish/voice-cases.md) define expected behavior.
These changes do not claim measured improvement to live audio. Official
[voice options](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech#voices)
and [prompting guidance](https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech/prompting-guide)
were checked on October 17. The prompt controls wording; provider voice selection
controls the voice itself. Physical listening evaluation remains necessary.

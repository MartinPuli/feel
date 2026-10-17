# V1 personal voice assistant

FEEL is designed to be used by a blind person without finding a Talk button.
After one-time provisioning and microphone permission, the assistant starts
when FEEL opens and says when it is ready. The camera remains the main screen.
The wordmark uses the same capsule background and border as nearby controls.
There is no LIVE badge. Simulation remains labeled.

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
one photo, not a confirmed object. Without Chalk settings, or when Chalk cannot be
reached within 12 s, FEEL answers on the phone itself: Vision reads EXIT signs and
door-shaped rectangles and finds people, and the bundled Core ML detector finds chairs
and common objects (run `python3 scripts/fetch_model.py` before building). For anything
else offline it says "I can only look for the exit, a door, a person, a chair or common
objects right now." With direction arrows on, a found target also becomes the arrows' route goal:
the pins draw one arrow along the planned route to it, then again only when the route changes.

**Typed requests.** While the assistant is active, the Assistant panel has a "Type a
request" field. Text takes the same path as speech (a user item, then a response), so
a loud room or a Bluetooth keyboard with VoiceOver still works.

**No sound output.** The iOS Simulator can keep captions and tool calls running
without an audio engine. On an iPhone, a playback failure closes the broken audio
session and follows the bounded reconnect policy. It does not silently switch a
blind user's assistant to captions only.

“Stop” stops sensing and sends neutral tactile output while the assistant keeps
listening. “Pause assistant” or “stop listening” ends microphone capture. The
VoiceOver-accessible status control can resume it. Each modal exposes separate
Stop camera and Pause assistant actions when applicable.

Useful updates are enabled by default and can be turned off by voice or in
Assistant settings. FEEL announces stable nearby obstacles, initial target
acquisition, meaningful target movement, target loss and sensing recovery.
New scene observations need 0.8 seconds of stability and at least eight seconds
between accepted observations. Unchanged readings stay quiet. Obstacles at or
within 0.9 meters take priority; readings below 0.3 meters remain eligible.
Target movement requires a side change or a distance change of at least 0.5 meters.
Obstacle approach requires at least 0.4 meters of change. These are event-driven
updates from fresh calibrated live frames, not periodic conversational polling.
Target-loss announcements wait 600 ms; all updates wait while the user speaks.

“Silence yourself” mutes current and future speech while leaving the microphone
and app controls active. “Speak again” restores spoken replies. “Stop automatic
updates” disables unsolicited observations but preserves answers to questions.
“Stop listening” pauses capture and needs the accessible on-screen control to
resume. Locking/backgrounding still pauses capture in every mode.

Voice actions now cover the camera, target selection, measured camera height,
floor calibration, puck discovery/selection/disconnection, teammate discovery,
explicit invitations and stopping, simulation, panel navigation, the drawer,
spoken replies and useful updates. Teammates still accept on their own phone.
FEEL can open its iPhone Settings page, but iOS permission choices remain manual.
Forgetting voice setup requires explicit confirmation and ends the connection.
Credential entry remains manual; the assistant never requests secrets aloud.

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
a server-only OpenAI API key for short-lived Realtime tokens. Deploy it behind a
trusted HTTPS proxy, configure its separate phone access token, then enter the
service /session URL and that access token in Assistant settings. Neither the
OpenAI key nor any usable credential is bundled with the app. Both phone settings
are stored in Keychain. Audio streams directly to OpenAI. Optional Where-is requests can send one camera photo through the separately configured Chalk gateway.

The production token endpoint is `https://feel-v1-voice.vercel.app/session`.
OpenAI Realtime uses `gpt-realtime-2.1` and Cedar with 24 kHz PCM audio.
The server retains the provider key and returns a five-minute client secret.
A live provider probe completed readiness speech, 40 seconds of streamed silent
PCM and a second readiness response without provider or send errors.
This does not verify microphone input, headset routing or recovery on the phone.
See [current migration evidence](evidence/v1-openai-voice/validation.txt).

Debug builds accept an explicit paired developer launch with
`FEEL_PROVISION_VOICE=1`, `FEEL_VOICE_ENDPOINT` and `FEEL_VOICE_ACCESS_TOKEN`.
Only the separate service token is supplied; never a provider API key. With devicectl,
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

## Voice wording

The assistant status control now lives as a 48-point icon in the top toolbar.
Its modal contains captions, recovery and pause/resume controls. The camera
center stays empty; automatic foreground listening remains unchanged.

OpenAI uses Cedar at its default speed. The prompt asks for result-first responses,
usually one sentence of 3–12 words, with one follow-up question only when needed.
Readiness is “I'm here.” Repeated introductions and offers to help are removed.
Proactive observations use normal distance units and relative sides, preserve
possible-door uncertainty and use past tense to acknowledge sample-to-speech
latency. Local fallback prefers the highest-quality installed English voice.

The [voice cases](evidence/v1-voice-polish/voice-cases.md) define expected behavior.
These changes do not claim measured improvement to live audio. The prompt controls
wording; provider voice selection controls the voice itself. Physical listening
evaluation remains necessary.

## Recovery and response ownership

The phone diagnostic captured a stopped audio engine on first playback. Playback
now restarts the existing graph only when its microphone format is unchanged;
a changed format triggers a complete reconnect. Explicit pause clears the graph.
Short microphone send stalls coalesce queued PCM with a one-second bound.

App announcements run outside conversational history with tools disabled. Every
manual response has a unique request identifier, so a late canceled announcement
cannot replace a newer user request. Debug diagnostics contain only bounded event
names and error categories, never credentials, microphone audio or transcripts.

## October 17 voice control completion

Voice now enables/disables arrows, requests directions without a V sign, stops
arrows independently of camera sensing, and plays an explicitly synthetic cue.
It also starts/stops local depth recording and chooses camera-video inclusion.
The assistant asks whether to include video when unspecified; that preference
cannot change during a recording. Startup is reported as pending until the
recorder reports progress. Camera recording never includes microphone audio.

Choosing another target, changing photo setup or losing tracking cancels an
older Where-is request. Delayed photos and answers cannot restore that target.
Repeated held-target direction reminders now respect automatic-update settings.
A muted assistant does not queue an unheard choice question or silently pick a
target in that choice path; the status explains how to resume spoken selection.

Automatic observations are acknowledged only after a completed response and
audio playback drain. Interrupted, expired or muted requests remain eligible
for a fresh retry. State-dependent loss/recovery messages are canceled if their
supporting state changes before playback. This is software evidence; hearing
quality and real headset behavior still require device acceptance.

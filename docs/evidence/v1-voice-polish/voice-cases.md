# Voice acceptance cases

These are target behaviors, not transcripts from a live OpenAI session.

| Input or event | Expected wording | Required grounding |
|---|---|---|
| Session becomes ready | I'm here. | Microphone started and session configuration acknowledged |
| Stop | Camera stopped. | stop tool returns success; assistant keeps listening |
| Find a chair | Searching for a chair. | find_target tool accepts the mode |
| No target | I haven't found it yet. | Fresh get_status with no target |
| Door candidate left, 1.24 m | A possible door was 1.2 meters to your left. | Current valid rectangle observation, not a confirmed door |
| EXIT sign ahead, 1 m | An exit sign was 1 meter ahead. | Current valid OCR target, no safe-route claim |
| Headphones removed | Headphones disconnected. Reconnect them to resume. | Actual route notification |
| Voice permission denied | Microphone access is off. Enable it in iPhone Settings. | Permission callback denied |
| Missing service setup | Voice needs setup. Open Assistant settings. | No valid configuration |

The deterministic observation helper and recovery strings are implemented. OpenAI
response wording is instructed, not guaranteed by unit tests. Verify live speech
for accuracy, brevity, natural pronunciation and interruption behavior after
provisioning. Default provider voice is Cedar at normal speed. A higher-quality
installed iOS English voice is preferred for local fallback; no voice is downloaded.

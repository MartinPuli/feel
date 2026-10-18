# FEEL

**Keep your ears. Feel the room.**

If you can't see, your ears are how you get around: traffic, footsteps, echoes, the person
you're talking to. Most AI tools for blind people add another voice to that. FEEL leaves your
ears free and puts the room in your palm instead.

A LiDAR iPhone reads the space ahead. A palm-sized puck shows it as **6 directions × 4
distances**, one raised pin per direction. Ask "where's the exit?" and a pin taps toward it.
FEEL shows you the room, and you decide where to go.

> FEEL is an experimental prototype for supervised indoor use. It is not a certified mobility
> aid and does not replace a cane or guide dog. See [what has been verified](#verification-status).

## Why another approach

| Common approach | Where it falls short |
|---|---|
| Camera → cloud model → spoken narration | Seconds of delay. It talks over the sounds you navigate by, and can confidently say "clear" when it isn't. |
| Distance sensor + vibration motor | One bit: "something is near." No direction, distance or *what*. |
| Devices that steer you | Handle the path straight ahead and decide for you. They can't find a goal across the room. |

FEEL's answer:

1. **A map, not a bit.** 24 pins encode direction and distance at once, read silently through touch.
2. **It finds goals.** "Where's the exit / a chair / the registration desk?" places the target in
   the room with LiDAR depth and taps its direction until you arrive.
3. **It works with your cane.** The cane covers the ground ahead; FEEL covers the rest of the room.
4. **Safe by design.** Obstacle sensing runs entirely on the phone. If the Bluetooth link goes
   quiet for 500 ms, every pin drops to neutral.
5. **It knows when it doesn't know.** The Where-is agent is evaluated on how often it claims to
   find a target that isn't there, and falls back to on-device detection without a connection.

## How it works

![FEEL at a glance](docs/diagrams/feel-system.svg)

1. **Sense.** ARKit scene depth on the iPhone keeps points 0.6–2.1 m above the calibrated floor,
   splits the camera's ±45° field into six 15° sectors, and takes the nearest range in each.
2. **Encode.** Each sector's range becomes a distance row. A selected target sets a highlight
   column. The phone sends a 9-byte Bluetooth packet ten times a second.
3. **Touch.** An ESP32 drives one servo per column. Each servo turns a cam shaft that raises
   exactly one of four pins. The highlighted column taps.

| Distance to nearest obstacle | Pin row (wrist → fingers) |
|---|---|
| under 0.9 m | 1 |
| 0.9–1.6 m | 2 |
| 1.6–2.5 m | 3 |
| 2.5–4.0 m | 4 |
| missing, invalid or beyond 4 m | none (column stays down) |

A column that stays down means *no pin request*, not *clear space*. The phone announces lost
tracking, stale depth and disconnection separately.

More figures: [sensing to pins](docs/diagrams/sensing-to-pins.svg),
[one Where-is request](docs/diagrams/where-is-path.svg),
[the evaluation loop](docs/diagrams/chalk-eval-loop.svg) and
[memory and venue knowledge](docs/diagrams/chalk-context.svg).

## Hardware

| Part | Spec |
|---|---|
| Phone | iPhone with LiDAR (developed on an iPhone 14 Pro Max), held landscape-left, rear camera forward |
| Controller | ESP32-WROOM (classic ESP32) with Bluetooth LE, powered over its own USB lead |
| Actuators | 6 × FEETECH FS0307 sub-micro servos (Pololu 3420): 4.8–6 V, 0.4–0.5 A stall each |
| Tactile display | 6 columns × 4 rows = 24 pins. One servo and one cam shaft per column, so one pin per column is up at a time |
| Servo power | 5 V / 4 A wall supply on a separate servo bus, 1000 µF bulk capacitor, ground shared with the ESP32 |
| Housing | 3D-printed PLA puck, chassis 100.5 × 92.5 × 26.7 mm, worn on the palm with a strap; ESP32 and wiring in a forearm pack tray |
| Pins | 4.2 mm pins in holes reamed to 4.37 mm (11/64″) |

The housing has seven column positions; the leftmost is left empty and GPIO32 is unused.
Wiring, left to right: GPIO33, 25, 26, 27, 14, 13 ([layout and wiring](docs/SIX-COLUMN-LAYOUT.md)).

The firmware currently assumes 175° servo travel over 650–2500 µs, based on user-observed
wider motion. FEETECH rates the FS0307 at 120° over 900–2100 µs, and our units' travel has not
been measured. [The travel test](docs/SERVO-TRAVEL-TEST.md) decides which cam shaft to print.

### Link and safety

- **Protocol:** BLE, 9-byte frame `[seq, 0, b1…b6, highlight]` at 10 Hz. Stale sensor results
  are dropped, never queued. Wire cases live in [`protocol/vectors.json`](protocol/vectors.json);
  policy in [PROTOCOL.md](docs/PROTOCOL.md).
- **Validation:** the firmware rejects malformed, duplicate and out-of-order packets atomically.
- **Watchdog:** after 500 ms without an accepted packet, or on disconnect, every column returns
  to a neutral gap. Reconnection starts neutral and waits for a fresh packet.
- **Output guard:** servo PWM is off by default. Production output builds only with each unit's
  measured pulse limits.
- **Known limit:** the puck has no position, force or current sensing, so it can't detect a
  jammed pin. See [known issues](docs/KNOWN-ISSUES.md).

## Cost

About **$95 in parts**, not counting the iPhone.

| Part | Qty | Unit | Total | Basis |
|---|---|---|---|---|
| FEETECH FS0307 servo | 6 | $9.35 | $56.10 | Pololu list price, 5+ units |
| ESP32-WROOM USB-C dev board | 1 | ~$8 | ~$8 | Typical retail range $5–12 |
| 5 V / 4 A switching supply | 1 | $14.95 | $14.95 | Adafruit list price |
| Barrel-to-screw-terminal adapter | 1 | ~$2 | ~$2 | Estimate |
| 1000 µF capacitor, 22 AWG wire, perfboard, headers | — | — | ~$3 | Estimate |
| PLA filament, 8 printed parts | ≤ 210 g | $20/kg | ≤ $5 | Upper bound: every part solid, from CAD volumes |
| Strap, foam, M3 screws | — | — | ~$5 | Estimate |
| **Total** | | | **≈ $94** | |

Prices checked October 17, 2026, before shipping and tax. Not included: the LiDAR iPhone, a
spare servo, a battery bank for walking use ([power options](BATTERY.md)), and printer time.
For context, commercial refreshable braille displays, the closest pin-based devices, start
around $1,500, though they display text rather than space.
Sources: [Pololu FS0307](https://www.pololu.com/product/3420),
[Adafruit 5 V 4 A supply](https://www.adafruit.com/product/1466),
[braille display buyer's guide](https://www.disabilityworld.org/articles/refreshable-braille-displays-buyers-guide/).

## Where Chalk is used

FEEL's voice assistant has a `where_is` tool. "Where is the registration desk?" sends one camera
photo and the question through **Chalk's Model Gateway** to a vision model. The phone places the
answer in the room with LiDAR depth, and the puck taps toward it until you arrive.

- **Evaluations.** Chalk Evaluations score the tool on labeled venue photos: pointing accuracy,
  well-formed replies, and the **false-found rate**, how often it claims to see something that
  isn't there. For a blind user, a confident wrong answer is worse than none, so this is the
  metric that decides which model ships. Every report gives its denominators, per-case timing and
  usage, under one 12 s deadline shared with the phone.
- **Fallback.** Without Chalk settings, or when the gateway can't be reached, `where_is` falls
  back to the phone's own Vision and Core ML detection: EXIT signs, door candidates, people,
  chairs and common objects.
- **Venue knowledge.** Downloadable venue packs answer questions offline from reviewed sources,
  with expiry and temporary restrictions. The repo includes a pack for the David Rubenstein
  Treehouse, built only from what reviewed public pages state.
- **Context.** Chalk features keep confirmed finds, venue packs and shared room anchors.

Voice runs on OpenAI Realtime directly; audio does not pass through Chalk.
Setup, evaluation commands and current status: [chalk/README.md](chalk/README.md).

## Verification status

What has run, and what hasn't:

- **Passes:** software checks on the Swift core, C++ controller, cross-layer replay and CAD
  geometry. Exact counts and commits are in [release status](docs/RELEASE-STATUS.md).
- **Observed on hardware:** one servo moving under phone control.
- **Not yet measured:** six-servo travel and mechanics, servo supply under load, sensing
  accuracy, end-to-end latency, hosted evaluation results, and testing with blind users.

The [production replay](validation/production/README.md) runs the real Swift encoder and C++
controller on recorded and synthetic scenes. It is labeled as simulation and is not a recording
of real pins. [Grid walk](docs/GRID-WALK.md) tests the guidance on the phone screen without a puck.

## Run it

Requirements: Swift 5.9+ (6.1.3 used locally), a C++11 compiler, Python 3.10+, OpenSCAD
2021.01+ and PlatformIO 6.1.18. The iOS apps need macOS with Xcode and XcodeGen. Linux compiles
the same Swift core and C++ controller, but not the Apple frameworks.

```sh
sh ios/scripts/test_portable.sh
sh firmware/test/run_host_tests.sh
sh validation/adapters/run_contract_tests.sh
pio run -j 2 --project-dir firmware
sh cad/build.sh
python3 cad/tools/check_stl.py stl/*/*.stl
python3 cad/tools/cam_sim.py
python3 scripts/run_v1_checks.py   # exits 0 pass, 1 fail, 2 blocked or not run
```

Open `.artifacts/production/index.html` for the recorded offline replay.

On a Mac:

```sh
python3 scripts/fetch_model.py   # Apple Core ML model, pinned revision and SHA-256
bash scripts/check_ios.sh        # simulator tests and unsigned device builds
cd ios
xcodegen generate
open Lantern.xcodeproj
```

Select your signing team and a LiDAR iPhone in Xcode. The simulator can't show LiDAR, Bluetooth,
Nearby Interaction, tactile usability or mechanical behavior.

Hardware: [Mac and ESP32 setup](docs/SETUP-MAC-ESP32.md), [bring-up](docs/HARDWARE-BRINGUP.md),
[calibration](docs/CALIBRATION.md) and [app and servo test](docs/TEST-V1.md).

## Repository

| Path | Contents |
|---|---|
| [`ios/`](ios/README.md) | FEEL iPhone app (target `Lantern`), Beacon companion app, portable Swift core and tests |
| [`firmware/`](firmware/README.md) | Shared C++ controller, ESP32 Bluetooth adapter, host simulator and tests |
| [`cad/`](cad/README.md) | Parametric OpenSCAD puck, cams, pins, forearm pack, mesh and cam checks |
| [`chalk/`](chalk/README.md) | Chalk gateway client, evaluations, features and venue packs |
| [`protocol/`](protocol/vectors.json) | Normative packet vectors, the shared Where-is prompt and venue packs |
| [`services/voice-token/`](services/voice-token) | Small service that issues short-lived voice credentials |
| [`validation/`](validation/production/README.md) | Cross-layer replay of the real Swift and C++ code |
| [`web/`](web) | FEEL site with `/replay` |

[Codebase guide](docs/CODEBASE.md) · [demo script](docs/DEMO.md) · [Devpost draft](docs/DEVPOST.md)

## Provenance

The FEEL concept and its design handoff ([HANDOFF-v7.md](HANDOFF-v7.md)) predate this
repository. No original app, firmware or CAD source was available, so this code is a new
implementation written from that handoff. Third-party model weights keep their own source,
hash and license. See [eligibility and disclosure](docs/ELIGIBILITY.md).

# Offline command integration

## Design and version boundary

V4 adds local-first command understanding on the iPhone, using V2 spatial-memory
operations and V3 command, tracking and lifecycle guards. V1 `main`, the V2 and V3
release branches, firmware, BLE encoding, GPIO assignments and calibration are
not modified by this update. This is integration within V4, not backporting voice
features into the V2 release.

The first implementation is a bounded English/Spanish phrase parser, not a trained
language model. Recognized commands execute locally even when cloud understanding
is enabled. Unsupported phrases may go to Chalk only with the existing opt-in and
sharing consent. A network failure never becomes a guessed destination or replayed
movement. The user can continue with supported local commands; retrying cloud is
explicit. Typed input works without speech services. Offline speech itself still
requires on-device recognition support for the selected language and device.

## Physical output ownership

Command text -> validated intent -> existing memory/finder operation -> current
local perception/pose -> existing tactile encoder -> nine-byte Bluetooth packet ->
ESP32 controller -> calibrated servo PWM.

The phone sends seven band selections and a highlight, not arbitrary GPIO numbers
or pulse widths. The classic seven-servo configuration uses GPIO
32, 33, 25, 26, 27, 14, 13. The separate single-servo live adapter maps the center
column to GPIO32; it is not the seven-servo wiring map. Existing timeout, neutral,
tracking, output-enable and calibration requirements remain authoritative.

## Next model milestone

A future local intent model should run on the iPhone behind the same intent
interface. Before shipping it: choose a model/license compatible with iPhone 14
Pro Max, measure memory and p50/p95 latency on that device, evaluate held-out EN/ES
phrases including ambiguity and negation, require exact known destination grounding,
and abstain on uncertain requests. Preserve the explicit Stop path and never let
model output select pins, pulses or bypass tracking guards. Do not call this first
parser a local LLM or claim arbitrary conversational understanding.

## Physical acceptance check

1. With Bluetooth connected, disable Wi-Fi and cellular data but leave Bluetooth on.
   Start Live and establish normal tracking; save a place using the existing UI.
2. Enter a supported local recall command for that exact place. Verify app selection
   and virtual puck; actual tactile output requires the already validated hardware
   configuration. Use Stop and confirm neutral behavior.
3. Re-enable networking and explicitly retry Chalk. Test an unsupported local phrase,
   then Stop while it is pending: no late response may restart guidance.

Simulator tests cannot prove physical servo movement, Bluetooth reliability,
tracking accuracy or safe navigation. Live Chalk access and device validation
remain separate acceptance gates.

## Supported examples

Choose the matching input language in the app. Place names must match a current
saved destination; unknown or duplicate names do not select an arbitrary place.

| English | Spanish | Operation |
| --- | --- | --- |
| `take me to Entrance` | `llevame a Entrada` | Recall an existing place |
| `remember this place as Entrance` | `guardá este lugar como Entrada` | Save the current tracked position |
| `take me back` | `volvé` | Return to the explicitly set return point |
| `show my places` | `mostrame mis lugares` | List saved places |
| `help me find chair` | `ayudame a buscar silla` | Select existing finder |
| `please stop now!` | `por favor detenete!` | Stop locally |

Existing canonical V3 commands remain supported. Unknown sentences are not fuzzy
matched to a destination. A network outage does not execute the failed sentence;
it enables a visible offline state for subsequent local commands. "Try cloud on
next command" permits a future request without replaying anything.

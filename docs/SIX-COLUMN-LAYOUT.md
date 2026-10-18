# Six-column FEEL layout

User-selected October 17, 2026: the original leftmost column is not used.
GPIO32 has no servo connection. There are six active servos and 24 tactile pins.
Keep the existing physical positions and angle settings.

| Physical column, left to right | Wire slot | White signal wire | Camera bearing |
|---|---|---|---|
| 1 | 1 | GPIO33 | −45° to −30° |
| 2 | 2 | GPIO25 | −30° to −15° |
| 3 | 3 | GPIO26 | −15° to 0° |
| 4 | 4 | GPIO27 | 0° to 15° |
| 5 | 5 | GPIO14 | 15° to 30° |
| 6 | 6 | GPIO13 | 30° to 45° |

Internal boundaries select the column on the right. Both outside endpoints are
included. The complete camera field is redistributed; left-side detections are
not discarded. There is no single middle column in a six-column layout.

## Compatibility

The BLE service and nine-byte frame stay unchanged: `[seq,0,b1,b2,b3,b4,b5,b6,hl]`.
The app uses slots1–6, and the hardware adapter independently disables slot0.
Raw decoder tests can still use historical seven-slot packets; this does not
re-enable a seventh physical output. Old phone builds are byte-compatible but
must be updated for correct six-sector coverage and UI.

The same mapping applies to V1 perception, V2 memory, V3 advanced guidance and
V4 Chalk paths. Versions remain separate; this update does not merge their features.
Default PWM-off and measured-production guards remain in place. The opt-in live
profile is `esp32-six-live`; its experimental pulse settings are unchanged.
Existing device firmware must be replaced before GPIO32 is considered disabled.

## Wiring

Unplug power before changing wiring. Leave GPIO32 disconnected. Connect each
white signal wire according to the table. Red servo wires join external +5V;
black servo wires join external negative, also connected to ESP32 GND. Power
the ESP32 through USB. Do not carry the combined servo current through ESP32
pins or undersized breadboard contacts. Use suitable power distribution.

An optional correctly polarized 1000µF capacitor across servo supply near the
distribution point can help brief dips; it does not replace adequate wiring or
supply capacity. Existing seven-position CAD may be used with the original
leftmost position empty; this is not a redesigned or newly validated housing.

## Acceptance

1. Confirm six-column app display and firmware status without GPIO32 output.
2. Move a target across the whole view; confirm six independent outputs in order.
3. Test Stop, loss of tracking, Bluetooth disconnect and 500ms packet timeout.

Software test results belong in the release evidence. Physical mapping, supply
under load, return, travel and real phone integration remain unverified until
observed. A requested servo angle is not measured physical rotation.

> Current layout — October 17: six active columns. GPIO32 / wire slot0 is unused.
> Left to right: GPIO33,25,26,27,14,13 (wire slots1–6). The nine-byte packet
> remains unchanged; the app reserves b0=0 and divides the whole ±45° field into
> six sectors. Existing angle settings are unchanged. See [six-column guide](SIX-COLUMN-LAYOUT.md).

# Seven-servo live configuration

October17,2026. The user explicitly requested enabling all seven outputs with
the current connected-servo alignment. Profile: `esp32-seven-live`; BLE name:
**FEEL Puck**. This is an opt-in live hardware profile, not the measured-record
`esp32-production` profile. No measurement record is manufactured or bypassed
inside that production profile. Default build environments still keep PWM off.

## Wiring and app mapping

Each column has its own signal wire and follows the same-index app sector.
Columns below are numbered1–7 for the user (protocol indices0–6).

| Column, left to right when worn | ESP32 GPIO |
|---|---:|
| 1 | 32 |
| 2 | 33 |
| 3 | 25 |
| 4, center | 26 |
| 5 | 27 |
| 6 | 14 |
| 7 | 13 |

The previous single-servo profile routed center sector3 toGPIO32. This profile
routes center sector3 toGPIO26. Do not connect multiple signal wires to one
breadboard row or signal rail: that duplicates one signal across servos.
Use the external servo supply and common ground; seven-servo current must not
pass through the ESP32 or undersized breadboard rails.

## Requested motion

Base selected-pin angles are0/58/116/174°, with +159µs alignment trim on every
channel. Output pulses at zero calibration are809/1422/2035/2648µs,
approximately15/73/131/189° on the assumed scale.189° is not a measured angle.
No-pin pulses are1116/1729/2342µs, approximately44/102/160°, selected by the
nearest gap to the previous band; ties go lower. Highlight uses the same
controller timing and trimmed pulses. Per-channel stored offsets apply first.

All channels remain detached at boot and until fresh valid live commands.
Fresh zero-band packets command empty gaps. Disconnect, serialSTOP and500ms
without a valid fresh packet detach all outputs. Detachment is not power
isolation and does not establish physical pin return. Serial motion/calibration
commands are unavailable in this live profile. SerialSTOP can be followed by
new phone packets; use app Stop/disconnect or remove servo power to end testing.

The user reports successful motion on the current servo. This does not verify
seven servo ranges,2648µs mechanical clearance, total current, wiring or pin
return. Live packets may hold an endpoint. Stop and remove servo power for
straining, buzzing, heat or jamming. The normal production measurement gate and
all physical release checks remain separate.

## Verification

Host tests must verify independent columns, exact selected/neutral pulse maps,
all-zero return, input rejection, boot/disconnect/watchdog detachment, and
compile-time isolation from single-servo and measured-production profiles.
Build and upload outcomes are recorded in the implementation evidence. A host
PASS does not establish seven-unit physical acceptance.

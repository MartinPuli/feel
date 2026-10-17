# FEEL offline specification model — SIMULATION ONLY

This is newly written validation tooling based on the supplied `HANDOFF-v7.md`.
The supplied GitHub repository had no production source when inspected. Therefore
this does **not** reuse or validate the missing iOS encoder, ESP32 decoder, CAD,
or servo implementation. A passing result here does not clear the V2 software
gate and does not verify physical hardware.

## Run it

From the repository root, with Python 3.9 or later (standard library only):

```sh
python3 -m unittest discover -s validation/tests -v
python3 validation/run_scenarios.py --output .artifacts/simulation
```

Open `.artifacts/simulation/index.html` in a browser. It works offline. Choose a
scenario, use the step slider or Previous / Next buttons, and inspect the exact
packet, expected result, logical pin requests, and nominal command phases.
`report.json` contains the same trace for tools. The HTML only renders that trace;
it does not implement a second packet decoder or model.

The runner returns 0 only when every fixture expectation passes. Assertion
failures return 1. Invalid / empty fixtures raise an error and do not create a new
report. Empty suites, empty event lists, empty or recursively empty expectations,
duplicate scenario IDs, and nonmonotonic simulation time are rejected.

Observed test result after implementation: **51 unit tests; 18 scenarios / 77
asserted trace steps PASS**. These counts describe this model only. The fixtures
use seed `20261016`; seeded loss decisions are committed and independently
checked against that seed. Output has no wall-clock fields, so repeated runs are
byte deterministic. The report includes the SHA-256 of the scenario file.

## What is modeled

- Strict application payload `[seq, b0, b1, b2, b3, b4, b5, b6, hl]`: exactly nine
  bytes; bands 0–4; highlight 0–6 or 255. Logical output has at most one selected
  pin per column. That invariant does not demonstrate physical exclusivity.
- A receipt watchdog, disconnect state, sequence diagnostics and optional
  ordering policy. There is no simulated BLE stack, radio, or network latency.
- Nominal cam command phases: request a gap, request a band, assume a hold after
  a configurable elapsed time. No continuous angular travel is simulated. A servo
  moving between these requested angles could pass through other lobes.
- Revised 120° design band angles 0° / 40° / 80° / 120°, derived gap midpoints, and a nominal
  13° highlight dip hint. **Highlight is a tap request only; tap cadence,
  actuation, and physical tapping are not simulated.**
- Already-sectorized synthetic depth, target bearing, tracking and freshness
  inputs. Synthetic pose is retained as **metadata only**. There is no camera
  transform, depth projection, confidence filter, CoreML detector, UWB, or ARKit
  behavior behind these inputs.

No code in this directory opens Bluetooth, serial, GPIO, network, or sensor
connections. No command here can flash or move the actual hardware.

## Known contract versus explicit reference choices

| Topic | Handoff evidence | Choice in this model, pending recovered source |
|---|---|---|
| Packet | Nine bytes, seven bands 0–4, `hl` 0–6/255 | Reject invalid shape/range; do not refresh watchdog on rejection |
| Failsafe | 500 ms | Clear logical requests at **age >= 500 ms**, measured from last accepted receipt; `ModelConfig.timeout_ms` can be varied for tests |
| Sequence | One byte | Default `observe` accepts valid duplicates and backward/large-gap traffic while labeling it; no claimed production ordering policy |
| Optional ordering | Not specified | `forward_only` accepts modulo delta 1–127; rejects 0 and 128–255; resets history after timeout/disconnect. It cannot prove absolute freshness |
| Disconnect | Not specified | Immediately clear requests; reconnect waits for a fresh packet |
| Neutral | Midpoint gaps between adjacent bands | Nearest gap to the former band; tie chooses lower; startup assumes 20°. These are unmeasured model commands, not calibration values |
| Motion timing | Not specified | `gap_ms=40`, `settle_ms=120`; configurable **unmeasured illustrations**. `hold_assumed` is never a measured position |
| Highlight | A selected column taps; 13° toward its gap | Display request + nominal dip angle, without a tap scheduler. `hl` on an empty band is wire-legal but does not invent a selected pin |
| Distance bands | 0.3–0.9 / 0.9–1.6 / 1.6–2.5 / 2.5–4 m | Half-open intermediate ranges; 4 m included; positive <0.3 m saturates to band 1 by default (`close_policy="none"` is available) |
| Missing/invalid depth | Not specified | Null, NaN, infinite, nonpositive or >4 m map to 0; this is not proof of free space |
| Freshness and tracking | Not specified | Synthetic loss of tracking or depth age >250 ms emits all zeros/no highlight; stale targets >250 ms ignored. Both age limits are configurable |
| Sector geometry | Seven columns; full geometry unavailable | Synthetic bearing FOV 90°, equal-width sectors, endpoints included; configurable `fov_degrees`. The physical left/right mapping remains unknown |
| Conflicting targets | Not specified | More than one current in-FOV candidate suppresses highlight; no target replaces obstacle bands |

These choices must be compared with the recovered `docs/PROTOCOL.md` and real
code. Do not silently copy them into production or treat them as a mechanical
safety specification.

## Failure scenarios and deliberate limitations

The 18 scenarios cover startup, band requests, nominal gap/hold/neutral commands,
the exact timeout edge, invalid length/bands/highlight, high-bit corruption,
sequence rollover, short gaps, duplicates/reordering, optional ordering rules,
seeded drops, disconnect/reconnect, synthetic tracking loss, stale depth,
disappearing/conflicting targets, delayed target results, distance edges, missing
depth and empty-column highlights. Expected nominal command phases and angles
are explicitly asserted; a regression test injects an always-neutral/999° model
and verifies the replay fails.

Important packet limitations are demonstrated rather than hidden:

1. **There is no application checksum.** A corruption that leaves every byte
   legal can change a band undetected. The legal-byte-corruption scenario passes
   precisely when it demonstrates this limitation. BLE link behavior is outside
   this model.
2. **There is no timestamp or sender boot ID.** One sequence byte cannot
   distinguish a newly wrapped value from an old packet 256 sequence values ago.
   Half-range ordering also cannot distinguish reordering from a large forward
   gap.
3. **There is no sensor-health field.** All-zero bands can mean clear space,
   unknown depth, stopped sensing, tracking loss, or a timeout. The replay has
   separate synthetic metadata, but that metadata is not in the wire packet.
4. **Commanded neutral is not measured neutral.** Nothing here proves servo
   movement, safe transitions, foam return, pin exclusivity during motion,
   mechanical clearances, current draw, torque, or response time.

## Files and later production integration

- `feel_model.py`: strict packet codec, reference receiver and nominal command
  phases, explicitly synthetic upstream policies.
- `fixtures/protocol_vectors.json`: **5 valid and 8 invalid** hand-authored golden
  vectors with exact bytes and expected fields.
- `fixtures/scenarios.json`: fixed inputs, hand-authored expectations, assumptions,
  provenance, and seed.
- `run_scenarios.py`: fixture validation, assertions, JSON output and offline HTML
  trace renderer.
- `tests/test_model.py`: contract/range/time/fault/fixture regressions, including
  exhaustive values in each band-byte position and all highlight/sequence bytes.

Once the real source is restored, add separate adapters that invoke the actual
Swift encoder and C++ decoder against `protocol_vectors.json`; compare rejection
semantics and byte-for-byte output. Do not replace this missing evidence with
another independent codec. Reconcile source differences explicitly, then run the
original build and tests before proposing V2 ready. Use physical measurements and
tests to replace command-timing assumptions; never infer them from this replay.

Python test framework reference: [official unittest documentation](https://docs.python.org/3/library/unittest.html).

# Compiled production replay

`run.py` starts **the real FeelCore Swift CLI** and **the real firmware C++
controller CLI**. It does not reimplement either codec. It asserts golden bytes,
malformed packets, seeded contract samples, distance boundaries, target bearings,
stale depth, tracking loss, sequence wrap/reordering, disconnect and the exact
watchdog boundary. Invalid packets must leave outputs unchanged.

```sh
sh validation/adapters/run_contract_tests.sh
# .artifacts/production/report.json and index.html
```

The HTML renders the asserted trace. Its pin grid displays requested bands. A
separate speed-limited motor estimate uses an **unmeasured 300°/s** and an injected
jam to demonstrate why commanded neutral does not prove physical return. It is
not a torque/friction, BLE-radio, image-recognition, or real ARKit simulation.

`protocol/vectors.json` is the normative byte contract; the earlier Python
reference model remains separately labeled under `validation/README.md`.

The test exits nonzero on an assertion or missing executable. Empty vectors and
empty evidence cannot pass. A bounded subprocess wait prevents hung adapters from
producing a false pass. Neither tool connects to a board, serial port or phone.

Known limitations are deliberately demonstrated: a legal-byte corruption is
undetectable; a sensorless controller cannot detect a stalled motor; nine bytes
have no sensor-health, timestamp, session identity, or application checksum.

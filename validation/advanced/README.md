# V3 production replay

This harness sends JSON operations into the compiled production Swift core/CLI,
then passes the resulting nine-byte packets to the compiled production C++
controller. It checks actual replies and controller states. The HTML viewer only
replays the captured results; it does not reimplement guidance or the protocol.

```sh
swift build -j 2 --package-path ios/Shared/FeelCore
sh firmware/test/run_host_tests.sh
python3 validation/advanced/run.py
# Open .artifacts/advanced/index.html
```

The consolidated command is `python3 scripts/run_advanced_checks.py`. It also
runs the V1 and V2 replays and attempts the native Apple build/test gate.
Exit0 means every gate passed; exit1 means failure; exit2 means a gate is blocked.
Read the report before interpreting its status.

## Covered behavior

- Final English/Spanish voice intents, unsupported/partial/malformed commands.
- Bounded versioned map archives, multiple places and Return point; rejected
  imports leave current state unchanged.
- Map/session/anchor identity, fresh upright poses, prior relocalizing state,
  continuous settling, missing observations, timeout and backwards clocks.
- Restored places remain inactive until explicitly recalled. Tracking loss
  neutralizes the resulting packet; a new session cancels an old restore.
- Standard, reduced and automatic target cadence, including quiet-first timing,
  close-obstacle hysteresis, source changes and sequence rollover. Every obstacle
  band and sequence byte must be preserved.
- Production firmware tap angles, watchdog and disconnect behavior.

The fixtures are deterministic. A reported seed identifies the scenario set;
the harness does not claim statistical sampling. Speech text, map bytes,
relocalization observations, phone poses and motor motion are **synthetic**.
The map fixture is deliberately not an ARWorldMap. Native Apple tests cover
invalid-map rejection, local file envelopes and a generated QR image separately. Neither test
proves a real environment can be relocalized or a real camera can detect a code.

The simulated motor has an assumed 300°/s slew rate, no measured torque, current,
force or jam sensor. Real servos, radio links, user comfort and mechanics remain
unverified. Output files always carry `physical_hardware: NOT VERIFIED`.

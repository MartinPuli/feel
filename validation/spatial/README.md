# V2 spatial-memory production replay

Run after compiling the same `FeelCore` package used by the app and the shared
C++ firmware controller:

```sh
sh ios/scripts/test_portable.sh
swift build -j 2 --package-path ios/Shared/FeelCore
sh firmware/test/run_host_tests.sh
python3 validation/production/run.py
python3 validation/spatial/run.py
# Open .artifacts/spatial/index.html
python3 scripts/run_spatial_checks.py
```

The replay keeps a real Swift `SpatialMemoryManager` alive over line-oriented
JSON commands. It remembers two places and a return point, moves/rotates the
synthetic camera, requests recall, then passes the exact nine bytes to the real
C++ controller. It checks translation, 90°/180° rotation, all six internal sector
edges on each side, FOV endpoints, out-of-view/behind/far/different-level/arrival,
nearer obstacles, tracking and freshness faults, session mismatch/reset/end,
selection, rename/delete, rejected mutations, Return, Stop and the watchdog.

The first executed version passed 358 assertions across 43 firmware states. The
final current counts are recorded in `docs/evidence/v2/`; this README does not
substitute for a fresh test run. V1's separate production contract is rerun too.

The viewer is a recording of those production outputs. Inputs and motor positions
are synthetic; there is no BLE radio, real AR session, location measurement,
physical servo, force, jam feedback or tactile subject. Neutral does not mean
clear space. Recall is direction toward a saved phone position, not route planning.

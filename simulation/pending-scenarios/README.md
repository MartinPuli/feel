# Failing movement acceptance candidates

These three source scenes from `origin/movement-simulation-tests` were relabelled by the current six-sector `geometry_labels.py` before replay. Every result is deterministic, but their unchanged 95% per-window agreement gate FAILS. They remain separate from the default passing scenario set to make their unresolved acceptance status explicit; they are **not verified production coverage**.

Run `python3 simulation/run.py simulation/pending-scenarios/*.json --repeat 2 --no-web --no-build`. It is expected to exit nonzero until the latency requirement is resolved. No known-issue waiver or lower threshold was added.

- `person-away-centre.json`: at 1.75 s, slots 3/4 still show band 1 rather than 2; at 3.35 s they show 2 rather than 3. Window agreements 83.3% and90%.
- `person-away-left.json`: slots 2 at 1.25–1.35 s and 1 at 1.35 s retain band 1 rather than 2. Window agreements 77.8% and80%.
- `person-away-right.json`: symmetric slots 5/6, same agreements.

The production `SectorFilter` deliberately requires a 0.1 m farther-range margin plus four agreeing frames. At 0.45 m/s the margin adds about 0.22 s and four 10 Hz frames about 0.3 s, exceeding the geometry generator's 0.35 s transition trim. Existing `SectorFilterTests.testFartherBandNeedsFourFramesAndMargin` verifies that policy. Observed mismatches are conservative nearer-band persistence, with no missed obstacle, false-clear or reserved-slot activation in these fixtures. Treat this as a P2 tactile latency/product acceptance question, not evidence that the filter violates its implemented contract. Real user testing must decide whether that lag is acceptable. Do not change margins or thresholds solely to turn this report green.

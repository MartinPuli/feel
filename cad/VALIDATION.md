# CAD validation evidence — 120° FS0307 redesign

Executed 2026-10-16 on the Mac with official OpenSCAD 2026.10.15, native Apple Silicon. This validates software geometry only. No print, real servo travel, force, foam return or tactile test is claimed. The prior 175° evidence is superseded for this branch.

| Check actually executed | Result | Evidence |
|---|---|---|
| `sh cad/build.sh` | 24/24 real STL exports passed | `evidence/full-build.log`, `../stl/manifest.json` |
| `check_stl.py stl/test/*.stl stl/puck/*.stl` | 24/24 closed oriented meshes, one body, positive volume, on Z=0 | `evidence/mesh-checks.json` and `.log` |
| `cam_sim.py --step 0.1` | 80/80 checks; A/H/G, band/gap/tap contact and 0–120° sweep at 0.1° | `evidence/cam-simulation.json`, `.log`, `cam-lifts.csv` |
| `unittest discover -s cad/test -v` | 15/15 tests | `evidence/tool-tests.log` |
| Selected nominal envelope probe | PASS; oversized servo rejected by regression test | `evidence/nominal-fit.log`, `../stl/pin-lengths.csv` |
| `--print-ready` without measurements | Correctly blocked, exit 2 | Automated test |
| Concurrent export writer | Correctly blocked, exit 2 | Automated test |
| Offline WebGL packaging / JS syntax | Rebuilt 12 layers; syntax PASS | `viewer/mesh_data.js`, `viewer/viewer.js` |
| OpenSCAD assembly PNG | Rendered and visually inspected; no fit proof | `evidence/geometry-preview.png` |
| Browser interaction | NOT RERUN for this mesh revision | Earlier baseline results are not evidence for this revision |
| Any physical print / P1–P5 / real servo | NOT VERIFIED | Measurements still required |

The new band centers are [0,40,80,120]°, neutral gaps [20,60,100]°, and taps [13,27,67,107]°. A 12° lobe half-width preserves the original 2 mm stroke with the original 0.6 mm flat foot / 30° conical follower. All four selected bands reach 2 mm; all neutral gaps remain within 0.03 mm of rest; no two pins exceed 0.12 mm simultaneously in the sampled sweep. Those thresholds are unchanged. A/H/G tap drops are approximately 1.059 / 0.985 / 1.249 mm, within the unchanged 0.65–1.4 mm acceptance interval. Contact includes polygon edge interiors and finite-foot broadening, not only radial height.

The negative regression exports the actual old 24°-wide profile at the new centers: both neighboring pins lift over 0.8 mm at the 20° gap. This establishes why changing only servo angles is insufficient. A 14° lobe also fails the strict neutral requirement for A/H in exploratory calculations. The chosen 12° profile makes the flanks steeper: required torque, lateral forces, jamming, wear and printing sensitivity remain unmeasured. No force model or physical suitability claim follows from this geometry result.

The output manifest records actual validated files and hashes. CAD build scripts reject warnings and use a process lock. Closed meshes and Z=0 contact do not prove support-free printing. The shaft lobes still require slicer support review.

Physical blockers remain: actual servo voltage variant and safe endpoints; unloaded and loaded usable 120° travel; unmeasured case/horn/ear/spline; C3 is only a smooth-bore coupon; thin-guide stiffness; 0.282 mm cone-guide and 0.1 mm collar-guide nominal clearances; foam load/return at 20–60% compression; coupling retention, power integrity, comfort and tactile recognition. No full assembly collision freedom is claimed. Repeat manual P1–P5 before powered integration.

Preview command: `QT_QPA_PLATFORM=offscreen openscad --render --imgsize 1200,900 --viewall --autocenter -o cad/evidence/geometry-preview.png cad/viewer.scad`. It shows the current static 40° assembly and forearm tray; it is not a dynamic contact simulation.

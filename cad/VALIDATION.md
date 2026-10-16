# CAD validation evidence — greenfield V1

This validates software-generated geometry, not a printed, powered or tactile device. The authoritative design is `params.scad` plus the OpenSCAD sources. No original CAD was supplied.

| Check actually executed | Result | Evidence |
|---|---|---|
| `sh cad/build.sh` | 24/24 real STL exports passed | `evidence/full-build.log`, `../stl/manifest.json` |
| `check_stl.py stl/test/*.stl stl/puck/*.stl` | 24/24 closed oriented meshes, one body, positive volume, on Z=0 | `evidence/mesh-checks.json` and `.log` |
| `cam_sim.py` | 78/78 ideal geometric checks; A/H/G, bands/gaps, real firmware tap angles, 0.5° sweep | `evidence/cam-simulation.json`, `.log`, `cam-lifts.csv` |
| `unittest discover -s cad/test -v` | 13/13 tests | `evidence/tool-tests.log` |
| Selected nominal envelope probe | Pass; rejects a deliberately oversized servo | `../stl/nominal-fit.log`, `../stl/pin-lengths.csv` |
| `sh cad/build.sh --print-ready` without measurements | Correctly blocked, exit 2 | Covered by automated test |
| Concurrent export to one output directory | Correctly blocked by process lock, exit 2 | Covered by automated test |
| Actual STL PNG review | Rendered and visually inspected | `evidence/geometry-preview.png` |
| Offline WebGL preview packaging / JS syntax | Passed packaging and `node --check` | `viewer/index.html`, `viewer/viewer.js`, `viewer/mesh_data.js` |
| Browser interaction / GPU rendering | PASS in root integration: 12 layers, WebGL, explode/reset and mobile layout | Root screenshot `.artifacts/cad-viewer.png` |
| Any physical print / P1–P5 / real servo | NOT VERIFIED | Hardware unavailable |

The tests include negative cases: missing/inverted STL faces, floating and disconnected meshes, empty geometry, finite conical follower contact along an edge, changed cam band orientation, oversized nominal servo, closed print gate, and competing writers. They do not simulate foam, friction, force, servo or skin response.

Review fixes included a nominal servo/wrist collision (internal grid moved toward fingers), a tangent cut creating a nonmanifold C2 coupling, a zero-area triangulation in aligned face bores, and testing the wrong band-3 tap direction (now 138°, toward nearest 146° gap). The lower guide/collar were redesigned to provide 4→2 mm foam space: a 5 mm stack still requires 20→60% compression and physical return/load measurements. Single 2 mm foam would leave a return dead zone and is not recommended.

The final output manifest snapshots the actual checked files. OpenSCAD may order equivalent binary facets differently between exports; compare regenerated files via fresh validation, not an expectation of identical byte hashes across arbitrary renders. Fast builds are isolated under `stl/fast/`. Full output builds now have a process lock and unique temporary names. Do not run a full build while another task is modifying CAD sources.

Physical blockers remain: FS0307's manufacturer-listed 120° travel versus the required 175°; actual voltage variant; unmeasured case/horn/ear/spline; C3 is only a smooth-bore coupon; thin-guide stiffness; 0.282 mm cone-guide and 0.1 mm collar-guide nominal clearances; foam load/return, jamming, retained coupling torque, power integrity, fit and tactile recognition. No claim of full assembly collision freedom is made.

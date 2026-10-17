# Pin Puck production CAD

Parametric OpenSCAD rebuilt from [CAD.md](../../CAD.md). It is kept separate from the greenfield `cad/` model, whose numbers are different and unmeasured. Neither tree replaces the other.

| File | Contents |
|---|---|
| `params.scad` | Every parameter in CAD.md §2, with derived values written as formulas |
| `lib.scad` | One module per part (§3), plus the servo-body and horn check models |
| `puck.scad` | Part selector: `-D part="chassis"` and so on, plus `assembly`, `derived` and the `x_*` checks |
| `verify.py` | Exports every deliverable and runs the §5 checks. Writes `evidence/verify.{log,json}` |

```sh
python3 cad/production/verify.py                     # export to stl/production/ and verify (~15 s)
openscad --backend Manifold -D 'part="shaft3"' -o shaft3.stl cad/production/puck.scad
openscad -D 'part="assembly"' -D angle=58 cad/production/puck.scad   # view, puck frame
```

STLs go to `stl/production/`, which is gitignored. Print orientation is the orientation the files are exported in. Slicer settings are in CAD.md §4.

## Verification (2026-10-16, OpenSCAD 2026.09.23, Manifold)

These checks cover geometry only. Nothing has been printed, fitted or measured.

- **Derived values:** all 34 match CAD.md §2. `crown_R` computes to 1019.72.
- **Mesh:** all 8 STLs pass. Each is one body, closed and consistently oriented when vertices are welded exactly, with positive volume, min z = 0, and a bounding box within 0.047 mm of the table.
- **Collision sweep:** passes. All 75 intersections are empty: 4 shaft pairs × 9 angles × 2 shaft variants, plus 3 servo pairs.
- **Horn insertion:** passes. All 10 offsets are empty for both shafts. Full insertion leaves only coincident faces, at 6e-15 mm³.
- **Cam, `shaft`:** passes. Stroke is 2.5500, rise at the gaps is 0, neighbour rise during a ±20° tap is 0 (the selected pin dips 1.97 mm), and the hold window is ±7.02°.
- **Cam, `shaft3`:** **fails one criterion.** The hold window is **±6.89°**. Stroke, gap rise and tap rise all pass, and the selected pin dips 2.14 mm.

The "hold window" is the range around a band centre where lift stays at least 2.50 mm (stroke − 0.05). The spec doesn't define it. This reading gives the 4-lobe shaft ±7.02°, just inside the requirement. With `shaft3_ramp = 22.5`, the same reading gives ±6.89°. The geometry follows the spec and was not changed.

The repo's `cad/tools/check_stl.py` rounds vertices to 1e-5 mm. That collapses sub-1e-8 mm² slivers left by the Manifold boolean, so it reports false failures on `chassis`, `pins`, `shaft` and `shaft3`. `verify.py` welds vertices exactly, and finds 0 collapsed faces and 0 unpaired edges in every file.

## Assumptions where CAD.md is ambiguous

1. **ID dot angle:** measured with the standard OpenSCAD `rotate` about Z, from +X. The single dot on `shaft` therefore sits at −X, opposite the keying notch.
2. **Spare pins:** "bands 2 and 3" is read as rows 2 and 3 (0-based, as `band_angle[k]` is). The spares continue the 7-per-row grid: row 4 is full and row 5 holds one, in slot 0. The word "spares" sits in the empty part of row 5. "Above the last row" leaves no room for 3 mm text: the sprue edge is 1.5 mm past the row-5 collars.
3. **Column digits:** 0–6, matching the 0-based column index.
4. **Pack strap-loop slot:** CAD.md gives only its depth and z range. It is cut through the full 27 mm loop length, so it's open at both y ends.
5. **0.01 mm overlaps:** wherever a solid is unioned onto existing material (bulkhead, ledges, loops, labels), it reaches 0.01 mm into it. These overlaps don't change the outer geometry.

## Notes on the spec as written

- **Screw points versus corner radius:** the four screw points sit 8.85 mm from the centres of the 9 mm corner radius. The chassis pilot holes break through the rounded corner by 1.15 mm, the face clearance holes by 1.55 mm, and the face counterbores by about 2.95 mm. This is modelled exactly as specified; see `evidence/` and render the `face` part to see it.
- **Firmware angles:** the firmware drives bands at `{0, 40, 80, 120}°` (`firmware/include/feel/controller.hpp`). Neither production shaft uses those angles: `shaft` uses 0/58/117/175 and `shaft3` uses 0/55/110 with no lobe on row 1. The firmware must change to match whichever shaft is printed. The 4-lobe shaft needs about 180° of servo travel; the repo's current design target is 120°.

# Printing the puck at the makerspace: step by step

For the 3–7 pm window. The makerspace has two printers side by side: a **Bambu Lab P1S** (left, grey) and an **Original Prusa MK3S** in a black enclosure (right). Use **both at once**:

- **Bambu P1S: shafts and pins.** Faster and more reliable on small, dense parts. Section A below.
- **Prusa MK3S: body parts** (chassis, face, guide, pack tray, foam template). Section B below.

Written for someone who has not used either slicer before. Every click is spelled out. If staff have a house way of doing something, follow them; nothing here is sacred except the settings table.

## Before you leave

1. Copy the folder `stl/print-oct17/` (8 files, 44 MB) to a USB stick. Also keep this page open on your phone.
2. Bring the finished print back in a box; the pins plate is fragile until the pins are snipped off.

## What you are printing, and in what order

Two jobs. Start Job 1 first because it's the long one; Job 2 can run on a second printer if there is one, or after.

| Job | Files | Rough time | Material |
|---|---|---|---|
| 1. Shafts | `shaft4.stl` × **7** | 3–4 h | PLA, any colour |
| 2. Body | `chassis.stl`, `guide.stl`, `face.stl`, `pack_tray.stl`, `foam_template.stl` | 5–7 h total; may not all fit in one go, see below | PLA, any colour |
| 3. Pins | `pins.stl` × 1 | 2–3 h | PLA, a **different colour** from the face if you can; dark is best |
| Only if the servo test showed ~175° | `shaft.stl` × 7 | 3–4 h | PLA |

If you can only do one thing before closing: **Job 1 (shaft4)** and **the pins**. Those are the parts that make it work. The chassis and face can print in the uncertain after-hours slot.

## The settings, all in one table

The slicer has thousands of settings. You change only these.

| Setting | Shafts and pins | Everything else | Where in PrusaSlicer |
|---|---|---|---|
| Layer height | **0.15 mm** (0.10 if time allows) | **0.20 mm** | Print Settings tab → Layers and perimeters → Layer height |
| Perimeters (walls) | **4** | 3 | Print Settings → Layers and perimeters → Perimeters |
| Infill | **100%** | 15% | Print Settings → Infill → Fill density |
| Brim | **3 mm** | none (0) | Print Settings → Skirt and brim → Brim width |
| Supports | **off** | **off** | Print Settings → Support material → Generate support material (unticked) |
| Orientation | **do not rotate** | **do not rotate** | they are already the right way up |

Everything not in the table stays at the Prusa default.

## Section A: Bambu P1S (shafts and pins), in Bambu Studio

The Bambu uses its own program, **Bambu Studio**, on the makerspace computer. The sticker on the printer says **NO GLUE, NO SCRAPER**: obey it. The textured plate releases parts by itself once it cools.

### A1. Pick the printer and filament

1. Open **Bambu Studio**. Click the **Prepare** tab at the top.
2. In the panel on the left, the top dropdown is the **Printer**: choose **Bambu Lab P1S 0.4 nozzle**.
3. Below it, **Filament**: choose the PLA that's loaded (ask staff; "Bambu PLA Basic" or "Generic PLA").
4. Below that, **Process**: choose a preset with **0.16mm** in the name (the Bambu equivalent of 0.15; "0.16mm Optimal" is fine). If there's one with **Quality** or **Fine** in the name, pick that for the pins plate.

### A2. Load the files

1. **File → Import → Import 3D Models** (or **Cmd/Ctrl+I**). From the USB stick choose `shaft4.stl`. Click **Open**. If it asks "load as a single object with multiple parts?", say **No**.
2. Click the shaft so it's selected, then press **+** on the keyboard 6 times. Seven shafts. Press **A** to arrange them.
3. **Do not rotate.** Shafts stand upright on their round base. If one looks tipped over, delete it (select, press Delete) and import again.

### A3. Set the settings

In the **Process** panel on the left, click the small **edit** (pencil) icon or just expand the sections. The sections are tabs across the top of that panel: **Quality, Strength, Speed, Support, Others**.

1. **Quality → Layer height**: 0.16 (or 0.12 if time allows). Leave "Initial layer height" alone.
2. **Strength → Wall loops**: **4**. **Sparse infill density**: **100%**.
3. **Support → Enable support**: **unticked**.
4. **Others → Brim type**: **Outer brim only**. **Brim width**: **3**.

Changed values turn orange. That's expected.

### A4. Slice, check, print

1. Click **Slice plate** (top right). When done, the view switches to **Preview** with a time estimate on the right. Write it down.
2. Drag the slider on the right up and down to scroll through layers. Lobes on the shafts should appear with nothing floating in the air.
3. Click **Print plate** (same button, now renamed). If the printer is connected over Wi-Fi, choose it from the list and click **Send**. If not, click **Export plate sliced file** and save the `.3mf` to the microSD card from the printer's slot (or ask staff how they load files).
4. On the printer's screen: **Files** (SD icon) → your file → **Print**. The P1S runs a few minutes of self-checks and bed levelling first; that's normal.
5. **Watch the first layer.** Clean and flat, stuck down: good. Balled up or dragging: press **Stop** on the screen and ask staff.

### A5. Pins plate, same way

Repeat A2–A4 with `pins.stl` × 1. Choose a **Quality/Fine** process preset if one exists; 36 thin pins print better slowly. If no such preset, go to **Speed** and halve **Outer wall** and **Inner wall** speeds. Same walls (4), infill (100%), brim (3), no support.

### A6. Taking parts off the Bambu

Wait for the bed to cool (the screen shows the bed temperature; under 40 °C is fine). Pull the flexible plate out, bend it gently, parts pop off. **No scraper.** Put the plate back the same way it came out, with the text at the front.

## Section B: Prusa MK3S (body parts), in PrusaSlicer

### 1. Open PrusaSlicer and pick the printer

1. Open **PrusaSlicer** on the makerspace computer.
2. Top right of the window there are three dropdowns: **Print settings**, **Filament**, **Printer**.
3. **Printer** → choose **Original Prusa i3 MK3S & MK3S+** (0.4 nozzle). Not MK4S. If it isn't in the list, ask staff; it's a one-time setup on their machine.
4. **Filament** → choose the PLA you're using, for example "Prusament PLA" or "Generic PLA". Ask staff which spool is loaded.
5. **Print settings** → choose a profile with **0.20mm** in the name (for example "0.20mm QUALITY"). The body parts all use 0.20. (If you end up printing shafts or pins on this machine too, pick **0.15mm QUALITY** for those.)

### 2. Load the files

1. **File → Import → Import STL** (or press **Ctrl+I** / **Cmd+I**), go to the USB stick, pick the file(s) for this job, click **Open**.
2. For the 7 shafts: import `shaft4.stl` **once**, click on it so it's highlighted, then press the **+** key 6 times (or right-click → **Instances → Add instance**, 6 times). You now have 7 copies. Press **A** on the keyboard to arrange them on the bed.
3. Each part should be standing or lying the way it loaded. **Do not rotate anything.** The shafts stand upright on their round base, the pins plate lies flat with the pins pointing up, the face is dome-side up. If something looks tipped over, delete it and import again rather than rotating.

### 3. Set the three settings that matter

Click the **Print Settings** tab across the top of the window (next to **Plater**). On the left is a list of sections.

1. **Layers and perimeters**
   - **Layer height**: should already read 0.15 (shafts/pins) or 0.2 (body) from the profile. If not, type it.
   - **Perimeters**: type **4** for shafts and pins, **3** for body parts.
2. **Infill**
   - **Fill density**: type **100%** for shafts and pins, **15%** for body parts.
3. **Skirt and brim**
   - **Brim width**: type **3** for shafts and pins, **0** for body parts.
   - **Brim type**: "Outer brim only" is fine.
4. **Support material**
   - **Generate support material**: make sure it is **unticked**.

A small orange "unlocked padlock" icon appears next to anything you changed from the profile. That's normal.

Go back to the **Plater** tab.

### 4. Slice and look

1. Click the big **Slice now** button, bottom right.
2. When it finishes, the bottom-right panel shows **Sliced Info** with an estimated time and filament use. Write the time on your phone.
3. Drag the vertical slider on the right side of the 3D view up and down. You're watching the layers build. Two things to check:
   - **Shafts:** the little round lobes on the shaft should appear and disappear as you scroll, with nothing floating in mid-air. The small chamfer under each lobe is designed so no support is needed.
   - **Pins plate:** 36 small pins standing on a flat base. The flattened tips at the top are expected.
4. If the slicer shows a yellow or red warning triangle about "unprintable" or "object outside print volume", stop and ask staff. Don't continue past a red warning.

### 5. Export and start the print

1. Click **Export G-code** (the Slice button changes into this). Save it to the USB stick. Give it a clear name like `shaft4_x7.bgcode`.
2. Take the USB stick to the printer. Plug it into the USB port on the printer's front/side.
3. On the printer screen, press **Print**, find your file, and press it. The printer heats up (a few minutes) and starts.
4. **Watch the first layer** (the first 2–3 minutes). It should be a clean, flat, even layer stuck to the bed. If the plastic is balling up, stringing in the air, or coming loose, press **Stop** on the screen and ask staff. First-layer problems are the most common failure and are always a bed/nozzle issue, not a file issue.
5. If the first layer looks right, it will almost certainly finish. Check back every 30–45 minutes.

### 6. Taking it off

1. Wait until the bed cools (the screen says, or wait ~5 min after it finishes). Parts pop off a cold bed easily and crack off a warm one.
2. The flexible steel sheet lifts off the printer; bend it gently and the parts pop free. Put the sheet back.
3. Peel the 3 mm brim off the shafts and pins with your fingers or a hobby knife.
4. Put the shafts in a bag labelled **shaft4** (and a separate bag for `shaft` if you printed those). They look nearly identical; `shaft4` has **two** small bumps on its base disc, `shaft` has **one**, `shaft3` has three.

## If the body parts don't fit on one bed

The MK3S bed is 250 × 210 mm (the Bambu is 256 × 256). The chassis (100 × 92), face (88 × 92), guide (84 × 56), pack tray (72 × 105) and foam template won't all fit at once. Do them in two plates:

- Plate A: chassis + guide + foam template.
- Plate B: face + pack tray.

Press **A** after importing to auto-arrange; if the slicer puts something off the bed it shows it in a different colour and won't slice. Delete the extra part and run it on the next plate.

## Things that might go wrong

| What you see | What to do |
|---|---|
| The printer isn't in the slicer's list | Ask staff to add it. PrusaSlicer: **Configuration → Configuration Wizard** → tick MK3S. Bambu Studio: the **+** next to the printer dropdown. Takes 2 minutes. |
| Bambu says "filament mismatch" or asks about AMS | Click **OK/Ignore**; it just wants confirmation that the loaded spool matches. If staff use the AMS (the box on top), choose the slot with PLA. |
| Sliced time is way longer than the table | Check you're not on 0.10 mm with 100% infill for the body parts. Body parts are 0.20 mm and 15%. |
| A shaft tips over mid-print | Brim too small or missing. Re-slice with 3 mm brim (or 5 mm). Print the remaining shafts; one failure doesn't ruin the others. |
| Pins snap off the plate when you remove it | They're meant to be snipped off the sprue later anyway. Keep every pin; there are 8 spares. |
| The face plate warps at the corners | It's a thin, wide part. If it happens, re-print with a 5 mm brim. |

## Settings the files already have baked in

So you don't second-guess them: all holes are printed deliberately undersize (4.3 mm) and get reamed to 4.37 mm (11/64") afterward. The pin tips are flattened by 0.25 mm so they stand up for printing. Pins print upside down on their 1 mm sprue. None of that needs fixing in the slicer.

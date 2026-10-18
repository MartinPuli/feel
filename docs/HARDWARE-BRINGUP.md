> Current layout — October 17: six active columns. GPIO32 / wire slot0 is unused.
> Left to right: GPIO33,25,26,27,14,13 (wire slots1–6). The nine-byte packet
> remains unchanged; the app reserves b0=0 and divides the whole ±45° field into
> six sectors. Existing angle settings are unchanged. See [six-column guide](SIX-COLUMN-LAYOUT.md).

> Current evidence: one unloaded GPIO32 servo moved during a bounded bench test
> and the user subsequently reported small live iPhone-driven movement. The
> complete seven-column device has not passed the physical gates below. See
> [single-servo validation](SINGLE-SERVO-IPHONE-VALIDATION.md).

# FEEL V1 — from printed parts to one working column

**Physical status: NOT VERIFIED.** These are instructions for the newly created
CAD/firmware/app. HANDOFF-v7 is a design reference, not a physical test record.
Do the stages in order. Stop at a failed stage and fix it before adding parts.

The team has confirmed two ESP32-WROOM USB-C boards and an Adafruit 5 V / 4 A supply. See [current inventory](HARDWARE-INVENTORY.md). Use the classic ESP32 build; the second board is a spare. Servo compatibility with that supply is still unverified.

## 1. Lay out and label the parts

- 7 FS0307 servos plus 1 spare; exact manufacturer/part: ______
- Classic ESP32 or ESP32-S3 development board, USB data cable; board: ______
- Separate servo power supply and suitable current distribution, switch/fuse,
  barrel connector, insulated wire and common signal ground.
- Nominal1000 µF capacitor with suitable voltage rating and correct polarity;
  half-size 400-point breadboard for signal work, not seven-servo current.
- Printed hand-cranked test column and coupons first; puck/pack later.
- 2 mm/3 mm craft foam,25 mm elastic/Velcro, zip ties, fasteners that fit the new CAD.
- Calipers, deburring tools,400/1000-grit abrasive; finishing tools and dry lubricant
  suited to the material. No heat polishing.
- LiDAR iPhone, Mac/Xcode. A second NI-compatible phone is optional for Beacon.

Photograph the parts together and each label. The geometry's `UNMEASURED` defaults
are placeholders. Read `cad/README.md` before printing servo-dependent parts.

## 2. Power review, with everything disconnected

Read the **actual** servo and board documentation. Record operating voltage,
connector order, pulse range and current requirements. Do not infer these from
wire colors or the product nickname.

| Check | Record |
|---|---|
| Servo manufacturer voltage/pulse/current source | ______ |
| Supply measured voltage and polarity | ______ |
| Supply, connector and wire current rating | ______ |
| GPIO signal compatibility | ______ |
| USB/external power cannot backfeed each other | ______ |
| Ground continuity; positives connected only as intended | ______ |
| Wiring photo and responsible electronics reviewer | ______ |

**Never power servos from GPIO or 3.3 V, or route all seven through undersized
breadboard rails.** Provide a reachable power disconnect. The capacitor does not
replace adequate power distribution. Trace wires with power off before connecting.

Classic ESP32 mapping from the handoff:

| User's left → right column | GPIO |
|---|---:|
|0|32|
|1|33|
|2|25|
|3|26|
|4|27|
|5|14|
|6|13|

S3 uses the explicit alternate mapping in `firmware/include/board_config.hpp`.
Check that mapping against your exact development-board schematic; flash/PSRAM,
USB and boot-strapping pins vary. GPIO numbers are not connector positions.

## 3. Print and assemble the hand-cranked rig

1. Run `sh cad/build.sh` and the mesh/cam checks. Read CAD warnings; nominal
   geometry passing does not authorize final fit-dependent prints.
2. Print the hole coupon and a test-column frame, guide, strip, pins, shaft and
   crank using `cad/README.md` orientation. Compare both tip radii if available.
3. Test the coupon before enlarging guide holes. The historical 11/64-inch bit is
   not a substitute for checking the new revision's nominal dimensions and fit.
4. Deburr, smooth tips gradually, and remove every sprue remnant. Do not change
   pin lengths randomly; keep wrist/finger row labels.
5. Insert pins through both guides, fit foam return as shown by CAD instructions,
   install the shaft and crank. Confirm alignment by hand before tightening.
6. Mark columns 0–6 left → right and bands 1–4 wrist→fingers. A correctly assembled
   rig must move freely without a servo forcing it.

| Test | Required observation | Result/evidence |
|---|---|---|
|P1 selection|Each band lifts only its intended pin; all gaps release pins. Measure nominal 2 mm travel.|______|
|P2 return|Repeated return works sideways and upside down without shaking.|______|
|P3 thumb contact|Comfortable gentle contact still allows selection/return; no binding or pain.|______|
|P4 endurance|100 complete four-band cycles, no jam. Record sequence, failures and wear.|______|
|P5 highlight|13° dip/return at each band; observe neighbors and actual dip travel.|______|

Also watch *between* band centres: the rotating cam passes intermediate lobes.
Software does not promise no transient activation. Record shaft variant, foam,
print settings, CAD commit, observations and video. P2 or P4 failure blocks expansion.

## 4. One unloaded servo, then one powered column

1. Keep servo power disconnected. Build the exact PlatformIO environment, review
   pin map/output enable and flash the ESP32 under team supervision.
2. Read `firmware/README.md`; firmware starts with neutral commands. Keep horn/cam
   detached for initial characterization. Check the actual servo's supported
   pulse range before enabling power.
3. Use the documented bench `ARM`, `US`, `B`, `HL`, `KEEP`, `STOP`, and `CAL`
   commands. Motion expires after 500 ms without accepted refresh; bench permission
   is a separate lease. Do not mistake this for a stable long-held calibration state.
4. Measure servo body, tabs, spline and horn. Fill the CAD measurement table,
   update parameters, rebuild coupling/shaft and confirm fit without slipping.
5. After manual P1–P5 pass, couple the mechanism with power off. Check one column's
   bands and gaps at low load. Calibrate its offset; do not force through a jam.
6. Repeat neutral, highlight, missed-write timeout and disconnect while stationary.
   Measure actual movement/return latency, supply voltage under load and current.
7. Save calibration, power-cycle and verify it was retained. Follow [CALIBRATION.md](CALIBRATION.md).

The v7 raw 650–2500 µs envelope is obsolete. The revised controller accepts only
650–2500 µs under the unmeasured175° assumption; this experimental envelope is not an instruction to begin at either endpoint. Stop on heat, buzzing, unexpected motion or binding.

## 5. Assemble the full puck only after one column passes

Follow `cad/README.md` assembly order. Match domed-face pin lengths to their printed
positions. Finish 56 guides and recheck travel; add strain relief before connecting
servo leads to the forearm pack. Check fastener lengths do not reach moving parts.

The handoff suggests cutting a lower servo ear. This is irreversible: verify exact
fit/retention with a spare or dummy first and have the team approve the cut. Do not
cut a measured part based solely on a nominal placeholder.

Add one calibrated servo at a time. Verify individual bands/gaps/taps, then
simultaneous movements, supply droop and reset behavior. Record all seven offsets.
Never compensate for a jam by increasing servo force or widening travel.

## 6. Real iPhone and BLE integration

1. Build/test on Mac, sign/install Lantern and optional Beacon. Record commits,
   OS versions and board settings. Start with a visible bench setup.
2. Mount as specified in `ios/README.md`, calibrate the floor from a measured camera
   height, and confirm left/center/right against known stationary obstacles.
3. Check all distance edges, missing depth, low confidence, tracking loss, app
   interruption/backgrounding, BLE disconnect/reconnect and 500 ms timeout.
4. Verify model loaded status and test chair/person, EXIT text and door candidates
   individually. Record false positives, missed detections and inference delay.
5. For Beacon, test both-device permissions, connection/reconnection, direction
   sign and availability across ±45°. If direction is absent, do not claim guidance.
6. After bench success, try a clear supervised indoor route with a spotter and
   immediate stop. No unsupervised blindfolded walking; no mobility-aid claims.

Keep user consent, route length, lighting, task time, contacts and failure counts
separate from simulation results. Never report a software assertion as a physical
measurement or a small demo as clinical validation.

## Next three human actions

1. Inspect the board/servo labels, power documentation and measured CAD dimensions.
2. Print the test rig, pass P1–P5, then calibrate one powered column.
3. Install the apps and verify real BLE/LiDAR/direction before seven-column walking trials.

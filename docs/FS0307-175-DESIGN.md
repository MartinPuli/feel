# FS0307 assumed 175° design — V1–V4

October 17, 2026: the user selected **175° as a working design assumption**.
This supersedes the120° source configuration. Neither175° nor the experimental
650–2500µs envelope is a measured result for the user's servo.

## Physical test report

The user reports that wider movement was tried successfully on the real servo
on October 17, 2026. This establishes user-observed motion on the tested unit.
No protractor reading, independently measured endpoints, loaded cam test, or
seven-unit result was supplied. Record the status as **user-tested wider motion;
175° selected design target**, not as no physical test and not as measured180°.

Use **175° consistently** for this revision. Do not alternate175° and180° in
firmware or geometry: the four cam positions must match the chosen mapping.
The existing650–2500µs envelope is unchanged by this decision; relabeling its
angle span cannot establish or change the servo's true physical travel.

## Shared hardware boundary

V1 perception, V2 spatial memory, V3 advanced features and V4 AI features all
send the existing nine-byte packet: sequence, seven bands, highlight. The phone
requests bands0–4; it does not send servo degrees. No BLE UUID, packet format,
GPIO assignment or electrical connection changes for this revision.

| Setting | Assumed value |
|---|---|
| Band1–4 angles | 0°,58°,116°,174° |
| Down gaps | 29°,87°,145° |
| Startup neutral | 29° |
| Highlight dip | 13° toward nearest gap; lower gap on a tie |
| Pulse mapping | Linear650–2500µs across0–175° |
| Midpoint | 87.5° =1575µs;1500µs is not the angular midpoint of this mapping |
| Calibration | New schema4 / offsets_175_v4; old offsets ignored |
| Classic seven-column GPIOs | 32,33,25,26,27,14,13 |
| Single-servo live adapter | Center camera sector3 routes to GPIO32 only |

The former single-wide adapter now passes through the shared mapping. It must
not widen it a second time. Default seven-servo output remains disabled; the
production profile still requires actual seven-unit measurement records.

## Compatibility and limits

All four app feature layers can use this mapping through the same protocol.
The shared change is promoted to main. Historical version branches remain
unchanged; no app feature branch needs merging merely to change servo angles.
An iPhone reinstall is not required for this unchanged packet contract.

Reference CAD must use the same band/gap/tap angles. Existing120° STLs, viewer
payloads, printed shafts and old test evidence remain historical; regenerate and
inspect parts before matching them to this configuration. Separate production
CAD variants may have different cam profiles or missing rows; their own checks
and physical acceptance remain necessary.

Software tests exercise commanded positions, guards, packet decoding and
simulation only. Seven-servo load, actual shaft angles, pin return, fit, torque,
Bluetooth radio behavior and full product readiness remain physically unverified.

## Test sequence

1. Verify the firmware build/profile and use one unloaded servo first. Log
   commanded pulse widths separately from measured shaft angles.
2. Measure each servo's endpoints and fit one matching cam column. Verify all
   four selected pins, all gaps, highlighting, Stop and disconnect behavior.
3. Record seven-unit calibration and power-under-load evidence before enabling
   the guarded seven-servo profile and repeating app feature tests.

No deployment or actual rotation is implied by changing these source constants.

## Five logical states

Band0 means no raised pin; bands1–4 select a pin. In the single-live/wide
adapter, a fresh band0 packet actively commands the nearest down gap, including
when all seven bands are zero. This fixes the earlier all-zero detachment that
could leave the servo at a raised-pin angle. There are three physical gap angles,
not one universal fifth angle. Actual pin return requires a matching cam and
return mechanism. App Stop/tracking loss use the same zero packet and therefore
also request a gap; disconnect, serial STOP and500ms timeout detach.

## Normal connected-device profile

For the current one-servo setup use `esp32-single-live`, advertised as **FEEL
Puck**. This uses the same shared175° mapping and zero-band gap return as the
seven-column controller, with center sector3 routed toGPIO32. The older
`esp32-single-wide-test` remains a compatibility experiment, not the profile
to deploy for this setup. Seven-servo deployment still uses its measured-record
profile; a Bluetooth name does not enable additional output pins.

## Exact user-selected pin positions

The user explicitly selected pin1=0°, pin2=58°, pin3=116°, pin4=174°.
This supersedes the earlier0/58/117/175 arrangement and removes the temporary
-7° single-unit trim. No additional adapter offset is applied. At zero stored
calibration, pulses are650/1263/1876/2489µs on the unchanged0–175° envelope.

Band0 requests the nearest gap:29° after pins1/2,87° after pin3,145° after pin4.
Ties select the lower gap. Corresponding pulses are957/1570/2183µs. Startup
neutral is29°. These commanded gaps are chosen between peaks; actual complete
pin retraction still requires physical cam/return verification.

## Current connected-servo trim: minus15°

The user's subsequent alignment request adds -159µs (approximately -15°)
once in the single-live adapter. It replaces the prior zero trim; adjustments
are not cumulative. Shared pin centers remain0/58/116/174°. Actual adapter
band pulses are650/1104/1717/2330µs, approximately0/43/101/159°. Empty-gap
pulses are798/1411/2024µs (approximately14/72/130°). Band1 clips at650µs.
This is one connected unit's alignment, not a seven-servo geometry revision.
Physical pin return at these shifted positions must be observed.

With this trim, the13° band1 highlight dip also clips to650µs: band1 has no
physical highlight pulse movement at zero calibration. This is a known effect
of the requested offset and lower bound, explicitly covered by a regression.

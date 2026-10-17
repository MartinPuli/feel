# Exact pin positions — October17,2026

User selected0/58/116/174° for pins1–4. Shared firmware, reference CAD and
four-lobe production CAD centers now agree. No-pin commands use nearest gaps
29/87/145° (lower tie); from pins1–4 the gaps are29/29/87/145°. The earlier
-7° adapter trim is removed. Schema4 resets old calibration records; production
measurement profile fs0307-assumed175-even-v4 prevents stale records being reused.

The assumed conversion remains650–2500µs across0–175°. Exact band command
pulses are650/1263/1876/2489µs. These are commanded, not measured, angles.

PASS: full firmware host suite (42controller cases plus adapter/config/CLI tests),
normal single-live build, independent single-live/wide review and regression,
51reference tests,18scenarios/77steps,2634compiled integration assertions/558states.
Evidence logs: /tmp/feel-even-host.log,/tmp/feel-even-live-build.log,
/tmp/feel-174-reference-tests.log,/tmp/feel-174-production/report.json.
Fresh OpenSCAD export/contact validation remainsBLOCKED (executable absent).
Existing meshes remain stale. Three-lobe production shaft remains incompatible.

Normal deployment is FEEL Puck, one GPIO32 servo following center sector3;
no seven-servo enablement. Upload evidence: /tmp/feel-exact-pins-upload.log.

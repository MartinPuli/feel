# No-light gap return correction

Fresh all-zero BLE packets previously detached the single-live/wide output,
leaving a servo potentially at the previous selection. They now forward the
controller's nearest-gap command. This applies to all four selected bands and
also preserves the stored calibration offset. Five logical states remain0–4;
logical0 can use29°,87.5° or146° according to the previous position.

Full firmware host suite passed; independent single-live/wide regression passed;
single-wide ESP32 build passed. Regression covers each band→allzero, gap hold
at499ms, detach at500ms, calibration, invalid input, boot and disconnect.
No physical return time or pin-height claim is made. App Stop and tracking-loss
zero packets are indistinguishable from clear-scene zero on the existing wire
format, so they command a gap too. Serial STOP/disconnect/timeout detach.

Evidence: /tmp/feel-zero-gap-tests.log, /tmp/feel-zero-gap-build.log,
/tmp/feel-zero-gap-upload.log. See upload log for actual flashing outcome.

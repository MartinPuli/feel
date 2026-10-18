> Current layout — October 17: six active columns. GPIO32 / wire slot0 is unused.
> Left to right: GPIO33,25,26,27,14,13 (wire slots1–6). The nine-byte packet
> remains unchanged; the app reserves b0=0 and divides the whole ±45° field into
> six sectors. Existing angle settings are unchanged. See [six-column guide](SIX-COLUMN-LAYOUT.md).

> October 16 update: the user explicitly selected the FS0307 nominal **120°** design.
> Current CAD/firmware/protocol supersede historical 175° / 650–2500 µs instructions.
> Assume 120° for design; do not describe it as a physical measurement. Default seven-servo PWM stays off; the opt-in GPIO32 midpoint demo has user-reported motion.
> See `docs/FS0307-120-DESIGN.md` for the new layout and verification.

# FEEL greenfield build handoff

The latest user directive names the foundation **V1**, Spatial Memory **V2**, and
advanced features **V3**. The supplied v7 document uses older version labels and
describes work that was never present in this checkout. Its verification claims
are not inherited. This file describes the new implementation.

## Source of truth

- User directive: recreate every missing component; do not wait for original code.
- `HANDOFF-v7.md`: mechanical dimensions and intended behavior, retained verbatim.
- `docs/PROTOCOL.md` and `protocol/vectors.json`: newly settled wire/edge policies.
- Source, executed logs, and `docs/RELEASE-STATUS.md`: what actually exists/passes.
- `cad/params.scad`: geometry and nominal **UNMEASURED** hardware placeholders.

No original CAD, firmware, Swift, models, weights, measurements, or research files
were supplied. Missing v5/v6 are not prerequisites to implementing this recreation.
The previous preparation branch is preserved for provenance; its Python reference
model remains explicitly separate from production-backed validation.

## Architecture

`ARKit frame → depth projection/filtering → seven sectors → tactile encoder →
nine-byte BLE write → ESP32 decoder/watchdog → calibrated seven-servo commands`.

The Swift package under `ios/Shared/FeelCore` contains portable production logic.
The Lantern app supplies ARKit/Vision/BLE adapters and accessible controls. Beacon
provides the optional peer-phone path. C++ firmware core is shared by the ESP32
application and host simulator. CAD geometry generates test-column and puck parts.

The production replay invokes compiled Swift and C++ executables. Virtual motor
motion is an explicitly synthetic estimate; no test here energizes physical pins.
The build script downloads Apple's pretrained YOLOv3 model at a pinned revision
and checks its SHA-256. Weights are not committed. Built-in Vision functionality
is labeled separately; actual CoreML inference still requires an Apple device.

## First device integration

1. On Mac, run the iOS checks and unsigned builds, then sign with the team's Apple
   ID and install on the LiDAR phone. Use the documented mounting/floor reference.
2. Build the exact board environment, inspect pin map and pulse limits, and flash
   with servo power disconnected. Follow `docs/HARDWARE-BRINGUP.md` in order.
3. Test crank P1–P5, measure the actual servo and horn, regenerate geometry, then
   calibrate one powered column. Seven columns follow only after that passes.

The release report, not file presence, determines the software gate. Physical
verification always remains separate. Spatial Memory is a separate branch after
available V1 checks pass; it does not claim safe route planning or navigation.

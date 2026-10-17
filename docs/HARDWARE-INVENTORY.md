# Hardware inventory — team confirmed October 16, 2026

This is the user's reported inventory, not measured/physically inspected here.

| Item | Quantity / specification | Integration use |
|---|---|---|
|ESP32-WROOM USB-C boards|2|Classic ESP32 is primary target; second board spare. Confirm printed GPIO labels.|
|USB-C data cable|1 reported|Programming and serial; no assumption that it powers seven servos.|
|Breadboards|3 ×400-point|Signal/temporary low-current work.|
|Perforated boards and headers|5 boards +header pack|Secure distribution and connections after bench validation.|
|Solid wire|22 AWG,7.6m|Use according to actual current, length and termination; secure against repeated flex.|
|Multimeter|Digital|Voltage/polarity/continuity and appropriately ranged current checks.|
|Cutting tool|Hakko cutters|Wire/print finishing.|
|Soldering kit|Weller|Permanent connections after wiring review.|
|Capacitor assortment|Check 1000 µF/25V present|Bulk capacitor, correct polarity, across servo supply; no substitute for adequate supply.|
|Adhesive|CA gel|Keep away from moving guides/bearings; do not glue shut before fit checks.|
|Power supply|Adafruit 5V/4A|Available supply, not yet approved for unidentified servo variant/load.|
|Barrel adapters|Barrel→terminal|Verify jack dimensions and polarity.|
|Drill bits and tactile buttons|Assortment|Coupon finishing; buttons optional.|

Still to obtain per user: M3×8 and M3×12 screws with nuts; USB-A→5.5×2.1 mm barrel
cable for a later portable-power experiment. A cable does not increase the source
port's current capacity. Wall-powered one-column testing comes first.

Not confirmed: seven FS0307 servos+one spare, exact servo label/datasheet, calipers,
2 mm/3 mm foam, Velcro/elastic, abrasives, printer access/material. Do not assume
these are absent; ask the team and update this table when confirmed.

Primary firmware environment is `esp32`. ESP32-S3 builds are portability checks;
there is no S3 in this confirmed inventory. The 5V supply must match the actual
servo's specification; the FS0307 page/handoff conflict remains unresolved.

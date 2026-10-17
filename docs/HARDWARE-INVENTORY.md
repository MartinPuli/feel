# Hardware inventory — team confirmed October 16, 2026

This is the user's reported inventory, not measured/physically inspected here.

| Item | Quantity / specification | Integration use |
|---|---|---|
|Servo identified by user|Pololu3420 FEETECH FS0307; one connected|Full seven-unit inventory and individual travel measurements still pending.|
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
|Power supply|Adafruit 5V/4A|Within the identified FS0307 supplier voltage range; seven-servo load/wiring performance unmeasured.|
|Barrel adapters|Barrel→terminal|Verify jack dimensions and polarity.|
|Drill bits and tactile buttons|Assortment|Coupon finishing; buttons optional.|

Still to obtain per user: M3×8 and M3×12 screws with nuts; USB-A→5.5×2.1 mm barrel
cable for a later portable-power experiment. A cable does not increase the source
port's current capacity. Wall-powered one-column testing comes first.

Not confirmed: availability of all seven FS0307 servos+one spare, individual measurements, calipers,
2 mm/3 mm foam, Velcro/elastic, abrasives, printer access/material. Do not assume
these are absent; ask the team and update this table when confirmed.

Primary firmware environment is `esp32`. ESP32-S3 builds are portability checks;
there is no S3 in this confirmed inventory. For the user-identified Pololu3420 FS0307, the
[supplier datasheet](https://www.pololu.com/file/0J1429/FS0307-specs.pdf) lists
4.8–6V operation,400mA stall current at4.8V and500mA at6V. Seven times the
published6V stall value is3.5A; this is arithmetic, not a5V transient/load test
or proof that the available4A supply and its wiring are adequate. The
[product page](https://www.pololu.com/product/3420) confirms3.3V signal compatibility
and approximate120° operation at900–2100µs. Verify every actual unit and power
path before final assembly.

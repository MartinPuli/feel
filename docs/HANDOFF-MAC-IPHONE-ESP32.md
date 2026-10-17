# FEEL — Mac, iPhone and ESP32 handoff

Date: October 16, 2026 (America/New_York)

> Current branch policy: all V1 development is now on `main`. The branch names,
> checkout paths and installed commit below record the earlier hardware session;
> they are historical evidence, not instructions to switch away from `main`.

> Update: the user subsequently selected 120° as the design basis. The working
> branch at that time was `codex/fs0307-120-degree`; the revision is now integrated
> into `main`. See [FS0307-120-DESIGN.md](FS0307-120-DESIGN.md).
> Historical setup/physical evidence below belongs to the prior flashed firmware.
> No new firmware was flashed as part of the redesign.

## Start here

Continue the existing FEEL V1 prototype. Do not restart setup or assume the physical mechanism works. The app is installed, the ESP32 is flashed, and actual iPhone-to-ESP32 Bluetooth messages were received. Servo outputs remain intentionally disabled. The next work is identifying the available wiring/power parts and resolving servo travel before powered mechanical integration.

The user is a beginner with electronics. Explain one physical action at a time, using visible labels and photos of their actual parts. Do not assume they understand “jumper,” “ground,” “barrel adapter,” or “power supply.” They want the assistant to perform computer work directly. They have repeatedly confused the ESP32 with a Raspberry Pi: this setup uses the ESP32, not a Raspberry Pi.

## Repository and local state

- Repository: https://github.com/MartinPuli/hackharvard
- Branch: `feel/v1-foundation`
- Current HEAD: `f6244379e7e8e9dad81f84fb4cd8886f9e77c7ee`
- Active clone: `/Users/martinezequielpulitano/Projects/feel`
- Chat workspace: `/Users/martinezequielpulitano/hackharvard` — do not confuse it with the active clone above.
- Read the active clone's `AGENTS.md` before further engineering work.
- No production source was changed during local installation. XcodeGen generated untracked `ios/Lantern/Info.plist` and `ios/Beacon/Info.plist`; preserve these for the generated project. This handoff is also a new local file. No new commit/push was performed during installation.
- Existing guide: `docs/SETUP-MAC-ESP32.md`.

## Verified in this session

| Area | Evidence and limits |
| --- | --- |
| Mac firmware tools | PlatformIO Core 6.1.18 installed in `.venv`; invoke `.venv/bin/pio` or activate the environment. A fresh shell does not have `pio` globally. |
| ESP32 build | `esp32` environment compiled successfully. Espressif32 6.9.0; Arduino framework 2.0.17; NimBLE-Arduino 2.3.6. |
| ESP32 installation | Upload succeeded and flash hashes were verified. Chip reported ESP32-D0WD-V3 revision 3.1. Port observed: `/dev/cu.usbserial-0001`, CP2102 bridge. Rediscover before future use. |
| ESP32 boot | Observed `FEEL V1 greenfield`, `SERVO OUTPUT DISABLED`, and successful `STATUS` with `outputState=0`. |
| iPhone | Actual connected device is iPhone 17 Pro, iOS 26.6.1, Developer Mode enabled. Earlier project references to an iPhone 14 Pro Max do not describe this connected phone. |
| iOS build | Xcode 26.6 (17F113); XcodeGen available. Signed Debug device build succeeded. |
| Model | Downloaded 62,200,325-byte model through `scripts/fetch_model.py`; pinned SHA-256 verification passed. |
| App installation | FEEL installed and launched on the physical iPhone. Internal target/app name `Lantern`; bundle ID `org.feel.hackharvard.lantern`. |
| Actual Bluetooth | User selected FEEL Puck in the app. Serial evidence reached `connected=1`, `accepted=14`, `rejected=0`, `outputState=0`. This verifies actual packet reception, not motor motion or full transport reliability. |
| Camera/depth UI | User reported seeing responsive blue points after guidance to use Live sensing and floor calibration. Assistant did not independently inspect the phone display or measure accuracy. Treat this as user-reported observation, not validated obstacle detection. |
| Physical servo/mechanism | NOT TESTED. No powered servo test, mechanical assembly validation, torque, travel, or tactile performance measurement. |

Final recorded board status included `active=0 connected=1 armed=0 outputState=0 seq=16 accepted=14 rejected=0 timeouts=7`. Timeouts were counted during intermittent commands; this was not a measured failsafe timing test. It is historical evidence, not a statement about the current connection.

Local evidence:

- `.artifacts/esp32-usb-status.log`
- `.artifacts/iphone-ble-status.log`
- `/tmp/feel-ios-device-build.log` (temporary file; may disappear)

Opening/closing the serial monitor was observed to coincide with an ESP32 restart and Bluetooth disconnection. Keep a single monitor session open during tests, allow boot to complete, then reconnect the phone. Do not repeatedly reopen the port and mistake reset counters for failed Bluetooth writes.

## Reusing the installation

From the active clone:

```sh
source .venv/bin/activate
pio device list
# Build only; no upload:
pio run -j 2 --project-dir firmware -e esp32
```

The successful iOS build command was:

```sh
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Lantern.xcodeproj -scheme Lantern \
  -configuration Debug -destination 'id=<currently connected device UDID>' \
  -derivedDataPath .build/ios-device DEVELOPMENT_TEAM=39D23XHM5Z \
  -allowProvisioningUpdates build
```

Discover the device with `xcrun devicectl list devices`; use device details to obtain its current identifier/UDID. Built app: `.build/ios-device/Build/Products/Debug-iphoneos/Lantern.app`. Install with `xcrun devicectl device install app --device <device-id> <app-path>`, then launch bundle ID `org.feel.hackharvard.lantern`. Unlock the phone first: the initial launch failed solely because it was locked, and succeeded after unlocking.

The Mac initially ran out of disk space. Two already-installed PlatformIO download archives were removed (about 323 MiB); the user subsequently freed space. Roughly 14 GiB was free at the last check. Check current space if builds fail; do not delete personal files.

## App operation

- App opens STOPPED. Bluetooth initialization can request permission; camera sensing requires a separate action.
- Expand **Puck connection** → **Scan for puck** → **Connect FEEL Puck**.
- Expected current firmware status: **Physical PWM DISABLED**. This is intentional, not a Bluetooth error.
- **Stop** sends a neutral packet when connected; this was used for the BLE check.
- **Simulation** is local and does not send simulated movement to hardware.
- **Live sensing** requests camera access and starts sensing. Measure actual lens height, set **Camera height**, and tap **Calibrate floor** after tracking becomes normal. Keep the documented landscape-left mounting orientation and height. Do not invent a height or assume calibration was correctly completed merely because the UI changes.

## Hardware known and unknown

User showed a small blue servo and identified it as **FEETECH Sub-Micro Servo FS0307**. They reported red, white and black wires; a photo showed a three-position female connector. Conventional mapping is red supply positive, black ground, white signal, but connector orientation and actual wiring have not been physically verified. Do not label holes by photo position without following the corresponding wires.

Reported inventory in `docs/HARDWARE-INVENTORY.md` includes:

- Two ESP32-WROOM USB-C boards.
- Adafruit 5 V / 4 A supply and barrel-to-screw-terminal adapters.
- Breadboards, perforated boards/headers, 22 AWG solid wire, multimeter, soldering kit, capacitor assortment.

These are recorded inventory, not proof the user has identified or connected them. Dupont jumper leads were not explicitly listed. Do not insist the user must have a particular cable pack. Printed mechanism availability is still unknown.

Conceptual one-servo wiring, only after confirming the source, connector and suitable leads:

- Servo signal → ESP32 **GPIO32** (printed GPIO label, not physical pin number 32).
- Servo positive → compatible external supply positive.
- Servo ground → external supply negative.
- Same supply negative → ESP32 GND (shared signal reference).
- ESP32 remains powered/programmed by Mac USB.

Do not power servo positive from GPIO or 3V3; do not join external supply positive to the ESP32 USB supply by assumption. Do not cut the servo connector as a default workaround. Verify the supply label, polarity and actual connector before giving precise assembly instructions.

## Critical unresolved issue: 120° versus 175°

The manufacturer's FS0307 PDF specifies approximately **120° for 900–2100 microsecond control pulses**, with 1500 microseconds as center. The project's **175° / 650–2500 microsecond** expectation was a design assumption, not a verified FS0307 capability. No actual travel measurement has been made. Do not claim 120° is an absolute mechanical stop; it is the documented operating range, and larger travel is not established safe.

Sources:

- Official FEETECH PDF, page 2, section 5, row 5-5: https://www.feetechrc.com/Data/feetechrc/upload/file/20220608/6379029528194935652722624.pdf
- Official product page: https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html

There is also a voltage documentation inconsistency: the PDF lists performance at 4.8 V and 6 V, while the product webpage lists an operating range of 6–8.4 V. Confirm the supplied unit/vendor documentation; do not infer permission to apply 8.4 V. The available 5 V supply was reported but has not been physically inspected or measured.

Current firmware defaults to `FEEL_ENABLE_SERVO_OUTPUT=0`. Enabling it requires explicit measured-safe pulse bounds as well. The `esp32-compilecheck` environments use unmeasured fixtures and MUST NOT be flashed. Simply turning outputs on does not resolve the mismatch between the mechanism and the servo. Review the controller's entire pulse range before enabling physical output.

## Next actions

1. Identify the user's actual supply, terminal adapter and available connection leads from a clear photo; verify source voltage/polarity and connector wiring. Give one concrete physical instruction at a time.
2. Resolve FS0307 travel and mechanical compatibility: establish safe unloaded operation and measured bounds, then adapt the cam design or select a compatible actuator based on evidence. Do not command unverified endpoint sweeps or attach an unvalidated mechanism.
3. Proceed through the repository's single-column mechanical tests and supervised unloaded-servo procedure before powered column integration, then expand to seven columns and full iPhone/perception testing.

Do not promise a completion date based solely on the installed software. Earlier estimates were conditional; mechanism availability, travel compatibility, assembly and real tests are unresolved. This is a prototype, not a validated mobility aid.

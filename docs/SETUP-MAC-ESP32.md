# FEEL: set up the ESP32 from your Mac

This guide is for your **classic ESP32-WROOM with USB-C**. You do not need a
Raspberry Pi for this setup. Today's goal is to have the Mac recognize the
board, install the firmware, and read its status. **Keep the servo and external
power supply disconnected throughout these steps.** Physical movement is
disabled in the initial firmware.

## 1. Open Terminal and check the tools

Press **⌘ + Space**, type **Terminal**, and press Enter. Copy one line at a time:

```sh
git --version
python3 --version
```

If macOS asks to install developer tools, accept the installation and reopen
Terminal when it finishes. If `python3` is unavailable, install Python 3 from
[python.org for macOS](https://www.python.org/downloads/macos/) and repeat the
check. You do not need the full Xcode installation for this first ESP32 step.

## 2. Clone the branch containing the code

Copy this block into Terminal:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone --branch feel/v1-foundation https://github.com/MartinPuli/hackharvard.git feel
cd feel
```

The repository is private: use your GitHub access if prompted. Do not paste keys
or tokens into the chat. If you see `Repository not found`, check that you are
signed in with an account that has access. This does not necessarily mean the
repository is missing.

If you already have a `~/Projects/feel` folder, do not clone over it. Open it and
first check whether you have local changes:

```sh
cd ~/Projects/feel
git status
git fetch origin
git switch feel/v1-foundation
git pull --ff-only
```

If Git reports local changes or conflicts, keep those files and share the
message; do not use `reset --hard`. On this branch, the board's code is in
`firmware/` and this guide is in `docs/SETUP-MAC-ESP32.md`.

## 3. Install PlatformIO in an isolated folder

From `~/Projects/feel`:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install platformio==6.1.18
pio --version
```

It should show PlatformIO Core 6.1.18. In a new Terminal window, run
`cd ~/Projects/feel` and `source .venv/bin/activate` again before using `pio`.
The first build downloads dependencies and requires internet access.

## 4. Identify your board's port

Connect **only one ESP32** to the Mac using the USB-C data cable. Run:

```sh
ls /dev/cu.*
pio device list
```

To identify it, compare the list before and after unplugging and reconnecting
**only that board's USB connection**. The port that appears belongs to that
connection. Its name may resemble `/dev/cu.usbserial-0001` or
`/dev/cu.SLAB_USBtoUART`; do not copy these examples as if they were your actual port.

If no new port appears, try the data cable and another USB port, temporarily
bypass any hub, and check the board's USB-to-serial chip. Some variants require
a CP210x or CH34x driver. Install only the driver for the identified chip, from
its manufacturer or the board's documentation; a power light does not prove
that USB communication works.

## 5. Build the firmware without uploading it yet

```sh
pio run -j 2 --project-dir firmware -e esp32
```

Look for `SUCCESS` at the end. The correct environment for your WROOM boards is
**`esp32`**. Do not select `esp32s3` or the `compilecheck` environments: the latter
are build checks and prohibit uploading.

If it fails, copy the first error and the last few lines. Do not change pulse
limits or motor options to fix a toolchain error.

## 6. Upload the program to the ESP32

This operation replaces the program currently on the board. Check that it is
your test board and that the servo/external power supply remain disconnected.
Close any open serial monitor.

First save the actual port you identified. Replace the text inside the quotes:

```sh
FEEL_PORT='/dev/cu.YOUR_ACTUAL_PORT'
```

Then run:

```sh
pio run -j 2 --project-dir firmware -e esp32 --target upload --upload-port "$FEEL_PORT"
```

Wait for it to finish and show `SUCCESS`. If it keeps trying to connect, some
boards require holding **BOOT** while the connection starts and releasing it
when writing begins. If this does not work, share the exact error; do not
perform a full erase or change eFuses.

## 7. Read FEEL's status

```sh
pio device monitor --port "$FEEL_PORT" --baud 115200 --echo --eol LF
```

If you do not see the startup output, briefly press **EN/RESET**. The firmware
should show `FEEL V1 greenfield` and `SERVO OUTPUT DISABLED`. Type:

```text
STATUS
```

Press Enter. The response should include `outputState=0`, which means physical
PWM output is disabled. `HELP` shows the available commands.
**Do not use ARM, B, or US to try to move the servo yet.** To exit the monitor,
press **Ctrl+C**. Close it before uploading firmware again.

The program starting and responding confirms that part of the connection to
the board; it does not prove that the motors, BLE with the iPhone, or the
mechanism work.

## 8. Before connecting a servo

The user identified the servo as a Pololu-supplied FEETECH FS0307. The design now
uses nominal 120° travel, superseding the historical 175° assumption. Actual
travel, supply under load and the complete mechanism still require measurement.
For the tested, limited GPIO32 app demo, see [SINGLE-SERVO-IPHONE.md](SINGLE-SERVO-IPHONE.md).
The default firmware in this guide leaves physical output disabled.

The intended functional wiring for **a single column**, once voltage and wires
have been verified, is:

| Connection | Intended destination |
|---|---|
| Servo signal | ESP32 GPIO **32**, identified by its GPIO label, not its physical pin position |
| Servo ground | External supply negative and ESP32 GND, connected together |
| Servo power | Positive terminal of a supply compatible with that model |
| ESP32 USB | Mac, for programming/serial communication |

Wire colors do not prove their function. Do not power servos from a GPIO or
3V3. Do not connect the motor supply's positive terminal to USB/board positive
based on intuition. Before final assembly, follow
[HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md) and [CALIBRATION.md](CALIBRATION.md).

Check the manual column first, then an unloaded servo with its actual limits,
then one motorized column, and finally all seven. Physical validation remains
pending; the firmware has no position, force, or jam sensors.

## Official references

- [PlatformIO: installation](https://docs.platformio.org/en/latest/core/installation/index.html)
- [PlatformIO: run command](https://docs.platformio.org/en/latest/core/userguide/cmd_run.html)
- [PlatformIO: serial monitor](https://docs.platformio.org/en/latest/core/userguide/device/cmd_monitor.html)
- [Espressif: ESP32 serial connection](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/establish-serial-connection.html)
- [FEETECH: FS0307](https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html)

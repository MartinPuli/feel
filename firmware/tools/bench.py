#!/usr/bin/env python3
"""Bounded, supervised serial position hold. Real hardware only; no auto sweep."""
import argparse
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    motion = parser.add_mutually_exclusive_group(required=True)
    motion.add_argument("--band", type=int, nargs=2, metavar=("COLUMN", "BAND"))
    motion.add_argument("--pulse", type=int, nargs=2, metavar=("COLUMN", "MICROSECONDS"))
    parser.add_argument("--seconds", type=float, default=2)
    args = parser.parse_args()
    if not 0 < args.seconds <= 10:
        parser.error("--seconds must be in (0, 10]")
    column, value = args.band if args.band else args.pulse
    if not 0 <= column < 7:
        parser.error("column must be 0..6")
    if args.band and not 0 <= value <= 4:
        parser.error("band must be 0..4")
    if args.pulse and not 650 <= value <= 2500:
        parser.error("pulse must be 650..2500; establish safe endpoints on your servo first")

    import serial

    print("REAL HARDWARE: supervised one-column hold. Opening serial may reset the board.", flush=True)
    with serial.Serial(args.port, 115200, timeout=0.05, write_timeout=0.2) as connection:
        time.sleep(2)  # Board boot; no motion commands have been sent.
        connection.reset_input_buffer()

        def command(text):
            connection.write((text + "\n").encode("ascii"))
            deadline = time.monotonic() + 0.35
            while time.monotonic() < deadline:
                response = connection.readline().decode("ascii", errors="replace").strip()
                if response == "ok":
                    return
                if response:
                    raise RuntimeError(f"{text}: {response}")
            raise TimeoutError(f"No acknowledgment for {text}; watchdog will neutralize")

        try:
            connection.write(b"STATUS\n")
            deadline = time.monotonic() + 0.35
            output_ready = False
            status_complete = False
            while time.monotonic() < deadline:
                response = connection.readline().decode("ascii", errors="replace").strip()
                if response.startswith("STATUS "):
                    output_ready = "outputState=1(" in response
                if response.startswith("c6 "):
                    status_complete = True
                    break
            if not status_complete or not output_ready:
                raise RuntimeError("Physical PWM is disabled, faulted, or status unavailable; no motion sent. Verify measured-range build configuration.")
            command("ARM")
            command(f"{'B' if args.band else 'US'} {column} {value}")
            deadline = time.monotonic() + args.seconds
            while time.monotonic() < deadline:
                time.sleep(min(0.1, max(0, deadline - time.monotonic())))
                command("KEEP")
            print("Hold complete; sending STOP", flush=True)
        finally:
            connection.write(b"STOP\n")
            connection.flush()


if __name__ == "__main__":
    main()

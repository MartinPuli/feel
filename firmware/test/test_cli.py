#!/usr/bin/env python3
"""Exercise the actual production-controller process and its JSON boundary."""
import json
import subprocess
import sys

executable = sys.argv[1]
commands = """CONNECT 0
PACKET 0 254 1 2 3 4 0 1 2 255
PACKET 100 255 1 2 3 4 0 1 2 3
PACKET 200 0 1 2 3 4 0 1 2 3
PACKET 300 0 4 4 4 4 4 4 4 255
PACKET 400 1 5 1 1 1 1 1 1 255
TICK 699
TICK 700
DISCONNECT 710
ARM 720
US 730 0 2100
TICK 1230
US 1231 0 999999
DECODE 1240 127 0 0 0 0 0 0 0 4
PACKET 1250 1
CONNECT 1300
PACKET 1301 0x01 4 4 4 4 4 4 4 0xff
"""
result = subprocess.run([executable], input=commands, text=True, capture_output=True, check=True, timeout=10)
states = [json.loads(line) for line in result.stdout.splitlines()]
assert len(states) == len(commands.splitlines()), result.stdout
assert all(s["mode"] == "SIMULATION" and s["production_controller"] for s in states)
assert states[1]["angles_deg"] == [0, 40, 80, 120, 20, 0, 40]
assert states[2]["angles_deg"][3] == 107 and states[2]["tap_active"]
assert states[3]["angles_deg"][3] == 120 and not states[3]["tap_active"]
assert states[4]["result"] == "duplicate"
assert states[5]["result"] == "bad_band"
assert states[6]["active"]
assert not states[7]["active"] and states[7]["bands"] == [0] * 7
assert states[7]["angles_deg"] == [20, 20, 60, 100, 20, 20, 20]
assert states[10]["raw_pulse"] and states[10]["pulses_us"][0] == 2100
assert not states[11]["active"] and states[11]["angles_deg"][0] == 100
assert states[12]["result"] == "bad_command"
assert states[13]["result"] == "ok"
assert states[14]["result"] == "bad_length"
assert states[16]["result"] == "ok" and states[16]["bands"] == [4] * 7
print("PASS firmware CLI: 17 commands, JSON states, production decoder and timeout assertions")

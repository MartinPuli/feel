#!/usr/bin/env python3
"""Compile-only safety gates: enabling PWM cannot omit measured pulse limits."""
import os
from pathlib import Path
import subprocess

include = Path(__file__).resolve().parents[1] / "include"
base = [os.environ.get("CXX", "c++"), "-std=c++11", "-x", "c++", "-fsyntax-only", "-", "-I", str(include), "-DFEEL_BOARD_CLASSIC"]


def check(flags, success):
    result = subprocess.run(base + flags, input='#include "board_config.hpp"\n', capture_output=True, text=True, timeout=15)
    assert (result.returncode == 0) == success, result.stderr


check([], True)
check(["-DFEEL_ENABLE_SERVO_OUTPUT=1"], False)
check(["-DFEEL_ENABLE_SERVO_OUTPUT=1", "-DFEEL_VERIFIED_PULSE_MIN_US=900"], False)
check(["-DFEEL_ENABLE_SERVO_OUTPUT=1", "-DFEEL_VERIFIED_PULSE_MIN_US=900", "-DFEEL_VERIFIED_PULSE_MAX_US=2100"], True)
check(["-DFEEL_ENABLE_SERVO_OUTPUT=1", "-DFEEL_VERIFIED_PULSE_MIN_US=2100", "-DFEEL_VERIFIED_PULSE_MAX_US=900"], False)
check(["-DFEEL_ENABLE_SERVO_OUTPUT=1", "-DFEEL_VERIFIED_PULSE_MIN_US=500", "-DFEEL_VERIFIED_PULSE_MAX_US=2500"], False)
print("PASS firmware board config: 6 compile-only default/required-limit/range checks (no physical outputs)")

#!/bin/sh
# Point-to-describe detector check on the Mac: synthetic frames through the real Vision pipeline.
set -eu
cd "$(dirname "$0")/.."
out=.build/pointing-harness
mkdir -p "$out"
swiftc -O -parse-as-library -emit-library -static -module-name FeelCore -emit-module -emit-module-path "$out/FeelCore.swiftmodule" \
  -o "$out/libFeelCore.a" Shared/FeelCore/Sources/FeelCore/*.swift
swiftc -O -I "$out" -L "$out" -lFeelCore -o "$out/harness" \
  Lantern/Services/PointingDetector.swift LanternTests/PointingSynthetic.swift scripts/pointing_harness/main.swift
"$out/harness"

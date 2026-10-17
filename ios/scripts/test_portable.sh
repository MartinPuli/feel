#!/bin/sh
# On Linux, execute the built XCTest binary directly. This also works in hosts
# where SwiftPM's subprocess monitor cannot read child /proc/<pid>/stat entries.
set -eu
cd "$(dirname "$0")/../Shared/FeelCore"
if [ "$(uname -s)" = Linux ]; then
  swift build --build-tests -j "${FEEL_SWIFT_JOBS:-2}"
  feel_bin_dir=$(swift build --show-bin-path)
  "$feel_bin_dir/FeelCorePackageTests.xctest"
else
  swift test
fi

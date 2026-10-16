#!/bin/sh
# On Linux, execute the built XCTest binary directly. This also works in hosts
# where SwiftPM's subprocess monitor cannot read child /proc/<pid>/stat entries.
set -eu
cd "$(dirname "$0")/../Shared/FeelCore"
if [ "$(uname -s)" = Linux ]; then
  swift build --build-tests -j "${FEEL_SWIFT_JOBS:-2}"
  # SwiftPM creates this configuration symlink for the current host triple.
  # Avoid starting a second SwiftPM subprocess just to discover its output path.
  feel_test_binary=.build/debug/FeelCorePackageTests.xctest
  if [ ! -x "$feel_test_binary" ]; then
    echo "Built XCTest executable is missing: $feel_test_binary" >&2
    exit 1
  fi
  "$feel_test_binary"
else
  swift test
fi

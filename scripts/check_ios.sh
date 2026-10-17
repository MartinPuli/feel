#!/usr/bin/env bash
# Software-only validation. No signing, provisioning, flashing, or real device use.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
if [ ! -d "$repo_root/ios" ]; then
  echo 'BLOCKED: greenfield ios/ source directory is missing.'
  exit 2
fi
cd "$repo_root/ios"
for tool in xcodegen xcodebuild xcrun python3; do
  if ! command -v "$tool" >/dev/null; then
    echo "BLOCKED: missing $tool; use the team's compatible macOS/Xcode installation."
    exit 2
  fi
done
test -f project.yml || { echo 'BLOCKED: missing greenfield ios/project.yml'; exit 2; }
xcodebuild -version
xcodegen generate
xcodebuild -list -project Lantern.xcodeproj
mkdir -p ../.artifacts/ios
xcrun simctl list devices available --json > ../.artifacts/ios/destinations.json
destination=$(python3 - <<'PY'
import json
with open('../.artifacts/ios/destinations.json') as f:
    data = json.load(f)
choices = [(runtime, d['name'], d['udid']) for runtime, devices in data['devices'].items()
           if '.iOS-' in runtime for d in devices
           if d.get('isAvailable') and d['name'].startswith('iPhone')]
if choices:
    print(sorted(choices)[-1][2])
PY
)
if [ -z "$destination" ]; then
  echo 'BLOCKED: no available iPhone simulator. Install a runtime compatible with the project.'
  exit 2
fi
printf 'Selected installed simulator: %s\n' "$destination"
# Keep one simulator lifecycle and retain diagnostics even when a UI test fails.
result_directory=$(mktemp -d ../.artifacts/ios/results.XXXXXX)
xcodebuild -project Lantern.xcodeproj -scheme Lantern \
  -destination "platform=iOS Simulator,id=$destination" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "$result_directory/Lantern.xcresult" \
  -derivedDataPath ../.artifacts/ios/DerivedData CODE_SIGNING_ALLOWED=NO test
# Companion UI and compilation are checked separately; NI functionality needs real phones.
xcodebuild -project Lantern.xcodeproj -scheme Beacon \
  -destination "platform=iOS Simulator,id=$destination" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "$result_directory/Beacon.xcresult" \
  -derivedDataPath ../.artifacts/ios/DerivedData CODE_SIGNING_ALLOWED=NO test
# Compile device-only paths as unsigned builds. This does not run on a phone.
for scheme in Lantern Beacon; do
  xcodebuild -project Lantern.xcodeproj -scheme "$scheme" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath ../.artifacts/ios/DerivedData CODE_SIGNING_ALLOWED=NO build
done

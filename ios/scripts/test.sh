#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test --package-path Shared/FeelCore
if [ "${1:-}" = '--ios' ]; then
  command -v xcodegen >/dev/null
  xcodegen generate
  : "${FEEL_SIMULATOR_ID:?Set FEEL_SIMULATOR_ID to a real available simulator UUID from xcrun simctl list devices available}"
  xcodebuild -project Lantern.xcodeproj -scheme Lantern -destination "platform=iOS Simulator,id=$FEEL_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO test
fi

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen, then rerun. See ios/README.md.' >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo 'Xcode on macOS is required.' >&2; exit 2; }
xcodegen generate
xcodebuild -project Lantern.xcodeproj -scheme Lantern -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Lantern.xcodeproj -scheme Beacon -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

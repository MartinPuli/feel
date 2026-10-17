#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../.."
sh firmware/test/run_host_tests.sh
swift build --package-path ios/Shared/FeelCore
python3 validation/production/run.py "$@"

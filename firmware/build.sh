#!/bin/sh
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 -m platformio run -d "$firmware_dir" -e esp32 -e esp32s3 -j "${FEEL_BUILD_JOBS:-2}" "$@"

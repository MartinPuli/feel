#!/bin/sh
# Copy FEEL recordings off a connected iPhone into simulation/recordings/ and rerun the replay harness,
# so a walk you just recorded shows up on /replay as an UNLABELLED session.
#
#   scripts/pull_recordings.sh                      # device named "iPhone", then python3 simulation/run.py
#   scripts/pull_recordings.sh "Ethan's iPhone"     # another device name or UDID (xcrun devicectl list devices)
#   scripts/pull_recordings.sh iPhone --snapshot before   # extra arguments go to simulation/run.py
#
# Needs: the phone plugged in or on the same Wi-Fi, paired with this Mac, Developer Mode on, and Lantern
# installed as a development build (devicectl can only read the data container of apps it can debug).
# Files already in simulation/recordings/ are not overwritten. Nothing is deleted from the phone.
# Alternative without a cable: Files app → On My iPhone → FEEL → Recordings, AirDrop to the Mac.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEVICE=${1:-iPhone}
[ $# -gt 0 ] && shift
DEST="$ROOT/simulation/recordings"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier org.feel.hackharvard.lantern --source Documents/Recordings --destination "$TMP"

before=$(find "$DEST" -maxdepth 1 -name '*.feelrec' | wc -l | tr -d ' ')
find "$TMP" -type f \( -name '*.feelrec' -o -name '*.mp4' -o -name '*.video.json' -o -name '*.events.json' \) \
  -exec mv -n {} "$DEST"/ \;
after=$(find "$DEST" -maxdepth 1 -name '*.feelrec' | wc -l | tr -d ' ')
echo "Recordings in simulation/recordings: $after ($((after - before)) new)"
ls -t "$DEST" | grep '\.feelrec$' | head -3 | sed 's/^/  /'

cd "$ROOT" && python3 simulation/run.py "$@"

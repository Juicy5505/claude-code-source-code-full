#!/usr/bin/env bash
# Build the WHOOP IMU sidecar iOS app (macOS + Xcode only).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MODE="check"
case "${1:-}" in
  --test) MODE="test" ;;
  --device) MODE="device" ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found — run on a Mac with Xcode" >&2
  exit 1
fi

echo "==> regenerating project"
python3 generate-project.py || exit 1

find_sim() {
  xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for d in entries:
        if d.get("isAvailable") and d.get("udid"):
            print(d["udid"])
            raise SystemExit
' 2>/dev/null
}

SIM=$(find_sim || true)
DEST=${SIM:+platform=iOS Simulator,id=$SIM}
DEST=${DEST:-generic/platform=iOS Simulator}

COMMON=(
  -project WhoopSwingSidecar.xcodeproj
  -scheme WhoopSwingSidecar
  -destination "$DEST"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

case "$MODE" in
  check)
    xcodebuild build "${COMMON[@]}" -quiet
    ;;
  test)
    xcodebuild test "${COMMON[@]}" -quiet
    ;;
  device)
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
      echo "Set DEVELOPMENT_TEAM for device builds" >&2
      exit 1
    fi
    xcodebuild build -project WhoopSwingSidecar.xcodeproj -scheme WhoopSwingSidecar \
      -destination generic/platform=iOS \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -quiet
    ;;
esac

echo "==> OK ($MODE)"

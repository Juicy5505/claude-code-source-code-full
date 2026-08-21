#!/usr/bin/env bash
# D19 Mac green-build proof — paste on Alex's Mac after "xcode is good to go".
# Linux cloud agents cannot run this (NO_XCODE). Do NOT invent a green result.
#
# Usage (from repo root or apple/):
#   bash whoop-18birdies/apple/scripts/mac-d19-verify.sh
#
# Notes:
# - Do NOT pass -derivedDataPath under iCloud ~/Documents (LESSONS L3).
# - Physical Watch install remains OS-gated; this script is build + unit tests only.
# - Schemes: WhoopGolf, WhoopGolfWatch (shared under WhoopGolf.xcodeproj).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${APPLE_DIR}"

LOG_DIR="${TMPDIR:-/tmp}/whoopgolf-d19-verify-$$"
mkdir -p "${LOG_DIR}"

echo "==> D19 verify in ${APPLE_DIR}"
echo "    logs → ${LOG_DIR}"
echo

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "FAIL: xcodebuild not found. Open Xcode once, then retry." >&2
  exit 127
fi

xcodebuild -version | tee "${LOG_DIR}/xcode-version.txt"
echo

# Prefer a concrete simulator when available; fall back to generic iOS for build-only.
SIM_DEST="platform=iOS Simulator,name=iPhone 16"
if ! xcodebuild -scheme WhoopGolf -showdestinations 2>/dev/null | grep -q "iPhone 16"; then
  if xcodebuild -scheme WhoopGolf -showdestinations 2>/dev/null | grep -q "iPhone 15"; then
    SIM_DEST="platform=iOS Simulator,name=iPhone 15"
  else
    SIM_DEST="generic/platform=iOS"
    echo "WARN: no iPhone 15/16 simulator listed; tests will use generic/platform=iOS (may need a booted sim)."
  fi
fi

echo "==> [1/3] WhoopGolf (iOS) build"
xcodebuild \
  -scheme WhoopGolf \
  -destination 'generic/platform=iOS' \
  -quiet \
  build | tee "${LOG_DIR}/ios-build.log"
echo "OK WhoopGolf build"
echo

echo "==> [2/3] WhoopGolfWatch (watchOS) build"
xcodebuild \
  -scheme WhoopGolfWatch \
  -destination 'generic/platform=watchOS' \
  -quiet \
  build | tee "${LOG_DIR}/watch-build.log"
echo "OK WhoopGolfWatch build"
echo

echo "==> [3/3] WhoopGolfTests (D19 minimum + trail-right polarity)"
# Minimum D19 proof classes (also run full WhoopGolfTests if these pass and you want more).
xcodebuild \
  -scheme WhoopGolf \
  -destination "${SIM_DEST}" \
  -only-testing:WhoopGolfTests/DualWearableRequirementTests \
  -only-testing:WhoopGolfTests/ComprehensiveShotIntelligenceTests \
  -only-testing:WhoopGolfTests/StrokeScoreShotChainTests \
  -only-testing:WhoopGolfTests/SwingPathGuidanceTests \
  test | tee "${LOG_DIR}/d19-tests.log"
echo "OK D19 unit tests"
echo

echo "==== D19 MAC VERIFY SUCCEEDED ===="
echo "Paste back: builds green + DualWearableRequirement / ComprehensiveShotIntelligence /"
echo "StrokeScoreShotChain / SwingPathGuidanceTests (trail-right) passed."
echo "Logs: ${LOG_DIR}"
echo
echo "Still gated (not claimed by this script): physical Watch install / Watch OS update."

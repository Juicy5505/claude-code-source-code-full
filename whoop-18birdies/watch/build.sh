#!/usr/bin/env bash
#
# Build the watch app and show the compiler errors plainly.
#
#   ./build.sh            compile check only — no signing, no watch, no Team ID
#   ./build.sh --test     compile and run the unit tests in a simulator
#   ./build.sh --device   build for a real Apple Watch (needs DEVELOPMENT_TEAM)
#
# The default is the one you want first. It builds against the watchOS
# SIMULATOR sdk with signing switched off, which means it type-checks and
# compiles every Swift file without a developer account, a provisioning
# profile, or a paired watch — the three things that make "Signing for
# 'WhoopGolf' requires a development team" stop a build before the compiler
# has said anything at all about your code.
#
# macOS only: xcodebuild ships with Xcode and exists nowhere else.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MODE="check"
case "${1:-}" in
  --test)   MODE="test" ;;
  --device) MODE="device" ;;
  "")       ;;
  *) echo "unknown option: $1 (try --test or --device)" >&2; exit 2 ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
  cat >&2 <<'MSG'
xcodebuild not found.

This script needs Xcode, so it runs on a Mac and nowhere else. If you are in a
cloud session, a container, or on Windows, there is no way around that — build
from a local Claude Code session on the Mac instead (see HANDOFF.md).
MSG
  exit 1
fi

# Regenerate first, so a source file added to the repo but not to the project
# is a build error rather than a file that silently never compiles.
echo "==> regenerating the project"
python3 generate-project.py || exit 1

ARGS=(-project WhoopGolf.xcodeproj -scheme WhoopGolf -configuration Debug)

case "$MODE" in
  check)
    echo "==> compile check (watchOS simulator sdk, signing off)"
    ARGS+=(-sdk watchsimulator CODE_SIGNING_ALLOWED=NO build)
    ;;
  test)
    # A concrete simulator, discovered rather than guessed: the names change
    # with every Xcode release, so a hardcoded "Apple Watch Series 9 (45mm)"
    # fails on the next one with an error about destinations, not about tests.
    echo "==> finding a watchOS simulator"
    DEST=$(xcodebuild -project WhoopGolf.xcodeproj -scheme WhoopGolf \
             -showdestinations 2>/dev/null \
           | grep 'platform:watchOS Simulator' | grep -v 'placeholder' \
           | head -1 | sed -E 's/.*id:([0-9A-Fa-f-]+).*/\1/')
    if [ -z "$DEST" ]; then
      echo "no watchOS simulator installed — Xcode → Settings → Components" >&2
      exit 1
    fi
    echo "    simulator $DEST"
    ARGS+=(-destination "id=$DEST" CODE_SIGNING_ALLOWED=NO test)
    ;;
  device)
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
      cat >&2 <<'MSG'
DEVELOPMENT_TEAM is not set, and a device build cannot be signed without it.

  DEVELOPMENT_TEAM=ABCDE12345 ./build.sh --device

Your Team ID is the ten-character code at developer.apple.com → Membership.
Use ./build.sh with no arguments if you only want to know whether the code
compiles — that needs no team at all.
MSG
      exit 1
    fi
    echo "==> device build, team $DEVELOPMENT_TEAM"
    ARGS+=(-destination 'generic/platform=watchOS' build)
    ;;
esac

LOG=$(mktemp -t whoopgolf-build)
xcodebuild "${ARGS[@]}" >"$LOG" 2>&1
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  printf '\n\033[32mBUILD SUCCEEDED\033[0m  (full log: %s)\n' "$LOG"
  [ "$MODE" = "test" ] && grep -E "Test Suite .* (passed|failed)" "$LOG" | tail -5
  exit 0
fi

# Only the lines that name a file and a problem. xcodebuild prints thousands of
# lines of clang invocations around them, and the errors are easy to walk past.
printf '\n\033[31mBUILD FAILED\033[0m\n\n'
if grep -E '(error|warning): ' "$LOG" | sort -u | head -40 | grep -q .; then
  grep -E '(error|warning): ' "$LOG" | sort -u | head -40
else
  tail -40 "$LOG"
fi
printf '\nFull log: %s\n' "$LOG"
exit "$STATUS"

#!/usr/bin/env bash
# One-shot Mac setup for WHOOP golf — watch (Kit A) + sidecar (Kit C).
#
# Run from repo root on your Mac:
#   cd whoop-18birdies && ./setup-mac-xcode.sh
#
# Optional: bake your Apple Team ID into both projects:
#   DEVELOPMENT_TEAM=ABCDE12345 ./setup-mac-xcode.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }
hdr() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  red "This script must run on macOS (you are on $(uname -s))."
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  red "Xcode not found. Install from the App Store, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

hdr "Xcode"
xcodebuild -version | head -1

# --- Team ID ---------------------------------------------------------------
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  ylw "DEVELOPMENT_TEAM not set — trying to detect from keychain…"
  DEVELOPMENT_TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Development" | head -1 \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true)
fi

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  grn "Using DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
  export DEVELOPMENT_TEAM
else
  ylw "No Team ID detected. Xcode will prompt you to pick a team when you open each project."
  ylw "Find yours at developer.apple.com → Membership (10 characters)."
fi

# --- Regenerate projects ---------------------------------------------------
hdr "Regenerating watch project (Kit A)"
python3 watch/generate-project.py

hdr "Regenerating sidecar project (Kit C)"
python3 sidecar/generate-project.py

# --- Compile checks --------------------------------------------------------
hdr "Compile check — watch (simulator, no signing)"
( cd watch && ./build.sh ) && grn "Watch: compile OK" || { red "Watch compile failed"; exit 1; }

hdr "Compile check — sidecar (simulator, no signing)"
( cd sidecar && ./build.sh ) && grn "Sidecar: compile OK" || { red "Sidecar compile failed"; exit 1; }

# --- Optional: unit tests (slower) -----------------------------------------
if [[ "${RUN_TESTS:-}" == "1" ]]; then
  hdr "Unit tests — watch"
  ( cd watch && ./build.sh --test )
  hdr "Unit tests — sidecar"
  ( cd sidecar && ./build.sh --test )
fi

# --- Tailscale / LAN addresses ---------------------------------------------
hdr "Network addresses for upload settings"
LAN_IP=""
for iface in en0 en1; do
  LAN_IP=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
  [[ -n "$LAN_IP" ]] && break
done
TS_IP=""
if command -v tailscale >/dev/null 2>&1; then
  TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi

echo "  Watch upload URL  → http://${LAN_IP:-YOUR_LAN_IP}:8790"
echo "                      (watch has NO Tailscale — LAN WiFi only)"
echo "  iPhone / sidecar  → http://${TS_IP:-YOUR_TAILSCALE_IP}:8790"
echo "                      (or same LAN IP if both on home WiFi)"

# --- wb serve token --------------------------------------------------------
TOKEN_FILE="$HOME/.whoop-18birdies/ingest-token.txt"
mkdir -p "$HOME/.whoop-18birdies"
if [[ ! -f "$TOKEN_FILE" ]]; then
  openssl rand -base64 24 | tr -d '\n' > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  grn "Created ingest token → $TOKEN_FILE"
else
  grn "Existing ingest token → $TOKEN_FILE"
fi
echo "  WB_INGEST_TOKEN=$(cat "$TOKEN_FILE")"

# --- Open Xcode ------------------------------------------------------------
hdr "Opening both projects in Xcode"
open watch/WhoopGolf.xcodeproj
open sidecar/WhoopSwingSidecar.xcodeproj

cat <<'GUI'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IN XCODE (do once per project)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For BOTH targets (WhoopGolf and WhoopSwingSidecar):

  1. Click the blue project icon in the left sidebar
  2. Select the app target (not the test target)
  3. Signing & Capabilities tab
  4. ✓ Automatically manage signing
  5. Team → your Apple ID / Personal Team

WhoopGolf (watch):
  6. Destination → your Apple Watch (or a watch simulator to compile only)
  7. Product → Run  (⌘R)
  8. On watch: Upload settings → LAN URL above + token from ingest-token.txt

WhoopSwingSidecar (iPhone):
  6. Destination → your iPhone
  7. Product → Run  (⌘R)
  8. Trust developer on iPhone if prompted (Settings → General → VPN & Device Management)
  9. Upload settings → Tailscale URL (or LAN) + same token

First physical install (watch):
  • iPhone paired, Watch app installed, Developer Mode on watch if iOS 16+

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  START INGEST SERVER (separate Terminal tab)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  cd whoop-18birdies
  export WB_INGEST_TOKEN=$(cat ~/.whoop-18birdies/ingest-token.txt)
  bun src/cli.ts serve

  Tailscale: ON on Mac + iPhone. Exit nodes: OFF.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GUI

grn "Setup script finished. Both .xcodeproj files should be open in Xcode."

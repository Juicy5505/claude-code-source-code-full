#!/usr/bin/env bash
#
# Put WHOOP Golf on your iPhone AND your Apple Watch with one command:
#
#     cd whoop-18birdies/apple && ./ship-to-watch.sh
#
# No Xcode windows. This script finds your signing team, builds both apps,
# finds your plugged-in iPhone and its paired Watch, and installs to both.
#
# Apple reserves a few taps for a human — Developer Mode, trusting your
# certificate — and no script anywhere can perform those. When this hits one,
# it STOPS and prints the exact tap to make, in words. Make the tap, run the
# script again. It is fast on re-run; nothing is harmed by running it twice.
#
# Free Personal Team note: the install expires after 7 days. Re-run this
# script to refresh it — that is normal, not breakage.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
hdr() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

stop_and_tap() {
  # The script's whole contract: when a human tap is required, say exactly
  # which one, then exit so the re-run picks up from a clean state.
  echo
  red "STOP — one tap is needed before this can continue:"
  echo
  printf '%s\n' "$@"
  echo
  echo "Then run this script again:  ./ship-to-watch.sh"
  exit 1
}

# --- Preconditions -----------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
  red "This must run on your Mac (it is running on $(uname -s))."
  exit 1
fi
command -v xcodebuild >/dev/null 2>&1 || stop_and_tap \
  "Install Xcode from the App Store, open it once, then:" \
  "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"

hdr "Xcode"
xcodebuild -version | head -1

# --- Signing team ------------------------------------------------------------
# Personal Team IDs are ten alphanumerics; the keychain has one as soon as an
# Apple ID has been added to Xcode. If none is there, no build can be signed,
# and the fix is a one-time sign-in that only a person can do.

hdr "Signing team"
TEAM="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
         | grep -oE '\(([A-Z0-9]{10})\)' | head -1 | tr -d '()')
fi
if [[ -z "$TEAM" ]]; then
  stop_and_tap \
    "Open Xcode → Settings → Accounts → '+' → sign in with your Apple ID." \
    "(One time only. This creates the free Personal Team the build signs with.)"
fi
grn "team $TEAM"

# --- Find the iPhone and the Watch -------------------------------------------

hdr "Devices"
DEVJSON=$(mktemp -t whoopgolf-devices).json
if ! xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1; then
  stop_and_tap \
    "Plug your iPhone into this Mac with a cable and unlock it." \
    "If it asks 'Trust This Computer?', tap Trust."
fi

read -r PHONE_ID PHONE_NAME WATCH_ID WATCH_NAME <<<"$(python3 - "$DEVJSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("- - - -"); raise SystemExit
phone = watch = None
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {}) or {}
    kind = (hw.get("deviceType") or hw.get("productType") or "")
    name = (d.get("deviceProperties", {}) or {}).get("name") or "device"
    ident = d.get("identifier")
    if not ident:
        continue
    k = kind.lower()
    if "iphone" in k and phone is None:
        phone = (ident, name)
    if "watch" in k and watch is None:
        watch = (ident, name)
def cell(x): return x.replace(" ", "_") if x else "-"
print(cell(phone[0] if phone else None), cell(phone[1] if phone else None),
      cell(watch[0] if watch else None), cell(watch[1] if watch else None))
PY
)"

if [[ "$PHONE_ID" == "-" ]]; then
  stop_and_tap \
    "Plug your iPhone into this Mac with a cable and unlock it." \
    "If it asks 'Trust This Computer?', tap Trust on the phone."
fi
grn "iPhone: ${PHONE_NAME//_/ }"
if [[ "$WATCH_ID" == "-" ]]; then
  echo "  (Watch not visible yet — it appears through the iPhone. Continuing;"
  echo "   the Watch step below will say what to do if it stays hidden.)"
else
  grn "Watch:  ${WATCH_NAME//_/ }"
fi

# --- Build both apps ---------------------------------------------------------
# -allowProvisioningUpdates lets xcodebuild mint free-team profiles and
# register your devices by itself — this is what replaces every visit to the
# Signing & Capabilities pane.

DD="$HOME/Library/Developer/WhoopGolfShip"   # NOT under iCloud Documents (LESSONS L3)
LOG=$(mktemp -t whoopgolf-ship)

build() {
  local scheme="$1" platform="$2"
  hdr "Building $scheme"
  if ! xcodebuild -project WhoopGolf.xcodeproj -scheme "$scheme" \
        -configuration Debug -destination "generic/platform=$platform" \
        -derivedDataPath "$DD" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
        build >"$LOG" 2>&1; then
    if grep -qiE "requires a development team|No Account for Team|Sign in with your Apple ID" "$LOG"; then
      stop_and_tap \
        "Open Xcode → Settings → Accounts → '+' → sign in with your Apple ID."
    fi
    if grep -qiE "maximum App ID limit" "$LOG"; then
      stop_and_tap \
        "Your free Apple ID hit its 10-App-IDs-per-week limit." \
        "Wait for the week to roll over, or delete unused personal-team apps at" \
        "developer.apple.com → Certificates, Identifiers & Profiles → Identifiers."
    fi
    red "BUILD FAILED — the lines that matter:"
    grep -E "error: " "$LOG" | sort -u | head -20
    echo "Full log: $LOG"
    exit 1
  fi
  grn "built"
}

build WhoopGolf iOS
build WhoopGolfWatch watchOS

PHONE_APP="$DD/Build/Products/Debug-iphoneos/WhoopGolf.app"
WATCH_APP="$DD/Build/Products/Debug-watchos/WhoopGolfWatch.app"

# --- Verify the plist that cost us once already ------------------------------
# The Watch bundle must carry location (or the app dies at round start) and
# workout-processing (or it suspends when the wrist drops). Checked in the
# BUILT product, because trusting the source file has burned this project before.

hdr "Checking the built Watch app"
for want in "UIBackgroundModes:location" "WKBackgroundModes:workout-processing"; do
  key="${want%%:*}"; val="${want##*:}"
  if plutil -extract "$key" json -o - "$WATCH_APP/Info.plist" 2>/dev/null | grep -q "\"$val\""; then
    grn "$key contains $val"
  else
    red "$key is missing '$val' in the built Watch app — pull the latest branch and re-run."
    exit 1
  fi
done

# --- Install to the iPhone ---------------------------------------------------

install_to() {
  local ident="$1" app="$2" what="$3"
  hdr "Installing to your $what"
  if xcrun devicectl device install app --device "$ident" "$app" >"$LOG" 2>&1; then
    grn "installed on the $what"
    return 0
  fi
  if grep -qiE "locked|passcode" "$LOG"; then
    stop_and_tap "Unlock your $what (keep it awake), leave it connected."
  fi
  if grep -qiE "developer mode" "$LOG"; then
    if [[ "$what" == "iPhone" ]]; then
      stop_and_tap \
        "iPhone → Settings → Privacy & Security → Developer Mode → ON." \
        "The phone restarts; unlock it afterwards."
    else
      stop_and_tap \
        "WATCH → Settings → Privacy & Security → Developer Mode → ON." \
        "(The Watch has its OWN switch — this is separate from the iPhone's." \
        " The Watch restarts; keep it on your wrist or charger, unlocked.)"
    fi
  fi
  if grep -qiE "not.*trusted|untrusted developer" "$LOG"; then
    stop_and_tap \
      "iPhone → Settings → General → VPN & Device Management →" \
      "tap your Apple ID under Developer App → Trust."
  fi
  red "Install to $what failed — the message:"
  tail -15 "$LOG"
  echo "Paste those lines back to me and I will decide the next step."
  exit 1
}

install_to "$PHONE_ID" "$PHONE_APP" "iPhone"

# --- Install to the Watch ----------------------------------------------------
# Directly, not via the phone->watch transfer — the transfer is the least
# reliable path under a free team and fails with a generic "couldn't install".

if [[ "$WATCH_ID" == "-" ]]; then
  # Try once more: the Watch often becomes visible only after the phone got a
  # development install and Developer Mode settled.
  xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true
  WATCH_ID=$(python3 - "$DEVJSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    kind = ((d.get("hardwareProperties", {}) or {}).get("deviceType") or "").lower()
    if "watch" in kind and d.get("identifier"):
        print(d["identifier"]); break
else:
    print("-")
PY
)
fi
if [[ "$WATCH_ID" == "-" ]]; then
  stop_and_tap \
    "The Watch is not visible to the Mac yet. On the WATCH:" \
    "  Settings → Privacy & Security → Developer Mode → ON  (it restarts)." \
    "Keep the iPhone plugged in and both devices unlocked."
fi

install_to "$WATCH_ID" "$WATCH_APP" "Watch"

# --- Done --------------------------------------------------------------------

echo
grn "DONE. WHOOP Golf is on the iPhone and the Watch."
echo
echo "Before the round:"
echo "  - Open WHOOP Golf on the Watch once; approve Health, Motion, Location."
echo "  - Phone can ride in the cart. If the Watch warns 'GPS looks like your"
echo "    PHONE', put the phone in Airplane Mode — or the yardages measure the cart."
echo "  - Free-team installs expire in 7 days; re-run this script to refresh."

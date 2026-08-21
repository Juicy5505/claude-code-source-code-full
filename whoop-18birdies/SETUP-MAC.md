# Mac + Xcode setup (Kit A watch + Kit C sidecar)

Run this **on your Mac** in Terminal (not in a cloud agent session):

```bash
cd path/to/claude-code-source-code-full/whoop-18birdies
chmod +x setup-mac-xcode.sh
./setup-mac-xcode.sh
```

With your Apple Team ID (optional — avoids the Xcode team picker):

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./setup-mac-xcode.sh
```

Run unit tests too (slower):

```bash
RUN_TESTS=1 ./setup-mac-xcode.sh
```

---

## What the script does

1. Verifies Xcode is installed
2. Regenerates `watch/WhoopGolf.xcodeproj` and `sidecar/WhoopSwingSidecar.xcodeproj`
3. Compile-checks both apps (simulator, no signing)
4. Prints your **LAN IP** (watch) and **Tailscale IP** (iPhone)
5. Creates `~/.whoop-18birdies/ingest-token.txt` if missing
6. Opens **both** projects in Xcode

---

## Xcode — both projects

| Step | WhoopGolf (watch) | WhoopSwingSidecar (iPhone) |
|---|---|---|
| Target | `WhoopGolf` | `WhoopSwingSidecar` |
| Signing | Automatic + your Team | Automatic + your Team |
| Run destination | Your Apple Watch | Your iPhone |
| Upload URL | `http://LAN_IP:8790` | `http://100.x.x.x:8790` (Tailscale) |
| Token | from `~/.whoop-18birdies/ingest-token.txt` | same token |

**Watch cannot use Tailscale.** Phone in cart → Airplane Mode during round (Series 5 GPS trap).

**Sidecar / Pythonista:** Tailscale on Mac + iPhone is enough. **Do not** enable exit nodes.

---

## wb serve

```bash
cd whoop-18birdies
export WB_INGEST_TOKEN=$(cat ~/.whoop-18birdies/ingest-token.txt)
# Loopback default. For phone over LAN/Tailscale:
bun src/cli.ts serve --hostname 0.0.0.0 --allow-insecure-lan
```

LaunchAgent `com.alex.whoop-golf-bridge` uses the same LAN bind when you need the phone to reach the Mac. Uploads land in `~/.whoop-18birdies/watch-sessions/`.

---

## WHOOP sidecar (Kit C) before connecting

1. Close the official WHOOP app
2. Strap in pairing mode (blue LEDs on WHOOP 5)
3. Sidecar → Connect WHOOP → Range or Round

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Signing requires a development team" | `./setup-mac-xcode.sh` with `DEVELOPMENT_TEAM=…` or pick Team in Xcode |
| Watch won't install | Developer Mode on watch; paired iPhone; watchOS 9+ |
| Upload 401 | Token in app must match `WB_INGEST_TOKEN` |
| Watch upload fails on course | Normal — outbox retries on WiFi; or pull `swings.json` via Xcode Devices |
| Sidecar bond fails | WHOOP app closed; forget strap in Bluetooth settings; pairing mode |

More: [watch/WATCH.md](watch/WATCH.md), [sidecar/SIDECAR.md](sidecar/SIDECAR.md).

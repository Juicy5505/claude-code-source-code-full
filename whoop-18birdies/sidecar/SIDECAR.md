# WHOOP IMU Sidecar (Kit C)

iOS app that bonds to your WHOOP strap over BLE, reads **6-axis IMU** via the
community [NOOP](https://github.com/noop-app/noop) protocol, detects golf swings,
tags **phone GPS** yardages, and POSTs the same `swings.json` schema as the
Apple Watch app to `wb serve`.

This is **Kit C** in [SUBSTITUTES.md](../SUBSTITUTES.md).

## Before you connect

1. **Close the official WHOOP app** — the strap holds one BLE bond.
2. Put the strap in **pairing mode** (WHOOP 5.0: flashing blue LEDs).
3. On your Mac: `wb serve` and copy the ingest URL + token.
4. In the sidecar: **Upload settings** → Tailscale `http://100.x.x.x:8790` works on iPhone.

## Build (Mac + Xcode)

```bash
cd whoop-18birdies/sidecar
python3 generate-project.py          # regenerates .xcodeproj
open WhoopSwingSidecar.xcodeproj     # pick your Team, Run on device

# Or from terminal:
./build.sh              # compile check (simulator, no signing)
./build.sh --test       # unit tests
DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh --device
```

Cloud agents cannot run Xcode — CI uses `sidecar-build` on `macos-latest`.

## Modes

| Mode | Motion | GPS | Upload |
|---|---|---|---|
| **Range** | WHOOP IMU | off | `/swings` |
| **Round** | WHOOP IMU | phone CoreLocation | `/swings` + shot distances |

**Phone motion fallback** toggle: uses CoreMotion instead of BLE (simulator / dev).

## Protocol code

Implemented in `WhoopSwingSidecar/BLE/` — not a git submodule fork, but a **minimal
port** of NOOP/my-whoop patterns:

| File | From NOOP / community |
|---|---|
| `WhoopFraming.swift` | CRC8/CRC16/CRC32, 4.0 + 5.0 envelopes |
| `WhoopCommands.swift` | Safe command subset (no destructive opcodes) |
| `WhoopIMUDecoder.swift` | Gen4 type-43 @1917 bytes; Gen5 0x2B/0x15 |
| `WhoopBLEManager.swift` | Bond → handshake → `TOGGLE_IMU_MODE` |

Full reference: [WHOOP_REPOS.md](../WHOOP_REPOS.md).

## Session JSON

Same shape as watch / Pythonista, plus:

```json
{
  "mode": "round",
  "imu_source": "whoop_ble",
  "whoop_generation": "WHOOP 5.0",
  "swings": [ ... ]
}
```

Analysis: `wb coach`, `iphone/analyze.py`, `wb golf` — unchanged.

## Limitations

- **WHOOP 5.0 IMU** is still evolving in community RE; Gen4 path is better tested.
- Bonding displaces the official app until you re-pair in WHOOP.
- Strap has **no GPS** — yardage always from the phone.
- Not affiliated with WHOOP; use at your own risk.

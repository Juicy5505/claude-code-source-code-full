# WHOOP reverse-engineering repos (reference)

Community projects that decode **your own strap** over BLE. None are affiliated
with WHOOP. Use at your own risk (ToS, bond exclusivity, firmware changes).

This list exists so you do not repeat the 2023 search that concluded "no IMU."
That was true **for the no-bond / unknown-checksum path**. These repos go further.

---

## Start here by strap generation

| Strap | Best entry points | IMU? | Language |
|---|---|---|---|
| **WHOOP 4.0** | [noop-app/noop](https://github.com/noop-app/noop), [bWanShiTong/openwhoop](https://github.com/bWanShiTong/openwhoop), [christianmeurer/whoop-reader](https://github.com/christianmeurer/whoop-reader) | Yes — `enable-imu`, historical + live streams | Swift, Rust |
| **WHOOP 5.0 / MG** | [noop-app/noop](https://github.com/noop-app/noop) (`docs/PROTOCOL.md`), [tigercraft4/my-whoop](https://github.com/tigercraft4/my-whoop) (`FINDINGS_5.md`, `protocol/whoop_protocol_5.json`), [b-nnett/goose](https://github.com/b-nnett/goose) | Yes — type 43 `REALTIME_RAW_DATA`, `TOGGLE_IMU_MODE` | Swift, Python |
| **Cross-vendor** | [OpenStrap/research](https://github.com/OpenStrap/research) | Yes (WHOOP 4 + 5 paths) | Python |

---

## What to copy for golf swing detection

Goal: ~100 Hz wrist accel/gyro → same spike detection logic as
`iphone/swing_logger.py` / `watch/SwingDetector.swift`.

| Repo | Copy this | Why |
|---|---|---|
| **noop-app/noop** | `Packages/WhoopProtocol/` (pure Swift decode), `Strand/BLE/BLEManager.swift` (bond + notify) | Production-quality 4.0 + 5.0; schema-driven `whoop_protocol.json` |
| **tigercraft4/my-whoop** | `protocol/whoop_protocol_5.json`, Python parity tests under `server/` | Cross-language decode verification |
| **bWanShiTong/openwhoop** | `openwhoop-algos/` strain/sleep; IMU enable in device layer | Mature 4.0 reference |
| **OpenStrap/research** | Python client, `TOGGLE_IMU_MODE` handling | Quick experiments without forking NOOP |

Key protocol facts (from NOOP `PROTOCOL.md`):

- Packet type **43** (`REALTIME_RAW_DATA`): live IMU batches (~2 packets/s).
- Command **106** (`TOGGLE_IMU_MODE`): payload `[0x01]` to start IMU mode.
- Accel scale **1/4096 g/LSB**; gyro **0.06104 deg/s/LSB** at ±2000 dps.
- **Bond required** for commands; HR Broadcast (`0x2A37`) works without bond.

---

## Cloud / credential-replay (not recommended here)

| Repo | What it does | Why we skip it |
|---|---|---|
| [jacc/whoopkit](https://github.com/jacc/whoopkit) | Private iOS API via password login | Password replay; unstable; no live IMU |
| [totem](https://github.com/search?q=whoop+totem) (various) | Cloud aggregates | No strap IMU stream |

Official OAuth v2 (`wb login`) stays the supported cloud path.

---

## Suggested integration into this project

If you want WHOOP IMU without the Apple Watch:

1. **Sidecar collector (recommended)** — Small iOS app forked from NOOP or
   my-whoop: bond to strap, enable IMU, run swing detector, POST to `wb serve`
   in the same JSON shape as Kit A/B.
2. **Do not port to Pythonista first** — Bonding, framing, CRC, and chunked
   notify reassembly are painful in Pythonista's `cb` module.
3. **Keep HR Broadcast path** — Even with IMU bond, HR Broadcast is simpler for
   live bpm during round; IMU bond may conflict with official WHOOP app.

Track progress in [sidecar/SIDECAR.md](../sidecar/SIDECAR.md).

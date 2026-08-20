# What a WHOOP will and won't give a third party

This records what community reverse-engineering actually found in the WHOOP
device, so design decisions in this project rest on evidence rather than
assumption.

**Last updated:** 2026-08 — community BLE work has moved fast since the 2023
teardown this repo originally cited. Read the timeline below before assuming
"WHOOP has no IMU."

Sources (oldest → newest):

| When | Source | What it established |
|---|---|---|
| 2023 | [bWanShiTong/reverse-engineering-whoop-post](https://github.com/bWanShiTong/reverse-engineering-whoop-post) | WHOOP 4.0 custom service, live HR on `0x2A37`, command checksum **not** recovered → could not trigger activity logging reliably |
| 2024+ | [bWanShiTong/openwhoop](https://github.com/bWanShiTong/openwhoop), [christianmeurer/whoop-reader](https://github.com/christianmeurer/whoop-reader) | WHOOP 4.0 framing, CRC8/CRC32, historical offload, **`enable-imu`** path |
| 2025+ | [noop-app/noop](https://github.com/noop-app/noop), [tigercraft4/my-whoop](https://github.com/tigercraft4/my-whoop), [b-nnett/goose](https://github.com/b-nnett/goose) | WHOOP 5.0/MG **Maverick** protocol (`FD4B0001-…`), full checksum chain, **`REALTIME_RAW_DATA` (type 43) IMU stream**, bond handshake |
| ongoing | [OpenStrap/research](https://github.com/OpenStrap/research), [rusheelraj.com/blog/whoop](https://www.rusheelraj.com/blog/whoop/) | Cross-platform clients, validated decoders, Android port |
| official | [WHOOP developer API](https://developer.whoop.com/), [HR Broadcast](https://support.whoop.com/hc/en-us/articles/360023430193-Heart-Rate-Broadcast) | Read-only physiology cloud API; standard BLE HR profile |

See also: [`WHOOP_REPOS.md`](../WHOOP_REPOS.md) — repos to borrow IMU decode code from.

---

## Three different "ceilings"

Do not mix these up:

| Path | Bonding | IMU / motion | GPS | What this project uses today |
|---|---|---|---|---|
| **Official WHOOP API** | OAuth | **No** | **No** | `wb sync`, recovery/sleep/strain |
| **Standard BLE (no bond)** | None | **No** | **No** | `hr_monitor.py` → `0x180D` / `0x2A37` HR Broadcast |
| **Unofficial BLE RE (bond required)** | Encrypted pair; strap holds **one** bond | **Yes** — 6-axis accel/gyro, ~100 Hz batches | **No** | **Not implemented** (see integration options below) |

---

## The Bluetooth surface

### WHOOP 4.0 — custom service `61080001-…`

The 2023 teardown mapped five characteristics under the vendor service plus
standard Heart Rate (`180D`) and Battery (`180F`):

| Characteristic | Role | Direction | Carries |
|---|---|---|---|
| Heart Rate Measurement `0x2A37` | standard | notify | live bpm (works **unbonded**) |
| `61080002` cmd write | custom | write | framed commands |
| `61080003` cmd notify | custom | notify | command responses |
| `61080004` event notify | custom | notify | event timestamps |
| `61080005` data notify | custom | notify | HR/RR aggregates, historical offload, **IMU when enabled** |
| `61080006` memfault | custom | notify | crash/diagnostic data |

**2023 finding (still true for the no-bond path):** without recovering the
command checksum, you could not reliably trigger `DATA_FROM_STRAP` activity
logging. That is why this project originally stopped at HR Broadcast.

**2024+ finding (changes the picture):** projects like **openwhoop** and
**NOOP** recovered the full 4.0 framing (CRC8 header + CRC32 payload), the
bond handshake, and IMU enable commands. Decoded streams include gravity
(|g| ≈ 1.0 at rest — used to validate accelerometer decode) and 6-axis motion.

### WHOOP 5.0 / MG — Maverick service `FD4B0001-…`

WHOOP 5.0 uses a different service family and CRC16-Modbus header checksum.
Community docs (NOOP `PROTOCOL.md`, `my-whoop` `FINDINGS_5.md`) document:

| Packet type | Name | Notes |
|---:|---|---|
| 40 | `REALTIME_DATA` | live HR / R-R |
| 43 | `REALTIME_RAW_DATA` | live IMU/optical flood (~2/s, ~1.9 KB); payload length `1917` = IMU |
| 51 | `REALTIME_IMU_DATA_STREAM` | IMU stream variant |
| 52 | `HISTORICAL_IMU_DATA_STREAM` | offloaded IMU records |

Commands include `TOGGLE_IMU_MODE` (cmd 106) with payload `[0x01]` to start
IMU streaming. Scale factors reported by NOOP/my-whoop: accelerometer
1/4096 g/LSB; gyro ±2000 dps at 0.06104 deg/s/LSB.

**Bond constraint (both generations):** the strap stores exactly **one**
encrypted BLE bond. While bonded to the official WHOOP app, the command channel
is reserved for that app. Community clients require closing the WHOOP app,
entering pairing mode (flashing blue LEDs on 5.0), and bonding from the
third-party client. HR Broadcast (`0x2A37`) still works without bonding.

---

## What is readable on each path

### Without bonding (what `hr_monitor.py` uses)

1. **Live heart rate** — standard `0x2A37`. Reliable. Enable once: WHOOP app →
   Device Settings → **HR Broadcast → ON**.
2. **Battery** — standard `0x2A19`.

That is the **reliable, zero-friction ceiling** for Pythonista on the course.

### With bonding + unofficial protocol (not in this repo yet)

1. **Live 6-axis IMU** — type-43 `REALTIME_RAW_DATA` or historical IMU offload.
2. **Live HR/R-R on custom stream** — type 40 (NOOP prefers standard `0x2A37`).
3. **Historical biometrics offload** — sleep, strain, skin temp, etc. (what NOOP
   computes locally without the WHOOP cloud).

Tradeoffs: ToS/standing unclear; bond fights with official app; Swift/CoreBluetooth
or a full protocol port required; not viable inside Pythonista's thin `cb` module
without a major rewrite.

### Official cloud API (what `wb` uses)

Recovery, sleep, strain, workouts, cycles — read-only OAuth v2. **No raw IMU,
no live stream, no GPS.**

---

## GPS — still not on the strap

WHOOP 5.0 has **no onboard GPS**; it borrows the phone's location when the
official app is connected. Neither the official API nor BLE reverse engineering
has found a GPS fix coming from the strap itself. Yardage still needs watch GPS
or phone GPS (Kit A or Kit B pocket mode).

---

## Why whoopkit is deliberately not incorporated

`whoopkit` reaches WHOOP's cloud by replaying a **username/password login**
rather than OAuth. Incorporating it would mean:

- putting your WHOOP **password** into this tool, versus the scoped, revocable
  OAuth token the toolkit already uses;
- depending on a library its own author marks **"nothing stable, tested, or for
  production"**, of unknown terms-of-service standing.

That is a downgrade on security, stability, and standing, in exchange for "maybe
more fields." The official OAuth v2 client stays.

---

## Net capability matrix

| Want | Official API | HR Broadcast (no bond) | Unofficial BLE RE (bond) | This project today |
|---|---|---|---|---|
| Recovery, sleep, strain | Yes | — | Yes (local decode) | `wb sync` |
| Live HR during round | — | Yes | Yes | `hr_monitor.py` |
| Live 6-axis IMU / swing motion | **No** | **No** | **Yes** | **No** — phone or watch |
| GPS / yardage | **No** | **No** | **No** | watch or phone GPS |
| Respiration during activity | — | No | Yes (with bond + commands) | not implemented |

---

## Integration options if you want WHOOP-as-swing-sensor

This repo does **not** ship IMU decoding yet. If you want to pursue it, borrow
from the repos in [`WHOOP_REPOS.md`](../WHOOP_REPOS.md):

| Option | Effort | Fits golf round? |
|---|---|---|
| **A — Sidecar iOS app** fork NOOP / my-whoop; write `swings.json` | Medium | Best — native BLE + bond |
| **B — Port decoder to Pythonista** | Very high | Poor — `cb` lacks bonding/framing helpers |
| **C — Keep Kit B as-is** phone motion + WHOOP HR | Done | Stable path today |

Kit B (phone on forearm or in pocket) remains the supported substitute when the
watch stays home. Unofficial WHOOP IMU is a **research path**, not something
this toolkit promises out of the box.

# What a WHOOP will and won't give a third party

This records what community reverse-engineering actually found in the WHOOP
device, so the design decisions in this project rest on evidence rather than
assumption — and so nobody repeats the search expecting a different answer.

Sources:
- BLE protocol teardown: https://github.com/bWanShiTong/reverse-engineering-whoop-post
- Cloud-API SDK (credential replay): https://github.com/jacc/whoopkit
- Official HR broadcast: https://support.whoop.com/hc/en-us/articles/360023430193-Heart-Rate-Broadcast

## The Bluetooth surface, as documented

The strap exposes a standard Heart Rate Service plus one custom service
(`61080002-8d6d-82b8-614a-1c8cb0f8dcc6`) with five characteristics:

| Characteristic | Handle | Direction | Carries |
|---|---|---|---|
| Heart Rate Measurement | `0x2A37` | notify | live bpm (standard profile) |
| `CMD_TO_STRAP` | `0x0010` | write | commands to the device |
| `CMD_FROM_STRAP` | `0x0012` | notify | command responses |
| `EVENTS_FROM_STRAP` | `0x0015` | notify | event timestamps |
| `DATA_FROM_STRAP` | `0x0018` | notify | RR + HR aggregates during activity logging |
| `MEMFAULT` | `0x001b` | notify | crash/diagnostic data |

## What is actually readable by a non-WHOOP app

1. **Live heart rate** — standard `0x2A37`, no authentication. Reliable. This is
   what `hr_monitor.py` uses.
2. **Respiration rate + HR aggregates** — streamed on `DATA_FROM_STRAP` *only*
   while activity logging is active, which must be triggered by writing a
   command to `CMD_TO_STRAP`.

## Why (2) is not implemented here

- The command framing on `CMD_TO_STRAP` uses a **checksum the reverse-engineer
  did not recover**, so the trigger cannot be constructed reliably.
- The same write-up reports that command communication from non-Android devices
  **"doesn't work"** reliably — a firmware-level restriction beyond the protocol.
- Respiration rate is a slow-moving physiological signal; it adds little to a
  golf session that live HR does not already give.

Writing speculative BLE-command code against an undocumented, admittedly-flaky
protocol would be shipping a guess dressed as a feature. If the checksum is ever
published, the honest way in is `CMD_TO_STRAP` -> confirm on `CMD_FROM_STRAP` ->
subscribe `DATA_FROM_STRAP`. Until then, live HR is the reliable ceiling.

## What is confirmed NOT available — the question this project kept asking

The teardown found **no accelerometer, gyroscope, motion, or raw IMU stream over
BLE**. None. This is the finding of people who disassembled the protocol, not an
assumption. It is why the swing sensor in this project is the phone, never the
WHOOP: the strap sits in the perfect place and exposes none of its motion.

SpO2 and skin temperature exist as device sensors but are measured once a day
during sleep, with no documented retrieval path — they reach you only through
the cloud API, already covered by the TypeScript toolkit.

## Why whoopkit is deliberately not incorporated

`whoopkit` reaches WHOOP's cloud by replaying a **username/password login**
rather than OAuth. Incorporating it would mean:

- putting your WHOOP **password** into this tool, versus the scoped, revocable
  OAuth token the toolkit already uses;
- depending on a library its own author marks **"nothing stable, tested, or for
  production"**, of unknown terms-of-service standing.

That is a downgrade on security, stability, and standing, in exchange for "maybe
more fields." The official OAuth v2 client stays. If a *specific* data point you
want is genuinely absent from the v2 API, name it and we can weigh that one
tradeoff deliberately — but credential replay is not the default.

## Net

| Want | Reachable? | How |
|---|---|---|
| Recovery, sleep, strain, overnight HRV | Yes | Official OAuth v2 API (toolkit) |
| Live heart rate during a session | Yes | BLE `0x2A37` (`hr_monitor.py`) |
| Live respiration rate | In theory | `DATA_FROM_STRAP`, blocked by unknown checksum |
| **Raw swing motion / accelerometer** | **No** | **Not exposed by the device to anyone** |

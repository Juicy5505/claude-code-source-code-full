# WHOOP and Apple Watch as substitutes

You asked for the WHOOP to do what the Apple Watch does for golf, so either
one can stand in when you play. Here is the honest answer, then the kit that
actually works **today**.

## The short version

**A WHOOP alone cannot substitute for the Apple Watch as a golf tracker** using
only official APIs or HR Broadcast. **Unofficial BLE reverse engineering** has
since shown the strap *does* stream 6-axis IMU when bonded and commanded — but
this project does **not** ship that yet (see [WHOOP_REPOS.md](WHOOP_REPOS.md)).

| Capability | Apple Watch (this app) | WHOOP — official / HR Broadcast | WHOOP — unofficial BLE RE* |
|---|---|---|---|
| Live heart rate during the round | yes (HealthKit) | yes (BLE HR Broadcast) | yes |
| Overnight recovery / sleep / strain | no (use WHOOP for that) | yes (official API → `wb`) | yes (local decode in NOOP) |
| Onboard GPS | yes (Series 5+) | **no** — borrows the phone's | **no** |
| Swing detection / tempo / impact force | yes (Core Motion ~100 Hz) | **no** on standard path | **yes in theory** — IMU ~100 Hz, bond required |
| Shot-to-shot yardage | yes (wrist GPS) | **no** without the phone | **no** without the phone |
| Background execution with wrist down | yes (`HKWorkoutSession`) | n/a | n/a |

\* Community projects: [noop-app/noop](https://github.com/noop-app/noop),
[tigercraft4/my-whoop](https://github.com/tigercraft4/my-whoop). Not in this repo.

Sources: [`iphone/WHOOP_BLE_NOTES.md`](iphone/WHOOP_BLE_NOTES.md) (updated 2026),
[WHOOP_REPOS.md](WHOOP_REPOS.md), WHOOP docs (no onboard GPS).

So: **WHOOP stays the physiology half.** The golf half needs watch, phone, or
(future) a sidecar app that speaks the unofficial IMU protocol. Kits A and B are
what works **now**.

---

## Two kits that substitute (supported today)

Same analysis pipeline, same `swings.json` shape, same `wb serve` upload, same
`wb golf` / `wb report` afterwards. Pick one before you leave the house.

### Kit A — Apple Watch (preferred when you have it)

```
WHOOP on lead wrist     → recovery / sleep / strain (overnight)
Apple Watch on wrist    → motion, tempo, GPS yardage, live HR
Phone in the cart       → Airplane Mode (Series 5 GPS trap)
```

Build: `whoop-18birdies/watch/` → Run on the watch.
Upload: **Upload settings** on the watch → Mac LAN `wb serve` URL + token.

### Kit B — WHOOP + iPhone (when the watch stays home)

```
WHOOP on lead wrist     → live HR (BLE) + overnight physiology
iPhone on you           → GPS yardage (pocket) OR tempo+force (forearm strap)
```

| Mode | Wear | You get | You lose vs Kit A |
|---|---|---|---|
| **Pocket** | phone in pocket | yardages + WHOOP live HR | tempo, swing force, chips &lt;~33 yd |
| **Arm** | phone on lead forearm | tempo + force + yardages + WHOOP live HR | comfort; must keep screen awake |

Run in Pythonista: `selftest.py` first, then `swing_logger.py`.
Enable **WHOOP app → Device Settings → HR Broadcast → ON** once.

---

## Kit C — WHOOP IMU sidecar (implemented)

Ships in `whoop-18birdies/sidecar/`. iOS app bonds to the strap (NOOP BLE
protocol), streams IMU, detects swings, uses phone GPS, uploads to `wb serve`.
See [sidecar/SIDECAR.md](sidecar/SIDECAR.md).

**Still no GPS from the strap** even with IMU unlocked.

---

## What you cannot get from any kit

- Swing path, face angle, club head speed, spin, launch angle — **launch monitor**.
- Pushing swings into 18Birdies — **no public API**.
- WHOOP writing swing data into its own app — **no write API** on official paths.

Do not expect the **official** WHOOP developer API or HR Broadcast alone to
expose accelerometer data. That requires the unofficial bond + command path above.

---

## Same day, either kit

```bash
wb sync
wb golf          # what the round cost your body (WHOOP)
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/*.json
wb report        # recovery vs scoring (needs CSV scores)
```

Sessions from Kit A and Kit B land in the same store and the same analysis.
That is what "substitute" means here: not that WHOOP becomes a watch out of the
box, but that leaving the watch at home still produces a round this toolkit can
read.

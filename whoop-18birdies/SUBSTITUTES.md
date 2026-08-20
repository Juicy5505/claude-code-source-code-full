# WHOOP and Apple Watch as substitutes

You asked for the WHOOP to do what the Apple Watch does for golf, so either
one can stand in when you play. Here is the honest answer, then the kit that
actually works.

## The short version

**A WHOOP alone cannot substitute for the Apple Watch as a golf tracker.**
Not because this project hasn't got around to it — because the strap does not
expose the sensors that tracking needs.

| Capability | Apple Watch (this app) | WHOOP 5.0 |
|---|---|---|
| Live heart rate during the round | yes (HealthKit) | yes (BLE HR Broadcast) |
| Overnight recovery / sleep / strain | no (use WHOOP for that) | yes (official API → `wb`) |
| Onboard GPS | yes (Series 5+) | **no** — borrows the phone's |
| Swing detection / tempo / impact force | yes (Core Motion ~100 Hz) | **no** — accelerometer exists in hardware, **not exposed** over BLE or API |
| Shot-to-shot yardage | yes (wrist GPS) | **no** without the phone |
| Background execution with wrist down | yes (`HKWorkoutSession`) | n/a (no display, no golf mode) |

Sources already in this repo: [`iphone/WHOOP_BLE_NOTES.md`](iphone/WHOOP_BLE_NOTES.md)
(BLE teardown found only heart-rate service `0x180D` / `0x2A37`), WHOOP's own
docs (no onboard GPS), and WHOOP community feature requests for golf shot
tracking that do not exist as a product.

So: **WHOOP stays the physiology half. The golf half needs either the watch or
the phone.** Those two kits are substitutes for each other.

---

## Two kits that substitute

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

## What you cannot get from either kit

- Swing path, face angle, club head speed, spin, launch angle — **launch monitor**.
- Pushing swings into 18Birdies — **no public API**.
- WHOOP writing swing data into its own app — **no write API**, and no motion
  stream to write.

Do not wait for a firmware unlock of WHOOP's accelerometer. The reverse
engineering of the BLE surface found none; the official developer API is
read-only physiology. If WHOOP ever ships golf shot tracking themselves, that
would be a product feature — not something a client can turn on.

---

## Same day, either kit

```bash
wb sync
wb golf          # what the round cost your body (WHOOP)
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/*.json
wb report        # recovery vs scoring (needs CSV scores)
```

Sessions from Kit A and Kit B land in the same store and the same analysis.
That is what "substitute" means here: not that WHOOP becomes a watch, but that
leaving the watch at home still produces a round this toolkit can read.

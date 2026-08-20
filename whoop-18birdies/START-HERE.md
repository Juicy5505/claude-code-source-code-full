# Start here

You have a **WHOOP**, and either an **Apple Watch** or an **iPhone**. Two kits
that substitute for each other — same analysis afterwards. Full capability
matrix: [SUBSTITUTES.md](SUBSTITUTES.md).

| Kit | Wear | Golf half | Physiology half |
|---|---|---|---|
| **A — Watch** | WHOOP + Apple Watch | watch does motion, tempo, GPS, live HR | WHOOP overnight |
| **B — Phone** | WHOOP + iPhone | phone does GPS (pocket) or tempo (forearm); WHOOP does live HR | WHOOP overnight |

**WHOOP alone cannot do the golf half with what this project ships today.** It
has no onboard GPS. Standard HR Broadcast does not expose IMU data. Community
BLE reverse engineering *has* decoded 6-axis motion from the strap (bond
required) — but that is **not implemented here yet**; see
[WHOOP_REPOS.md](WHOOP_REPOS.md). Details: [SUBSTITUTES.md](SUBSTITUTES.md).

---

## Kit B — no watch (WHOOP + phone)

Three ways to track a round. They stack — nothing stops you using all three —
but the first needs nothing strapped to you and is where to begin.

| | Wear | You get | You do not get |
|---|---|---|---|
| **1. WHOOP only** | just the strap | strain, HR, HR zones, calories, recovery, sleep | anything about the golf |
| **2. Pocket** | strap + phone in pocket | all of the above **plus yardages** + live WHOOP HR | tempo, swing force |
| **3. Arm** | strap + phone on lead forearm | all of the above **plus tempo and force** | comfort |

---

## 1. WHOOP only — zero setup, do this first

Wear the strap and play. WHOOP logs the round itself. Afterwards:

```bash
wb sync          # pull your WHOOP data
wb golf          # the round as WHOOP recorded it
```

```
Golf round — 2026-08-17
  Golf · 4h 15m

During the round
  Strain            9.8
  Average HR        92 bpm
  Max HR            131 bpm
  Energy            750 kcal
  Distance walked   5.6 mi

Heart-rate zones
  Zone 1  (50-60%)   ##########..............  105 min
  Zone 2  (60-70%)   #######.................   75 min

Body going in
  Recovery          64%
  Resting HR        54 bpm
  HRV               61.3 ms
  Slept             6.75 h
```

If WHOOP filed the round under another name — it sometimes guesses "Walking" —
`wb golf --list` shows every activity name in your data. Relabel it in the WHOOP
app as Golf, `wb sync` again.

**This is the whole physiological picture of a round on the official / HR
Broadcast path.** For swing count, tempo, and yardage you still need Kit A
(watch) or modes 2–3 below (phone sensors). Unofficial BLE work shows the
strap's accelerometer *can* be read by third-party apps after bonding — see
[`iphone/WHOOP_BLE_NOTES.md`](iphone/WHOOP_BLE_NOTES.md) — but this toolkit
uses HR Broadcast only for live HR during Kit B. See [SUBSTITUTES.md](SUBSTITUTES.md).

Enable **HR Broadcast** once for Kit B live heart rate:
WHOOP app → Device Settings → HR Broadcast → ON.

## 2. Pocket — yardages, nothing strapped on

Phone in your pocket, WHOOP on your wrist. You stop at the ball, hit it, and
walk after it; the shot's length is the distance between where you stopped and
where you stopped next. Arccos and Shot Scope measure distance the same way.

**On the phone**, in [Pythonista](https://apps.apple.com/app/id1085978097):

1. Copy the files from `iphone/` into Pythonista (see [IPHONE.md](IPHONE.md)).
2. **Run `selftest.py` first.** Thirty seconds, in the garden or on the
   practice green. It answers the only question that matters before you drive
   anywhere: *if I start the logger now, will it record anything?*

   ```
   [PASS] Motion sensor      reading, peak 1.02 g while held
   [PASS] Sample rate        98 Hz
   [PASS] GPS                accuracy 5 m
   [WARN] Auto-Lock          cannot be checked from code
          Settings → Display & Brightness → Auto-Lock → Never. iOS stops
          delivering motion and location the moment the screen sleeps.
   [PASS] Upload target      server reachable at 100.101.102.103

   READY, with 1 thing to be aware of: Auto-Lock
   ```

   Every check it runs corresponds to a way a session has silently recorded
   nothing: motion permission never granted, precise location off, GPS accuracy
   worse than the detector accepts, or an ingest URL that works at home and
   fails at the course.
3. Run `swing_logger.py` → choose **Pocket round (GPS only)**.
4. Play. Stop the script when you finish.

You get a report on the phone, and a log at `~/Documents/pocket_round.json`.

**One habit makes it work:** stand over the ball for a few seconds before you
hit. That pause is what marks the shot. Rake-and-hit gives it nothing to find.

### What pocket mode cannot see

- **Shots under about 33 yards do not appear at all.** A chip and the walk after
  it are indistinguishable from standing still. Your shot count will be short by
  roughly your number of chips and putts. This is why the trackers that do
  measure the short game put a sensor in the club.
- **No tempo, no swing force.** Those need the phone on your arm.

## 3. Arm — tempo and swing force

Same script, choose **Range (arm strap)** or **Round (arm strap + GPS)**, with
the phone on your **lead forearm** (left arm if you play right-handed). There a
swing is roughly 8x your walking motion and easy to pick out; in a pocket it is
nearer 3x and detection gets marginal.

Detection self-calibrates — there is no threshold to set.

Tempo is reported as a ratio and in Tour Tempo's 30fps frame units, so it reads
directly against the published elite groups (21/7, 24/8, 27/9). It runs about 5%
low by construction, so track your own trend rather than comparing the absolute
number to a benchmark.

---

## Getting the data to your Mac

Your phone is on Tailscale, so use the Mac's tailnet address — that works from a
golf course, not just your kitchen.

**On the Mac:**

```bash
tailscale ip -4                       # e.g. 100.101.102.103
export WB_INGEST_TOKEN=$(openssl rand -base64 24)
echo $WB_INGEST_TOKEN                 # copy this
wb serve
```

**In the phone script**, set the two fields near the top of `swing_logger.py`:

```python
INGEST_URL   = "http://100.101.102.103:8790"
INGEST_TOKEN = "the token you copied"
```

The session uploads when you stop the script. If there is no signal it is queued
and retried on the next run — a dead spot never costs you a round.

> `wb serve` speaks plain HTTP with a bearer token. The tailnet supplies the
> encryption it does not have. **Do not port-forward it to the open internet
> instead** — that is the same endpoint with the protection removed.

**You do not need exit nodes for this**, and one of them is worth turning off.
An exit node routes a device's traffic *out to the internet* through another
machine. Reaching `wb serve` is not that: it is peer-to-peer traffic between
two tailnet members, which goes direct and never touches an exit node. Plain
tailnet membership on both devices is the whole requirement.

Using the **iPhone** as an exit node during a round is actively bad: it would
relay another device's internet traffic for four-plus hours while also holding
a GPS fix and running the logger. Turn that one off before you play.

**Then, on the Mac:**

```bash
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/pocket-2026-08-17.json
```

Or, once you have several rounds, pass them all for the trend:

```bash
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/*.json
```

## Putting the two halves together

```bash
wb golf                     # what the round cost your body
wb readiness                # whether you should have played at all
wb report                   # does under-recovery actually show in your scoring
```

### `wb coach` — one round, read back to you

Everything above prints numbers. `wb coach` reads them:

```bash
wb coach                    # the most recent round on file
wb coach --list             # what is stored
wb coach round-2026-08-17   # a specific one
wb coach --json             # the structured read, for piping
```

```
Round of 2026-08-17
===================

Tempo held together all afternoon; contact fell away over the last nine.

20 swings · 294 min · tempo 2.95:1 · 19 shots measured · longest 230.1 yd

Work on
  Late-round contact, not mechanics.
  Drill: nine holes hitting to 80% — the goal is the last three swings
  matching the first three.
```

It needs an Anthropic credential (`export ANTHROPIC_API_KEY=...`, or `ant auth
login`). Nothing else in `wb` does — WHOOP and the watch work without it.

**It cannot see your swing.** No path, no face angle, no club speed, no ball
flight — those need a launch monitor, and the prompt forbids inventing them. It
reads tempo, impact force, yardage spread, front-to-back decline, and your WHOOP
numbers for that day.

Every statistic it cites is computed in `src/coach/facts.ts` and handed over as
a fact sheet, not derived by the model from raw swings — so a wrong average is
a test failure rather than a confident sentence. **If the round carries a GPS
warning, the yardages are removed from that sheet entirely** rather than flagged:
they measure where your cart went, and a number left in the input is a number
something can reason about.

`wb report` needs your scores, which nothing can read automatically — 18Birdies
has no public API. Add them with `wb import-csv` (`wb template` prints the
format) or post them to `wb serve` from a Shortcut.

---

## If you keep things in iCloud

`~/.whoop-18birdies` syncs fine — set `WB_DATA_DIR` to wherever you moved it and
put that in `~/.zshrc`. Note that `tokens.json` holds your WHOOP refresh token,
so syncing it puts that on Apple's servers; leave the directory local if you
would rather it did not.

**Keep the git clone on local disk**, though. iCloud evicts cold files, and
git's object files are exactly that — an evicted object is a missing object.
The repo is already synced by git itself. See
[../second-brain/ICLOUD.md](../second-brain/ICLOUD.md).

## If something does not work

```bash
./run-tests.sh              # is the code itself healthy
wb status                   # are you linked to WHOOP
wb golf --list              # what activities WHOOP actually has
```

**No shots detected in pocket mode.** Almost always one of: GPS was not
permitted, you never stood still long enough, or accuracy was poor under tree
cover. The report says which when it finds nothing.

**No tempo readings in arm mode.** The phase finder needs a still moment at
address. Pause a beat before each swing rather than raking ball to ball. It
returns nothing rather than inventing a number, which is why a missing reading
is honest rather than broken.

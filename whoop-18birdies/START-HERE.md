# Start here

You have a **WHOOP on your lead wrist**, an **iPhone**, and a **Mac**. No Apple
Watch. This is the shortest path from that to real numbers.

Three ways to track a round. They stack — nothing stops you using all three —
but the first needs nothing strapped to you and is where to begin.

| | Wear | You get | You do not get |
|---|---|---|---|
| **1. WHOOP only** | just the strap | strain, HR, HR zones, calories, recovery, sleep | anything about the golf |
| **2. Pocket** | strap + phone in pocket | all of the above **plus yardages** | tempo, swing force |
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

**This is the whole physiological picture of a round, and it is everything WHOOP
can give.** The strap exposes heart rate over Bluetooth and nothing else — no
accelerometer, no gyroscope, to any app including WHOOP's own. So swing count,
tempo, yardage and swing path are not missing features here; they are outside
what the hardware offers anyone. The next two paths add them using the phone.

## 2. Pocket — yardages, nothing strapped on

Phone in your pocket, WHOOP on your wrist. You stop at the ball, hit it, and
walk after it; the shot's length is the distance between where you stopped and
where you stopped next. Arccos and Shot Scope measure distance the same way.

**On the phone**, in [Pythonista](https://apps.apple.com/app/id1085978097):

1. Copy the files from `iphone/` into Pythonista (see [IPHONE.md](IPHONE.md)).
2. Run `swing_logger.py` → choose **Pocket round (GPS only)**.
3. Play. Stop the script when you finish.

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

`wb report` needs your scores, which nothing can read automatically — 18Birdies
has no public API. Add them with `wb import-csv` (`wb template` prints the
format) or post them to `wb serve` from a Shortcut.

---

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

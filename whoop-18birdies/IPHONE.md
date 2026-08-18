# Running this from your iPhone

## What is and isn't possible

**Nothing can read your iPhone's Health data remotely.** HealthKit is on-device
only by Apple's design — there is no cloud API, no server endpoint, and no
connector that exposes it. This isn't a permissions problem to route around;
it's the architecture. Any tool claiming to read your Apple Health from a
server is either using an export file you handed it or isn't doing what it says.

The direction that *does* work is the reverse: **the phone pushes data out.**
Apple Shortcuts can read Health locally and make web requests, so a Shortcut
running on your iPhone can send rounds to the ingest server in this repo. No
Mac, no Xcode, no developer account.

WHOOP needs none of this — the toolkit pulls WHOOP straight from their cloud
API. **The phone's only job is supplying golf rounds.**

---

## Part 1 — the native link (no code, do this first)

This is what makes a round show up in WHOOP at all.

1. **18Birdies → Apple Health.** Start a round to reach the GPS screen on the
   watch, long-press for the options menu, tap **Settings**, set
   **Watch Health Kit** to **On**.
2. **WHOOP → Apple Health.** WHOOP app: **More → App Settings → Integrations →
   Apple Health → Connect**. Allow workouts, heart rate, and sleep.

WHOOP takes the activity's start/end window from Apple Health and scores strain
against its own heart-rate data.

**Caveat:** 18Birdies doesn't tag its activity as an
`HKWorkoutActivityTypeGolf` workout. The window transfers so strain is right,
but it may appear under a generic classification. Re-label it in WHOOP if you
care.

---

## Part 2 — start the ingest server

On whatever machine holds your data (laptop, home server, Raspberry Pi):

```bash
export WB_INGEST_TOKEN=$(openssl rand -base64 24 | tr -d '=+/')
cd whoop-18birdies
bun src/cli.ts serve
```

It prints the LAN URLs your phone can reach:

```
Ingest server listening on port 8790.

Point the iPhone Shortcut at one of these (same Wi-Fi):
  http://192.168.1.24:8790/rounds
```

Check it from Safari on the phone: `http://192.168.1.24:8790/health` should
return `{"ok": true, ...}`. If it doesn't, you're on a different network or a
firewall is blocking the port.

**Endpoints**

| Route | Method | Purpose |
|---|---|---|
| `/health` | GET | Reachability. No auth. |
| `/rounds` | POST | Round JSON from the phone. |
| `/readiness?date=YYYY-MM-DD` | GET | Readiness, preformatted for a notification. |

Authorize with `Authorization: Bearer <token>` **or** `?token=<token>` — the
query param exists because custom headers in Shortcuts are fiddly.

---

## Part 3 — Shortcut A: push a round after you play

In the **Shortcuts** app → **+** → add these actions:

1. **Find Workouts** — `Workout Type` **is** `Golf`, `Limit` **1**,
   sorted by `End Date` descending.
   *If your 18Birdies rounds aren't typed as golf (see the caveat above), filter
   on `Source` **contains** `18Birdies` instead.*
2. **Get Dictionary from Input** isn't needed — instead add **Text** and paste:

```json
{
  "start": "[Start Date]",
  "end": "[End Date]",
  "course": "18Birdies",
  "holes": 18,
  "par": 72,
  "score": [Ask Each Time]
}
```

Replace the bracketed parts with **Magic Variables**: tap the field, pick the
workout's Start Date / End Date. For `score`, insert **Ask Each Time** so it
prompts you for your gross score when the Shortcut runs.

3. **Get Contents of URL**
   - URL: `http://192.168.1.24:8790/rounds?token=YOUR_TOKEN`
   - Method: **POST**
   - Request Body: **File** → select the Text from step 2
   - Headers: `Content-Type` → `application/json`
4. **Show Notification** with the response, so you see it worked.

The server responds `{"accepted": 1, "stored": N, "dates": [...]}`.

**Field names are forgiving.** `Date`, `Course Name`, `Gross`, `Total Putts`,
`Tee Time`, `FIR`, `GIR` all map correctly, and numbers may be strings —
Shortcuts sends them that way constantly. The only hard requirement is a date,
and a start time will do if there's no date field.

**To automate it:** Shortcuts → **Automation** → **+** → **App** → 18Birdies →
**Is Closed** → run this Shortcut. You'll still get prompted for the score.

---

## Part 4 — Shortcut B: readiness before you tee off

1. **Get Contents of URL**
   - URL: `http://192.168.1.24:8790/readiness?token=YOUR_TOKEN`
   - Method: **GET**
2. **Get Dictionary Value** — key `summary`
3. **Show Notification** with that value.

You get:

```
Golf readiness 82/100 (prime). Green light — this is a day to be aggressive off the tee.
```

**To automate it:** Automation → **Time of Day** → 7:00 AM → run this. Add a
**Get Dictionary Value** for `available` and an **If** so it stays quiet when
there's no WHOOP data for the day.

Remember this readiness score is a heuristic defined by this toolkit, **not a
WHOOP metric.** WHOOP publishes no golf readiness score.

---

## Part 5 — tracking the golf itself, on the phone

`iphone/swing_logger.py` runs in **Pythonista** (App Store) — no Mac, no Xcode,
no developer account. It offers three modes, and they differ mainly in what you
have to wear.

### Pocket — yardages, nothing strapped on

**Start here.** Phone in a pocket, GPS only. You stop at the ball, hit it, and
walk after it, so the shot's length is the distance between where you stopped
and where you stopped next. That is how Arccos and Shot Scope measure distance
too, and it needs nothing on your arm.

One habit makes it work: **stand over the ball for a few seconds before you
hit.** That pause is what marks the shot; rake-and-hit gives it nothing to find.

What it cannot see, stated up front rather than left to discover:

- **Shots under about 33 yards do not appear at all.** A chip and the walk after
  it are indistinguishable from standing still, so the shot is invisible rather
  than wrong. Your count will be short by roughly your chips and putts. This is
  exactly why the trackers that do measure the short game put a sensor in the
  club rather than reading where the player stood.
- **No tempo and no swing force.** Those need the arm.

### Range / Round — tempo and swing force

Same script, phone on your **lead forearm** (left arm for a right-handed
golfer). There a swing is roughly 8x your walking motion and easy to separate;
in a pocket it is nearer 3x, where swing detection gets marginal — which is why
pocket mode measures distance by GPS instead of trying to detect swings at all.

**No calibration step.** Detection tracks a rolling median of your own motion
and fires on a multiple of it, so it adapts to wherever the phone actually sits.
An earlier version needed a threshold set by hand; it does not any more. A
`calibrate` mode still exists (`python swing_logger.py calibrate`) but it only
*reports* placement quality — swing peaks 5x your walking peaks is a good spot —
and sets nothing.

### Constraints that apply to all three

- **iOS only delivers motion and location updates to a foreground app.** The
  script must stay on screen for the whole session — set Auto-Lock to Never and
  start on a full battery.
- **It cannot write shots into 18Birdies.** No public API. You get a standalone
  log to correlate afterwards.
- **No swing path, face angle, club speed, launch angle or spin.** Those need
  the club's position in space — a launch-monitor measurement. No wrist or
  pocket sensor gives them, an Apple Watch included.
- **Shortcuts cannot do any of this.** There is no motion or accelerometer
  action in Shortcuts; sensor work needs Pythonista or a native app.

It prints peak magnitudes per second. Set `SWING_THRESHOLD_G` comfortably above
your walking peaks — usually around 60-70% of your swing peak — then:

```
python swing_logger.py
```

Each detection prints with its peak g and GPS fix, and the round is written to
`~/Documents/swings.json`. Set `INGEST_URL` and `INGEST_TOKEN` at the top of the
file to also POST the round to `wb serve`.

A follow-through registers as a second spike moments after the swing, so
detections are gated by a 3-second refractory window; that suppression is
verified against a synthetic trace.

### Shot distance

Distance is **measured, not modelled**. You walk to your ball, so the
straight-line GPS distance from one swing to the next *is* how far the ball
went — the same method Arccos and Shot Scope use. At the end of a round the
logger prints each shot's distance and fits your peak swing g against your
measured carry, so over time it learns what your swing is worth in yards.

The last swing of a round has no successor and gets no distance, and any swing
without a GPS fix is skipped rather than guessed.

### Ball flight animation

```
python ball_flight.py
```

Animates your longest logged shot. Tap to replay.

**Be clear on what is real here:**

| | |
|---|---|
| **Measured** | carry distance (GPS), swing peak g |
| **Assumed** | launch angle (13°) and backspin (2700 rpm) |

The ball lands where yours landed. *How* it got there — the height and
steepness of the arc — is a plausible driver flight, not your flight. A phone
on your arm cannot measure launch angle or spin, and nothing that claims
otherwise from wrist data is telling you the truth.

The physics is drag plus Magnus lift from backspin, integrated numerically.
Lift matters enormously: without it a 250 yd carry would demand ~250 mph of
ball speed instead of ~165, and a 300 yd drive would be unreachable at any
speed. `test_shot_model.py` pins the model against real golf numbers —
ball speeds, apex height — precisely because an earlier drag-only version
passed every internal-consistency check while being badly wrong.

```
python3 test_shot_model.py   # 26 tests, runs anywhere
```

---

## Live WHOOP heart rate during a session (experimental)

Your WHOOP cannot be the swing sensor — its raw accelerometer never leaves
WHOOP's own pipeline — but it can stream one live signal: heart rate, over the
standard Bluetooth Heart Rate Profile.

Enable it once in the WHOOP app: **Menu → Device Settings → HR Broadcast → ON**.
The logger then scans for the strap at session start (12 s) and, if found,
attaches your heart rate to every swing and reports cardio drift across the
session:

```
swing   7   10.9 g  tempo 2.9:1 (26/9)  112 bpm

Heart rate (WHOOP, live): 111 bpm avg over 12 swings
  second half: up 16.8% (102 -> 120 bpm)
```

Rising HR at the same workload is the cardio face of fatigue — read it against
the tempo and distance drift in the same summary. If the strap's broadcast
includes RR intervals, a live rMSSD estimate is printed too (a session
estimate, not WHOOP's overnight HRV score). No strap found → the session simply
runs without heart rate.

The BLE packet parsing and HRV math are tested off-device; the Bluetooth shell
itself (Pythonista's `cb` module) is written to the documented API but, like
the other sensor code, first runs on your hardware.

---

## Reachability off your home network

The server binds `0.0.0.0` and speaks plain HTTP, which is fine on your own
LAN and **not** fine on the open internet. Don't port-forward it.

**Tailscale is the straightforward answer**, and it covers the iPhone (macOS,
iOS and tvOS are supported; watchOS is not). Install it on both the Mac and the
phone, then on the Mac:

```bash
tailscale ip -4        # e.g. 100.101.102.103 — this is your host
tailscale status       # confirms the phone is on the tailnet and reachable
```

Point `INGEST_URL` in `swing_logger.py` — or the Shortcut's URL — at
`http://100.101.102.103:8790`. The tunnel is encrypted end to end and
authenticated per device, so this works from a golf course, not just your
kitchen. Cloudflare Tunnel works the same way if you prefer a hostname.

The bearer token still applies. Over a tunnel the `?token=` form is safe,
because the whole URL is encrypted in transit.

If an upload fails anyway — a dead spot mid-round — the session is already
saved on the phone and queued; the next run retries it before starting.

---

## If you'd rather not run a server

`import-health` handles a one-off backfill with no server at all:

1. Health app → your profile photo → **Export All Health Data** → share the zip
   to your Mac/PC.
2. Unzip and run `bun src/cli.ts import-health path/to/export.xml`.

It streams the file (they run to hundreds of megabytes) and picks up both
golf-typed workouts and anything sourced from 18Birdies. Apple Health carries no
scorecard, so those rounds have no score until you add one — the two sources
merge on a stable id and the richer record wins.

---

## A note on the Shortcuts action names

Apple's Shortcuts documentation is blocked from the environment this was
written in, and action labels drift between iOS versions — "Find Workouts" has
also appeared as "Find Health Samples", and the request-body picker moved in
recent releases. The shapes above are right; if a label doesn't match on your
iOS version, search for the nearest equivalent. The server accepts whatever
reasonable JSON you end up sending, which is why it's built to be forgiving
about key names and value types.

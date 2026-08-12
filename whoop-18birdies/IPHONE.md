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

## Part 5 — swing detection on the phone (experimental)

`iphone/swing_logger.py` approximates what the 18Birdies watchOS app does on an
Apple Watch: watch the accelerometer for the spike a golf swing produces, and
tag each detection with GPS. It runs in **Pythonista** (App Store) — no Mac, no
Xcode, no developer account.

**Read the constraints before you bother:**

- **Placement decides whether this works at all.** Strap the phone to your
  **lead forearm** (left arm for a right-handed golfer). In a pocket the sensor
  mostly sees hip rotation, which is too close to a practice swing or climbing
  out of a cart to separate reliably. This is why 18Birdies built it for the
  watch and tells you to wear it on the lead wrist.
- **iOS only delivers motion updates to a foreground app.** The script must stay
  on screen for the whole round — set Auto-Lock to Never and start on a full
  battery. The Apple Watch gets a background workout entitlement a script never
  will.
- **It cannot write shots into 18Birdies.** No public API. You get a standalone
  log to correlate afterwards.
- **It detects that a swing happened and where you stood.** Not swing path, not
  face angle, not club head speed — an arm-worn phone cannot measure those.
- **Shortcuts cannot do any of this.** There is no motion or accelerometer
  action in Shortcuts; sensor work needs Pythonista or a native app.

**Calibrate first.** The threshold depends on your tempo and exactly where the
phone sits, so the shipped default is a starting point, not a setting:

```
python swing_logger.py calibrate   # 30s: walk, then take a few full swings
```

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

---

## Reachability off your home network

The server binds `0.0.0.0` and speaks plain HTTP, which is fine on your own
LAN and **not** fine on the open internet. Don't port-forward it.

To use it away from home, put it behind a tunnel that terminates TLS
(Tailscale, Cloudflare Tunnel, or similar) and point the Shortcut at the HTTPS
hostname. The bearer token still applies; over a tunnel the `?token=` form is
safe because the URL is encrypted in transit.

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

# Apple Watch swing tracker (Series 5 and up)

The honest best version of what you asked for: the swing sensor lives on your
**lead wrist**, always on you, and — unlike the phone — it runs in the
**background** with the screen off, because a watchOS workout session keeps it
alive. Motion, tempo, GPS shot distance, and live heart rate, with nothing in
your hands during the round.

**WHOOP still matters, and this is the "together" setup:**

| Device | Job |
|---|---|
| **Apple Watch** | swing detection, tempo, GPS distance, live HR — during play |
| **WHOOP** | recovery, sleep, strain → readiness — overnight, via the TypeScript toolkit |

The watch tells you *how you swung and scored*; WHOOP tells you *whether your
body was ready and what the round cost you*. Both on your body.

---

## What you need

- A **Mac with Xcode** (free from the App Store). This is the one hard
  requirement — watchOS has no on-device coding app like Pythonista, so custom
  watch apps are built in Xcode and installed over the paired iPhone/Wi-Fi.
- An **Apple ID**. The free tier works; the only cost is that a free-provisioned
  app **expires after 7 days** and must be rebuilt onto the watch. A paid
  Apple Developer account ($99/yr) lifts that to a year.
- Your **Series 5** paired to your iPhone. It runs up to watchOS 9, which has
  everything this uses (Core Motion device-motion at 100 Hz, HealthKit workout
  sessions, GPS).

The swing-detection maths is a faithful port of the Python in
`../iphone/swing_metrics.py`, which is the tested reference (93 tests). If you
ever change the algorithm, change it there first, then mirror it into
`SwingDetector.swift`.

---

## Build it (about 15 minutes, once)

1. **New project** in Xcode → **watchOS** → **App**. Name it `WhoopGolf`,
   interface **SwiftUI**, language **Swift**. Uncheck test targets if you like.
2. In the Watch App target's folder, **delete** the auto-generated
   `ContentView.swift` and the `App` file, then **drag in** all the `.swift`
   files from `WhoopGolfWatchApp/` here:
   - `WhoopGolfApp.swift`  (app entry + mode picker)
   - `SessionView.swift`  (the live dashboard + wiring)
   - `SwingDetector.swift`  (detection + tempo — the ported logic)
   - `MotionManager.swift`  (100 Hz Core Motion loop)
   - `WorkoutManager.swift`  (background execution + live HR)
   - `LocationManager.swift`  (GPS for shot distance)
   - `SessionModel.swift`  (records swings, saves, uploads)

   When dragging, tick **Copy items if needed** and add them to the Watch App
   target.
3. **Set the deployment target — do not skip this.** Select the blue project
   at the top of the sidebar → the **Watch App** target → **General** tab →
   **Minimum Deployments** → set **watchOS 9.0**.

   Xcode defaults new projects to the newest watchOS. An **Apple Watch Series 5
   tops out at watchOS 10** (watchOS 11 dropped support for it), so a default
   target builds cleanly and then refuses to install, with an unhelpful
   "does not support the minimum OS version" error. The code's real floor is
   watchOS 8.5, so 9.0 is a safe setting that still runs on a Series 5.

4. **Signing & Capabilities** (Watch App target):
   - **Signing** → pick your Apple ID team. Xcode auto-manages the profile.
   - **+ Capability → HealthKit**.
   - **+ Capability → Background Modes** → tick **Workout processing**.
5. **Info.plist** (Watch App target) — add these usage strings, or the app
   crashes the first time it asks for access:
   - `NSHealthShareUsageDescription` → "Reads heart rate during a round."
   - `NSHealthUpdateUsageDescription` → "Records the round as a workout."
   - `NSMotionUsageDescription` → "Detects your golf swings."
   - `NSLocationWhenInUseUsageDescription` → "Measures shot distances by GPS."
6. **Run**: select the Watch App scheme and your watch as the destination, press
   ▶. The first install, unlock the watch and, in **Settings → General → VPN &
   Device Management** on the *watch* (or via the prompt), **trust** your
   developer certificate.

That's it. The app appears on the watch; launch it from the app grid.

---

## Using it

Open **WhoopGolf** on the watch, pick **Range** or **Play a round**, allow the
health/motion/location prompts once. Detection self-calibrates — no threshold to
set. Each swing buzzes your wrist and updates the readout: force, tempo (ratio
and Tour Tempo frames), swing count, live HR, and running consistency. Tap
**Stop & Save** to finish.

The session is written on the watch as `swings.json` / `range_session.json` — the
**same format** the phone logger produces, so `../iphone/analyze.py` and
`round_report.py` read it identically.

## Getting the data off the watch

Set two fields at the top of `SessionModel.swift` before building:

```swift
var ingestURL = "http://192.168.1.24:8790/swings"   // your `wb serve` host
var ingestToken = "your-token"
```

On **Stop & Save** the watch POSTs the session to the `/swings` endpoint (added
to `wb serve` for exactly this), which stores it under
`~/.whoop-18birdies/watch-sessions/<mode>-<date>.json`. Then on that machine:

```bash
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/range-2026-08-12.json
# or several, for the trend:
python3 iphone/analyze.py ~/.whoop-18birdies/watch-sessions/*.json
```

Leave `ingestURL` empty to keep sessions on the watch only and pull them off
another way.

### If your phone is wired and VPN'd to the Mac

That changes what host to point at, and makes this work off your home network —
which matters, because a golf course is not your home network.

**Over the VPN.** Use the Mac's VPN-assigned address rather than its LAN one:

```bash
# on the Mac, find the address the VPN gave it
ifconfig | grep -A2 'utun\|tun0' | grep 'inet '
```

Then set `ingestURL = "http://<that-address>:8790/swings"`. The watch reaches it
from anywhere the VPN reaches, and — importantly — this is the *right* way to do
it. `wb serve` speaks plain HTTP with a bearer token; a VPN gives you the
encrypted transport it does not have. **Do not port-forward it to the open
internet instead.** That is the same endpoint without the encryption.

**Over the wire.** USB gets the data off the *phone*, not the watch — the watch
has no wired path at all, so the VPN route above is the only one for watch
sessions. For the Pythonista phone logger, USB is the simplest option there is:
connect the iPhone, open Finder → the device → **Files** → **Pythonista 3**, and
drag `swings.json` straight out. No server, no token, no network.

The watch still syncs its own copy through the paired iPhone regardless; the
upload is a convenience, not the only path.

---

## How the round reaches WHOOP

You do not need a WHOOP write API — there isn't one. The path is Apple Health:

```
Apple Watch  ──HKWorkoutSession (golf)──▶  Apple Health  ──imports──▶  WHOOP
```

WHOOP automatically imports activities logged by other apps from Apple Health,
using the activity's start/end window and classification alongside its own
heart-rate data to log the round and compute strain. This app finishes its
session as a **golf** workout, so the round shows up in WHOOP on its own.

Two things to enable once, or it silently won't work:

1. **WHOOP app** → More → App Settings → Integrations → **Apple Health** →
   Connect, and allow workouts.
2. On the **watch**, allow the Health and Location prompts the first time the
   app runs. The app shares **Workout Routes**, which is the specific permission
   WHOOP needs to import your GPS track — without it the round imports but the
   map does not.

Range mode deliberately records no route: standing still produces GPS noise, not
a track.

### What WHOOP does and does not get

| | |
|---|---|
| **WHOOP receives** | the round as a golf activity, its time window, strain from WHOOP's own HR, and the GPS route |
| **WHOOP does not receive** | swing count, tempo, shot distances — HealthKit workouts have no field for them, and WHOOP has no write API |

That split is the point of this project rather than a shortcoming: WHOOP holds
the physiology, the swing analytics live in the log this app writes, and
`iphone/analyze.py` joins the two.

---

## Honest limits

- **Not compiled here.** This Swift was written on Linux with no Xcode, so it
  has never been built. The detection *logic* it ports is fully tested in
  Python and the *output format* is verified to round-trip through `/swings`
  into `analyze.py`, but the watchOS API calls (HealthKit, Core Motion,
  SwiftUI) get their first compile on your Mac. Expect to fix a small thing or
  two — API signature nits are normal on first build. Paste me any Xcode error
  and I will correct it.

  A pre-build audit did find and fix four real defects that no compiler would
  have caught, all of them silent in the worst way:

  | Was | Effect |
  |---|---|
  | `autosave` used `replaceItemAt`, which requires the destination to exist | the file was never created, so **every session was lost** unless uploaded |
  | `ISO8601DateFormatter` defaulted to UTC | an evening round filed under **tomorrow**, dropping out of the WHOOP join |
  | motion ran on a default (concurrent) `OperationQueue` | samples could arrive **out of order**, corrupting the tempo maths |
  | `stop()` finished the route in a callback after the view dismissed | the manager deallocated first, so the round reached WHOOP **without its GPS** |

  The first one is why this audit was worth doing before your first round rather
  than after it.
- **Still no swing path / face angle / club speed.** One wrist sensor measures
  *when* and *how hard*, not where the clubface points. That is a launch-monitor
  measurement, on the watch exactly as on the phone.
- **The 7-day free-provisioning expiry** is Apple's rule, not this app's. Rebuild
  from Xcode when it lapses, or use a paid account.
- **watchOS floor is 8.5**, verified by scanning every API used against its
  availability: the newest requirements are the async `requestAuthorization`
  (8.5) and a handful of SwiftUI modifiers (8.0). HealthKit types are built with
  `quantityType(forIdentifier:)` rather than the `HKQuantityType(.heartRate)`
  shorthand precisely because that shorthand needs watchOS 9. A Series 5 runs up
  to watchOS 10, so it clears this comfortably — provided the deployment target
  is set as in step 3.

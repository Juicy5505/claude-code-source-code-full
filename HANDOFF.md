# Handoff — read this first

You are picking this up in a **local** Claude Code session on a Mac (VS Code or
Terminal — same thing). Your Mac is still needed for one thing CI cannot do:
`./build.sh --device`, to install on the Series 5.

**The watch app compiles and its Swift tests pass** — the `Watch (xcodebuild)`
CI job on `macos-latest` builds it, runs `SwingDetectorTests` in a watchOS
simulator, and verifies the shipped `Info.plist` on every push. That used to be
the open question and no longer is.

What is still unverified is everything a simulator cannot exercise: this has
never run on a physical Apple Watch. The phone-GPS trap, background suspension
with the wrist down, and five hours of battery are all untested.

Branch: `claude/whoop-18birdies-integration-n630ma` · PR #1 (draft).

```bash
git pull origin claude/whoop-18birdies-integration-n630ma
```

---

## 1. Do this first (Mac)

```bash
cd whoop-18birdies/watch
./build.sh
./build.sh --test
```

That compiles the watchOS app against the **simulator** SDK with signing off.
No Apple Developer team, no provisioning profile, no paired watch — so it gets
past `Signing for 'WhoopGolf' requires a development team` and actually reports
Swift errors.

When you want it on the physical watch:

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh --device   # ten chars, developer.apple.com → Membership
```

**CI now runs the same two commands on `macos-latest`** (job `watch-build` in
`.github/workflows/whoop-18birdies.yml`). If that job is green on your PR, the
Swift compiles. If it is red, open the log — `build.sh` prints only the error
lines, not the full clang invocation wall.

### What reading caught, and what only building caught

Four actor-isolation / import defects were found and fixed by reading before any
compiler ran. Two things reading could NOT have caught, both found by the macOS
CI job on its first runs:

- **Xcode was silently discarding the background modes.** They were
  `INFOPLIST_KEY_WKBackgroundModes` / `INFOPLIST_KEY_UIBackgroundModes`, which
  are not names Xcode recognises; it drops unrecognised `INFOPLIST_KEY_`
  settings without a warning, and the built bundle came back with *no background
  modes at all*. Without them the round stops recording when your wrist drops,
  and the app throws on the first tee. They now live in a real
  `WhoopGolfWatchApp/Info.plist`, and `build.sh` reads all six required keys
  back out of the built app so this cannot regress quietly.
- A Swift frontend crash on multiline string interpolation in the tests.

A fifth defect found by reading (bad peak index silently returning wrong mechanics)
was caught in Python and mirrored in Swift. Still run `./build.sh` locally once
before your first round — API signature nits are normal on first compile.

---

## 2. What the app is

Golf tracking where **the Apple Watch does all of it** and the phone does none
of it. That is a hard requirement, not a preference:

- Phone lives in the **cart**. It must never be the sensor.
- WHOOP on the **left (lead) wrist**, doing physiology only.
- Watch on the wrist does motion, tempo, GPS, heart rate, shot distance.

There is **no `WatchConnectivity` / `WCSession` anywhere** in the watch app, by
design. It is `WKWatchOnly = YES` — an independent watchOS app with no iOS
companion. If you find yourself adding an iPhone target, stop and re-read this.

### The trap that motivated `GPSSourceCheck.swift`

An Apple Watch **Series 5 uses the paired iPhone's GPS whenever the phone is in
Bluetooth range.** Apple only changed this for the Ultra, Series 8, and SE (2nd
gen). With the phone in the cart, every shot would be measured *cart-to-cart* —
plausible-looking yardages that are measurements of where the cart went. Nothing
errors and nothing warns.

There is no API to force the watch's own receiver, so it is inferred: if the
accelerometer says the wrist has been walking for 60 s but the reported position
moved less than 25 m, the fix is not describing the wrist. The warning is
persisted into the session file as `gps_warning`, so a suspect round is still
identifiable weeks later.

**Practical fix for the user: put the phone in Airplane Mode during the round.**

---

## 3. Unresolved — needs the user's answer before more feature work

There are **two competing Xcode projects**, and only one should survive:

| | `whoop-18birdies/watch/WhoopGolf.xcodeproj` | `whoop-18birdies/apple/WhoopGolf.xcodeproj` |
|---|---|---|
| Author | this branch | Codex, branch `codex/iphone-golf-app` |
| Shape | watch-only, `WKWatchOnly = YES` | iOS app + watch companion |
| On this branch? | yes | **no** — lives in `~/.codex/worktrees/7acc/`, never pushed |
| Matches "nothing through my iPhone"? | yes | no |

The user was last seen building the **Codex** one in Xcode, which is why the
signing error appeared on a target named `claude`. Ask which is canonical before
building on either. Do not merge them silently.

---

## 4. Map of the repo

```
whoop-18birdies/
  START-HERE.md          three tracking modes, ordered by how little you wear
  run-tests.sh           every suite, one command
  src/                   TypeScript: WHOOP OAuth v2 client, correlation, `wb` CLI
    link/golfRound.ts    `wb golf` — WHOOP-only round report, joins on LOCAL date
    whoop/oauth.ts       single-flight refresh (a single-use token, rotated once)
    store.ts             path-traversal-safe writes, mode 0600
  iphone/                Python: pocket-mode GPS yardage + the tested reference
    swing_metrics.py     THE source of truth for swing maths (Swift ports from it)
    shot_detect.py       stop-to-stop yardage, ~33 yd resolution floor, documented
    gen_swing_vectors.py generates the golden vectors the Swift tests replay
  watch/
    build.sh             ← start here
    generate-project.py  writes WhoopGolf.xcodeproj (deterministic, validated)
    test_generate_project.py   parses the .pbxproj as a plist and checks settings
    WhoopGolfWatchApp/   the ten Swift files + HealthKit entitlements
second-brain/            the Obsidian memory CLI (`brain`)
tools/share.py           publish files through the repo, with credential redaction
```

### The Python is the reference, the Swift is the port

`SwingDetector.swift` is a hand port of `iphone/swing_metrics.py`. The Python has
the tests; `swing_vectors.json` pins the Swift to what the Python actually
produces. **Change the algorithm in the Python first**, then regenerate:

```bash
python3 iphone/gen_swing_vectors.py           # regenerate
python3 iphone/gen_swing_vectors.py --check   # is the committed copy stale?
```

Two rounding traps are load-bearing here: Python's `round()` is banker's
rounding, Swift's `.rounded()` is half-away-from-zero. Every rounded value in the
Swift uses `.rounded(.toNearestOrEven)` for that reason. Do not "simplify" it.

---

## 5. Tests — all currently green

```bash
cd whoop-18birdies && ./run-tests.sh    # 129 TS + 203 Python + 24 project + vectors
python3 second-brain/test_brain.py      # 46
python3 tools/test_share.py             # 16
cd whoop-18birdies/watch && ./build.sh --test   # watch Swift tests (Mac / CI)
cd whoop-18birdies/sidecar && ./build.sh --test # sidecar Swift tests (Mac / CI)
```

The ubuntu CI job runs the first three. macOS CI runs watch and sidecar `./build.sh --test`.

---

## 6. Settled questions — don't re-litigate these

Each of these cost real time to establish. They are not open.

- **WHOOP 5.0 has no GPS.** It borrows the phone's. (WHOOP's own statement.)
- **Official API + HR Broadcast expose no IMU.** Kit B uses that path
  (`hr_monitor.py`). Community RE (NOOP, my-whoop) decodes 6-axis IMU with bond +
  `TOGGLE_IMU_MODE` — see `WHOOP_BLE_NOTES.md`. **Kit C sidecar** implements it:
  `whoop-18birdies/sidecar/`.
- **Supported golf substitutes:** Kit A (watch), Kit B (phone + HR Broadcast),
  Kit C (sidecar IMU + phone GPS). See `SUBSTITUTES.md`.
- **Swing path and face angle need a launch monitor.** No wrist or pocket sensor
  produces them. Do not promise them in the UI.
- **18Birdies has no public API.**
- **Tailscale has no watchOS client** — macOS/iOS/tvOS only. The watch reaches
  `wb serve` over plain WiFi or not at all, which is why uploads go through an
  on-watch outbox that survives a course with no signal.
- **A cloud session cannot reach local hardware** over USB-C, Tailscale, iCloud,
  or an MCP server that runs locally. That is what this handoff exists to solve.

## 7. Security constraints in force

- Never fabricate WHOOP endpoint paths. If a call 404s, override via
  `WHOOP_API_BASE` / `WHOOP_AUTHORIZE_URL` / `WHOOP_TOKEN_URL`.
- `wb serve` speaks plain HTTP. LAN or tailnet only — **never port-forward it.**
- OAuth tokens and caches are written at mode `0600`. Keep it that way.
- `tools/share.py` must keep refusing `tokens.json`, `.env`, and SSH keys.

---

## 8. The Obsidian second brain

Standing instruction from the user: *"everything should be written down in
Obsidian. That is your memory."* The vault is per-project and lives on **their**
machine, so it is not in this repo and was never initialised in the cloud
container. On the Mac:

```bash
./second-brain/brain init      # binds a vault to this project
./second-brain/brain where
./second-brain/brain recall    # what the last session was doing
```

`second-brain/ICLOUD.md` matters: the **vault** can live in iCloud, the **git
repo must not**. iCloud eviction replaces file contents with `.name.icloud`
placeholders and removes the real filename — which corrupts a `.git` directory
in a way that looks like repository damage. `brain doctor` detects evicted files.

---

## 9. Where to pick up

1. `./build.sh --device` on your Mac to install on the Series 5.
2. **Upload settings** on the watch: enter your Mac's LAN `wb serve` URL and token.
3. Ask the user: `watch/` or `apple/` — which project is real?

# Mac / device install — WhoopGolf + WhoopGolfWatch (D19)

## 0. The one-command path (start here)

```bash
git pull origin cursor/cloud-agent-1787290942317-17qh4
cd whoop-18birdies/apple && ./ship-to-watch.sh
```

The script does every Mac-side step itself: finds your signing team, builds
both apps, finds the plugged-in iPhone and the paired Watch, installs to both,
and verifies the built Watch bundle carries the background modes a round needs.
When it reaches a step Apple reserves for a human — Developer Mode, trusting
your certificate — it STOPS and prints the exact tap, in words. Make the tap,
run it again. Safe to re-run any number of times.

Everything below is the manual path, kept for when the script's message says
to come here.

**Status:** Watch OS gate **CLEARED** (Alex confirmed 2026-08-21; device **10.6.2** ≥ min **9.0**). Physical companion install is **allowed now**.  
**Project:** `whoop-18birdies/apple/WhoopGolf.xcodeproj` (not Kit A at `whoop-18birdies/watch/`)  
**Bundle:** `com.alex.whoopgolf` · Watch `com.alex.whoopgolf.watchkitapp` · home-screen name **WHOOP Golf**  
**Wear:** Apple Watch on the **right (trail)** hand when golfing.

**Goal:** download the **finished** integrated companion onto the Watch in one step — scheme **WhoopGolf** → Run to the physical iPhone embeds **WhoopGolfWatch**.

This runbook is for Alex on a Mac with Xcode. Linux cloud agents cannot perform these steps.

---

## 0. Green-build proof (if not yet run)

From repo root:

```bash
bash whoop-18birdies/apple/scripts/mac-d19-verify.sh
```

Expect `==== D19 MAC VERIFY SUCCEEDED ====`. Paste SUCCEEDED logs so orchestration can clear **NO_XCODE** / **XS-MAC**.  
Do **not** use `-derivedDataPath` under iCloud `~/Documents` (LESSONS L3).

---

## 1. Open the right project

1. Open **`whoop-18birdies/apple/WhoopGolf.xcodeproj`** in Xcode.
2. Confirm schemes **WhoopGolf** (iPhone) and **WhoopGolfWatch** (Watch companion / WatchSupport) exist in this project.
3. Do **not** install from `whoop-18birdies/watch/WhoopGolf.xcodeproj` (Kit A) — that is not the golfer-facing target.

---

## 2. Personal Team signing

1. Select the **WhoopGolf** target → Signing & Capabilities.
2. Team: your **Personal Team** (do not commit team IDs into the repo).
3. Confirm **WhoopGolfWatch** (and WatchSupport if separate) use the same Personal Team / automatic signing.
4. Bundle ID stays `com.alex.whoopgolf` (+ Watch companion suffix as already configured).

---

## 3. Pair phone + Watch, then Run

1. Unlock iPhone; unlock Apple Watch; keep both near the Mac.
2. In Xcode, destination: your physical **iPhone** (not only Simulator).
3. Scheme: **WhoopGolf** → **Run** (⌘R). This installs the phone app and should push/install **WhoopGolfWatch** to the paired Watch.
4. On the Watch: look for **WHOOP Golf** / companion; open once and allow Health / workout prompts if asked.
5. If the Watch app does not appear: Xcode → Window → Devices and Simulators → select Watch → confirm install, or Run with the Watch destination selected for WhoopGolfWatch.

---

## 3b. If Xcode says it can’t install (troubleshoot in order)

1. **Copy the exact error** from the Xcode Report navigator (red install failure) and paste it back — wording matters.
2. **Signing (most common):** WhoopGolf **and** WhoopGolfWatch → Signing & Capabilities → Team = **your Personal Team**, Automatically manage signing **On**. Bundle IDs stay `com.alex.whoopgolf` / `com.alex.whoopgolf.watchkitapp`. (Repo no longer ships a hardcoded team ID.)
3. **Developer Mode / Trust — on BOTH devices.** The Watch has its own switch, and without it the Watch refuses developer apps with a generic "couldn't install/download":
   - iPhone → Settings → Privacy & Security → **Developer Mode** → On (reboots the phone).
   - **Watch** → Settings → Privacy & Security → **Developer Mode** → On (reboots the Watch). If the switch is missing, run once to the iPhone from Xcode first — it appears after the Watch has seen a development install attempt.
   - iPhone → Settings → General → VPN & Device Management → **Trust** your developer cert. Companion transfers fail quietly until this is done.
   - Unlock the **Watch** (on wrist or on charger) during install.
3a. **"The Watch couldn't download the app" specifically:** stop using the phone→Watch transfer — it is the least reliable path with a free Personal Team. Install DIRECTLY instead: in Xcode pick scheme **WhoopGolfWatch**, destination **your Apple Watch (via your iPhone)**, and Run. That pushes the watch app with its provisioning profile in one step, and its failure messages are specific where the transfer's are generic. Run the **WhoopGolf** scheme to the iPhone separately; the pairing between the two apps comes from the bundle ids, not from installing together.
4. **Delete old copies:** Delete WHOOP Golf / Whoop Swing / any Kit A Watch app from phone **and** Watch, then Run again.
5. **Clean:** Xcode → Product → Clean Build Folder; Derived Data must **not** live under iCloud `~/Documents` (LESSONS L3).
6. **Free Personal Team limits:** Free accounts cap ~3 apps / 7-day profiles. Delete unused personal-team apps, then retry.
7. **Watch pairing:** Watch app on iPhone shows Watch connected; Xcode Devices lists Watch under the iPhone. Re-pair if the Watch is greyed out.
8. Pull latest branch. The Watch Info.plist carries `UIBackgroundModes = [location]` and nothing else in that key: `audio`/`remote-notification` are gone (plausible install blockers), but `location` is REQUIRED — `allowsBackgroundLocationUpdates = true` throws and kills the app at round start without it. Do not "fix" an install failure by deleting that key again.

---

## 4. After phone reboot (Personal Team)

If the app shows as **unavailable** after a reboot:

1. iPhone → Settings → Privacy & Security → **Developer Mode** → On (restart if prompted).
2. Trust the developer certificate again when prompted (Settings → General → VPN & Device Management).
3. Re-open WHOOP Golf from the home screen; re-launch the Watch companion if needed.

---

## 5. Trail-right wear

Wear the Watch on the **right (trail)** hand for golf — not the left/lead hand. In-app wrist preference defaults to trail-right; keep it there for path polarity.

---

## 6. Prove dual-gate (Start Round)

D19: **both** Watch session readiness **and** WHOOP readiness are required.

1. Open WHOOP Golf on the phone → Round / Start.
2. With only one wearable ready (Watch session missing **or** WHOOP not ready): **Start Round stays disabled**.
3. Satisfy hybrid: Watch live-capture session available **and** WHOOP swing source / delayed-import readiness (Check for WHOOP swings / cached readiness — **never** live `TOGGLE_IMU` / Arming).
4. Confirm Start Round enables only when both sides satisfy `DualWearableRequirement`.

WHOOP pairing / delayed import is Alex-only on device; cloud cannot pair hardware.

---

## 7. Finished payload on Watch (confirm after Run)

“Downloaded everything finished” means all of the following:

1. **Devices and Simulators** lists your iPhone and paired Watch (**10.6.2**).
2. Watch home screen shows **WHOOP Golf** (companion from `apple/` embed — not Kit A).
3. Opening the Watch app shows the round face surface (path / improver / yards / HR / hole / club code / ball-start when phone publishes `WatchLiveFace` v3).
4. Club **picker** and dual-gate Start Round stay on the **iPhone**; Watch **displays** phone-published club / yards / path.

Paste back to cloud: Run succeeded + WHOOP Golf visible on Watch → STATUS marks **on-device install confirmed**.

---

## 8. What this does *not* claim

- Cloud agents do **not** claim WhoopGolfWatch is already installed on your Watch until you confirm.
- `mac-d19-verify.sh` proves **compile + unit tests** only — not on-wrist install.
- Never commit Apple team IDs or WHOOP ingest tokens.

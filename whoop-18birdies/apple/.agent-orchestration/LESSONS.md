# LESSONS — WHOOP Golf error-fixer

Search this file before re-deriving a fix.

---

## L1 — A phone↔Watch contract type must live in `Shared/`, not in `WatchSupport/`

**Symptom**
```
WatchSessionTransfer.swift:11: error: cannot find type 'WatchRoundContext' in scope
WatchSessionTransfer.swift:13: error: cannot find 'WatchCoachingCue' in scope
```
Only the **WhoopGolfWatch** target fails; the iOS target builds fine.

**Root cause**
`WatchSupport/WatchSessionReceiver.swift` is an iOS-only file (it is a
`WCSessionDelegate` living in the phone app) and is a member of the **WhoopGolf**
target only. Any `struct`/`enum` declared inside it is invisible to watchOS —
even though both sides must encode and decode the exact same envelope.

**Fix**
Extract the wire contract into its own file under `apple/Shared/` and add that
file to **both** target Sources phases:

- `Shared/WatchRoundContext.swift` — `WatchRoundContext`, `WatchRoundContextError`,
  `WatchRoundApplicationContextCodec`
- `Shared/WatchCoachingCue.swift` — `WatchCoachingCue`, `WatchCoachingCueCodec`

**Rule of thumb:** if the type name appears on both sides of a WCSession
`applicationContext` / `transferUserInfo` payload, it belongs in `Shared/`.

**Anti-pattern (do not do this):** adding `WatchSessionReceiver.swift` itself to
the watch target and wrapping the phone half in `#if os(iOS)`. It compiles, but
it drags `WCSessionDelegate`, file recovery, and Application Support I/O into the
watch module and every later edit has to re-litigate the fence.

---

## L2 — `Shared/` does not mean "compiles on watchOS"

**Symptom**
```
Shared/PhoneYardageBridge.swift:126: error: cannot find type 'GolfSwingMetrics' in scope
Shared/PhoneYardageBridge.swift:15:  error: cannot find type 'GolfHoleGeometryAttribution' in scope
Shared/PhoneYardageBridge.swift:6:   error: type 'GolfHoleGreenTargets' does not conform to protocol 'Codable'
```
(The `does not conform to Codable` line is a *cascade* — a stored property whose
type is missing makes the synthesized conformance fail. Chase the
`cannot find type` errors first; the conformance errors disappear on their own.)

**Root cause**
`PhoneYardageBridge.swift` sits in `apple/Shared/` but depends on iOS-only app
types (`GolfSwingMetrics`, `LocationFix`, `GolfCourseCandidate`,
`ShotDistanceCalculator`, `GolfHoleGeometryAttribution`). It was added to the
**WhoopGolfWatch** Sources phase because of the folder it lives in.

**Fix**
`PhoneYardageBridge` is a *phone-side publisher* — it turns phone GPS + course
data into a `WatchLiveFace`. Only `WatchLiveFace` crosses the wire. Keep
`PhoneYardageBridge.swift` in the **WhoopGolf** target only.

**Rule of thumb:** membership follows *dependencies*, not directory. Before
adding a `Shared/` file to the watch target, check that every type it names is
also in the watch target.

---

## L3 — Building inside iCloud-synced `~/Documents` breaks device code signing

**Symptom**
```
.../Build/Products/Debug-iphoneos/WhoopGolf.app: resource fork, Finder
information, or similar detritus not allowed
Command CodeSign failed with a nonzero exit code
```
The Swift compile succeeds; only `CodeSign` on the `.app` fails.

**Root cause**
The repo lives under `~/Documents`, which is an iCloud Drive / File Provider
volume. Passing `-derivedDataPath build/DerivedData` puts the built `.app`
*inside* that synced tree, and the file provider stamps `com.apple.FinderInfo`
onto the bundle directories. `codesign` refuses to sign a bundle carrying
extended-attribute detritus.

**Fix**
Do **not** pass `-derivedDataPath` under the repo. Use Xcode's default
(`~/Library/Developer/Xcode/DerivedData`, outside the synced tree):

```bash
cd whoop-18birdies/apple
rm -rf build                       # delete the in-repo DerivedData
xattr -cr .                        # strip stamps already applied to sources
xcodebuild -scheme WhoopGolf      -destination 'generic/platform=iOS'      build
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS'  build
```

Xcode.app already uses the default location, so **Product → Run** was never
affected — only scripted `xcodebuild` invocations that pinned DerivedData into
the repo.

---

## L4 — Two agents editing `project.pbxproj` clobber each other silently

**Symptom**
A file is registered in the Xcode project, the build passes, and minutes later
the *same* "cannot find type in scope" error returns. `ls -lT project.pbxproj`
shows a write timestamp newer than your own.

**Root cause**
`project.pbxproj` is rewritten wholesale, not patched. Two agents (here: this
manager and a `cursor-agent` worker) each read a snapshot, edit it, and write
back — last writer wins, and the loser's target membership silently vanishes.
Duplicate `PBXFileReference` entries for one path (two different UUIDs, same
`path = PhoneYardageBridge.swift`) are the tell that a merge went wrong.

**Fix**
Single-writer rule: **one** agent owns `project.pbxproj`. Everyone else appends
a request to `HANDOFFS.md` naming the file and the target it must join. Before
trusting a green build, re-check that your registration survived:

```bash
grep -n "YourFile.swift" WhoopGolf.xcodeproj/project.pbxproj
plutil -lint WhoopGolf.xcodeproj/project.pbxproj
```

---

## L5 — Default arguments hide a stale call site

**Symptom**
No compile error at all — the Watch IMPROVE page shows trail-wrist drill copy
even after Settings is switched to left-lead.

**Root cause**
`GolfImprover.drill(path:tempoRatio:wrist:)` gained a `wrist` parameter with
`= .golferDefault`. `WatchRoundFaceView` still called the 2-argument form, so it
kept compiling and silently pinned the default instead of the user's choice.
The sibling call to `cue(...)` *did* pass `wrist:` — the mismatch was invisible.

**Fix**
Pass `wrist: wrist` explicitly at the call site. When adding a defaulted
parameter for a user preference, grep every call site rather than relying on the
compiler — a default argument is exactly the change the compiler cannot flag.

---

## L6 — `project.yml` `path: Shared` does not register files already missing from `pbxproj`

**Symptom**
iPhone call sites use `DualWearableRequirement` / `ComprehensiveShotIntelligence`,
the `.swift` files sit under `apple/Shared/`, and `project.yml` already has
`path: Shared` for **WhoopGolf** — yet Xcode still reports `cannot find … in scope`.

**Root cause**
This repo’s live membership is often the hand-edited `project.pbxproj`, not a
fresh XcodeGen expand. New Shared files landed on disk (and in tests) without
matching `PBXFileReference` / Sources entries. `project.yml` looking correct is
not evidence the open project compiles.

**Fix**
Diff disk vs pbxproj before trusting green:

```bash
# Shared files on disk but absent from the project file
comm -23 \
  <(ls Shared/*.swift | xargs -n1 basename | sort) \
  <(grep -oE '[A-Za-z0-9_]+\.swift' WhoopGolf.xcodeproj/project.pbxproj | sort -u)
```

Append a **membership request** to `HANDOFFS.md` (file + **WhoopGolf only** /
never Watch). Do not race-edit `pbxproj` (see L4).

**Rule of thumb:** Shared/ is a folder convention; the Sources phase is the
compiler’s truth.

---

## L7 — Dual admission is a separate pure gate, not SensorModeCoordinator

**Symptom**
Hybrid plan exists when both sensors are present, but the Round Start button
still allows Watch-only / WHOOP-only / manual rounds.

**Root cause**
`SensorModeCoordinator.plan` selects the best available mode (including
single-source). Using it alone as UX admission conflates diagnostics with
product start policy.

**Fix**
Keep mode selection in `SensorModeCoordinator`. Put product admission in
`DualWearableRequirement.evaluate` and gate `AppModel.startRound` + the Start
button on `.satisfied` only. Single-source modes remain for Settings diagnostics.

**Rule of thumb:** capability → plan math ≠ product admission.

---

## L8 — Watch Shared membership is an allowlist (never wholesale Shared/)

**Symptom**
Watch fails if it pulls `GolfModels`, `ComprehensiveShotIntelligence`,
`DualWearableRequirement`, or `PhoneYardageBridge` — or if `project.yml`
duplicates the same face files and later “fixes” by adding `path: Shared`.

**Root cause**
WhoopGolfWatch must compile only the WC contract + on-wrist coaching surface
(`WatchLiveFace`, `WatchRoundContext`, `WatchCoachingCue`, wrist/path/improver).
iPhone-only Shared types pull GolfModels / CoreLocation publishers /
SensorMode graphs that break watchOS (L2). Duplicate YAML allowlist entries
are a regen-review hazard.

**Fix**
Keep a **single** explicit allowlist under WhoopGolfWatch. Comment the ban list
in `project.yml`. Watch consumes Codable face *fields* (strings), not iPhone
dossier / admission types. Static-check Watch Sources never contain the ban
list before Mac `xcodebuild`.

**Rule of thumb:** if a Shared type needs phone-only models/frameworks, it stays
off WhoopGolfWatch Sources.

---

## L9 — Cloud “Xcode ready” ≠ cloud has `xcodebuild`

**Symptom**
Alex says “xcode is good to go,” but the cloud agent still cannot produce a
green build and may be tempted to clear `NO_XCODE`.

**Root cause**
Personal Mac Xcode readiness is independent of the Linux cloud image. Clearing
`NO_XCODE` without a local `xcodebuild` SUCCEEDED log invents proof.

**Fix**
Keep `NO_XCODE` until Mac paste results land. Ship a one-paste script
(`apple/scripts/mac-d19-verify.sh`) with correct destinations
(`generic/platform=watchOS`, not `platform/watchOS`) and the D19
`-only-testing:` class list. Physical Watch install stays a separate OS gate.

**Rule of thumb:** only clear NO_XCODE from a real Mac `xcodebuild` log.

# integrator (Claude Code) — build + cross-target integration

**Status:** BLOCKED ON WRITE CONTENTION
**Updated:** 2026-08-21

## What I own

`whoop-18birdies/apple/WhoopGolf.xcodeproj/project.pbxproj` (target membership),
plus cross-target type placement under `apple/Shared/`.

## Landed on disk (source — verified present)

| Change | File | Why |
|--------|------|-----|
| Extracted `WatchRoundContext` + `WatchRoundContextError` + `WatchRoundApplicationContextCodec` | **new** `apple/Shared/WatchRoundContext.swift` | Clears XS-1: `WatchSessionTransfer.swift:11/:92 cannot find type in scope`. They were declared inside the iOS-only `WatchSupport/WatchSessionReceiver.swift`. |
| Extracted `WatchCoachingCue` + `WatchCoachingCueCodec` | **new** `apple/Shared/WatchCoachingCue.swift` | Same class of break, newer: `WatchSessionTransfer.swift:13/:56/:104/:117/:122/:180/:240 cannot find 'WatchCoachingCue(Codec)'`. |
| Removed the `#if os(iOS)` fence around the rest of `WatchSessionReceiver.swift` | `apple/WatchSupport/WatchSessionReceiver.swift` | Unnecessary once the wire contracts live in `Shared/`; that file is a `WCSessionDelegate` and stays iOS-target-only. |
| `GolfImprover.drill(path:tempoRatio:wrist: wrist)` | `watch/WhoopGolfWatchApp/WatchRoundFaceView.swift:63` | Was taking the `.golferDefault` default silently — left-lead Settings never reached the drill copy. LESSONS L5. |

## Verified green (before the pbxproj was overwritten)

```
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build   ** BUILD SUCCEEDED **
xcodebuild -scheme WhoopGolf      -destination 'generic/platform=iOS'     build   ** BUILD SUCCEEDED **   (device-signed, watch app embedded)
```

## Blocker — `project.pbxproj` write war

`project.pbxproj` is rewritten wholesale, so two writers clobber each other.
Twice now, target membership I registered was wiped ~30 s later by a
`cursor-agent` worker, and the build regressed to the *same* XS-1 errors:

- `Shared/WatchRoundContext.swift` + `Shared/WatchCoachingCue.swift` — registration removed, so the watch target cannot see them.
- `Shared/PhoneYardageBridge.swift` — re-added to the **WhoopGolfWatch** target, where it cannot compile (see below), plus a duplicate `PBXFileReference` for the same path.

**Ask:** single-writer rule on `project.pbxproj`. Agents needing target
membership append a row here; the integrator lands it. See LESSONS L4.

## Required target membership (please do not revert)

| File | WhoopGolf (iOS) | WhoopGolfWatch (watchOS) |
|------|:---:|:---:|
| `Shared/WatchRoundContext.swift` | yes | **yes** |
| `Shared/WatchCoachingCue.swift` | yes | **yes** |
| `Shared/WatchLiveFace.swift` | yes | yes |
| `Shared/WatchWristPreference.swift` | yes | yes |
| `Shared/SwingPathGuidance.swift` | yes | yes |
| `Shared/GolfImprover.swift` | yes | yes |
| `Shared/PhoneYardageBridge.swift` | yes | **no** |
| `WatchSupport/WatchSessionReceiver.swift` | yes | **no** |

`PhoneYardageBridge` is a phone-side publisher: it depends on `GolfSwingMetrics`,
`LocationFix`, `GolfCourseCandidate`, `ShotDistanceCalculator`, and
`GolfHoleGeometryAttribution`, none of which are in the watch module. Only the
`WatchLiveFace` it produces crosses the wire. LESSONS L2.

## Also fixed: device code signing

`CodeSign ... resource fork, Finder information, or similar detritus not allowed`
was **not** a signing/entitlements problem. The repo is under iCloud-synced
`~/Documents`; `-derivedDataPath build/DerivedData` put the `.app` inside that
tree and File Provider stamped `com.apple.FinderInfo` on the bundle. Build with
Xcode's default DerivedData instead. Full recipe in LESSONS L3.

## Not done

- No physical Apple Watch install (constraint holds — Alex's Watch is mid-OS-update).
- `WhoopGolfTests` not yet green: last run was polluted by concurrent edits
  (`GolfImprover.swift:136-138 missing argument for parameter 'path'`,
  `WatchYardageBridgeTests.swift:82 Double? vs Double`). Re-run once writes settle.

## Evidence

- `graphify query "Apple Watch companion WhoopGolfWatch WatchSessionTransfer WorkoutManager live face yardage"`
- Build logs (scratchpad, not committed): `watchbuild.log`, `iosbuild.log`, `iostest.log`
- No secrets in this report.

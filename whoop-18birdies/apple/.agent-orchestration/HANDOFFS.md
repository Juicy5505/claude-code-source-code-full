# HANDOFFS — blockers & ownership (D19)

Manager clears conflicts. Agents append; do not steal files.

## Active blockers

| ID | From | Needs | Blocker | Manager action |
|----|------|-------|---------|----------------|
| H1 | manager | xcode-ship report | ~~No build evidence~~ → **DONE** see `agents/xcode-ship.md` (all targets FAILED) | Clear H1; act on XS-1 |
| XS-1 | xcode-ship | Compile WhoopGolfWatch / ship green | `WatchSessionTransfer.swift:11` missing `WatchRoundContext`; `:92` missing `WatchRoundApplicationContextCodec`. WhoopGolf + WhoopGolfWatch + tests `build-for-testing` all **FAILED**. Also check `SessionView.swift:64` / `WatchRoundFaceView` target membership. Logs: `/tmp/whoopgolf-*-build.log`. Report: `agents/xcode-ship.md` | **CLAIMED by error-fixer-learner** (2026-08-21) — verifying Shared membership + rebuild |
| H2 | manager | LESSONS ≥3 | LESSONS.md header only | Resume error-fixer-learner |
| H3 | manager | Hybrid coordinator | ~~Watch-only C0 aim obsolete~~ → **DONE** wearable-architecture D19 fused status (`agents/wearable-architecture.md`) | Clear H3 |
| H4 | golf-improver-engine | score+explanation | **Engine DONE** — UI bind still open | N2: watch-round-face or phone UI bind `strokeScore` on IMPROVE + stroke rows |
| H5 | manager | inter-swing yardage | ~~open~~ → **DONE** phone-yardage-bridge | Clear H5 |
| XS-2 | integrator | **Single-writer lock on `project.pbxproj`** + honour the target-membership table in `agents/integrator.md` | XS-1 root cause is fixed on disk (`Shared/WatchRoundContext.swift`, `Shared/WatchCoachingCue.swift`), but the registration keeps getting overwritten by a concurrent `project.pbxproj` writer, so the watch target regresses to the same errors. Also: `Shared/PhoneYardageBridge.swift` must **not** be in WhoopGolfWatch (iOS-only deps), and a duplicate `PBXFileReference` for it needs removing. LESSONS L2/L4. | Stop all agents editing `project.pbxproj`; route membership requests here |

## Ownership claims (D19)

| File / area | Owner | Notes |
|-------------|-------|-------|
| SessionView / SettingsView (watch) | watch-round-face | HR+hole on face |
| WatchRoundFaceView.swift (watch) | watch-round-face | Live face TabView; claimed D19 reopen |
| WatchWristPreference / SwingPathGuidance / MotionManager | trail-right-motion | |
| WatchSessionTransfer / WatchSessionReceiver | watch-connectivity | |
| WatchLiveFace; AppModel yardage publish; RoundView distance sections | phone-yardage-bridge | |
| WorkoutManager | watch-healthkit | |
| SensorModeCoordinator | wearable-architecture | Hybrid maximize-both + fused status helpers |
| WhoopGolf/Views/SettingsView.swift + TodayView.swift | wearable-architecture | D19 phone fused dual status (temp claim) |
| GolfImprover.swift (`SwingStrokeScore`, `ImproverTip`, drills/miss/tempo) | golf-improver-engine | H4 models shipped; no separate View file yet |
| SwingPathGuidanceTests + new stroke/yardage tests | automated-tests | |
| LESSONS.md / compile fixes | error-fixer-learner | |
| agents/tailscale-ingest.md | tailscale-ingest | report-only |

## Agent-noted (non-blocking)

| ID | From | Note | Manager action |
|----|------|------|----------------|
| N1 | golf-improver-engine | ~~`WatchRoundFaceView` drill without `wrist:`~~ → **fixed** by watch-round-face. ~~`WatchSessionTransfer` drill without `wrist:`~~ → **fixed** by watch-connectivity (`drill(…, wrist:)`). | Clear N1 |
| N2 | golf-improver-engine | Bind `GolfImprover.strokeScore(path:correctedYawDegrees:tempoRatio:wrist:)` on Watch IMPROVE + phone stroke rows (`pathScore`, `explanation`, `tip.missAdvice`, `tip.alternateDrill`) | UI agents |
| WC-1 | watch-connectivity | WC payloads + durable transfer **shipped** in owned files + `Shared/WatchCoachingCue.swift`. WhoopGolfWatch build still **FAILED** because iPhone `SettingsView.swift` is in Watch Sources (`project.pbxproj`) — escalate to integrator (XS-2). Log: `/tmp/whoopgolf-watch-connectivity-build.log`. Report: `agents/watch-connectivity.md`. | Integrator fix membership; xcode-ship re-verify |

## Cleared

- C0: no agent-filed ownership fights.
- C1-D19: cancelled Watch-only tasking; ownership expanded for phone Hybrid surfaces.

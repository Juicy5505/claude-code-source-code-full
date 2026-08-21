# watch-healthkit

Updated: 2026-08-21
Status: **DONE** (owned file; no physical Watch install)

## Purpose

HR / `HKWorkoutSession` on Watch for golf rounds (`WorkoutManager.swift` only).

## Done

- Audited existing golf workout path: `.golf` + outdoor, live builder, route builder (round only), auth for workout/route share + HR read.
- Gap-fill in `whoop-18birdies/watch/WhoopGolfWatchApp/WorkoutManager.swift`:
  - Explicit `HKLiveWorkoutDataSource.enableCollection` for heart rate (+ active energy) so golf configs that omit HR still stream bpm.
  - Published `averageHeartRate`, `isSessionRunning`, `lastFailure`; sample ingest with 1…300 bpm guard.
  - Async beginCollection / session failure surfaces via `lastFailure` (start used to return true then die silently).
  - Idempotent restart clears prior session handles before a new start.
- Entitlements: left as-is (`WatchSupport/WhoopGolfWatch.entitlements` already has `com.apple.developer.healthkit` only). Did **not** invent health-records / background-delivery on Watch.
- Info: `workout-processing` + health usage strings already present in `WatchSupport/Info.plist` / project.yml.

## Wiring evidence (read-only; other agents own these)

- `SessionView` already binds `workout.$heartRate` → `session.currentHR`, tiles `"HR"`, tags swings with `workout.heartRate`.
- Per-swing `hr_bpm` already transfers via `WatchSessionTransfer.sendLiveSwing` / session JSON → phone `WatchSessionImporter` / `lastWatchHeartRate`.
- New `averageHeartRate` is ready for face/summary consumers; not wired into SessionView (owned by watch-round-face).

## Gaps / blockers (not owned)

- WhoopGolfWatch build currently fails: `WatchSessionTransfer` cannot find `WatchRoundContext` / `WatchRoundApplicationContextCodec` because `WatchSupport/WatchSessionReceiver.swift` is **not** in the Watch target Sources (iOS-only membership). See HANDOFFS → watch-connectivity / error-fixer.
- No WorkoutManager.swift compile errors in the failed build log.
- Physical Watch install still gated (per board).

## Files touched

- `whoop-18birdies/watch/WhoopGolfWatchApp/WorkoutManager.swift`

## Evidence

- Graphify: `WorkoutManager` / `HKWorkoutSession` / `WatchSessionReceiver` / `HeartRateMeasurement` path reviewed first.
- `xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build` → **BUILD FAILED** on foreign `WatchSessionTransfer` types; zero `WorkoutManager` errors.
- Entitlement check: Watch = HealthKit only; phone entitlements unchanged.

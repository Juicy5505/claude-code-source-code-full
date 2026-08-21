# watch-round-face

**Role:** Full golf UI maximizing Watch S5 + WHOOP 5 + phone (`com.alex.whoopgolf`).  
**Owns:** Watch face (`WatchRoundFaceView` / SessionView composition).  
**Does not own:** Path/tempo math, fusion reconciliation, WCSession receiver, ingest tokens.

## Status

- **DONE** (D19) — on-wrist face wired to WatchLiveFace v3 + coaching cue overlays.

## Consumes

| Model | Path |
|---|---|
| `SwingPathStrokeScore` / `SwingPathGuidance.scoreStroke` | `Shared/SwingPathGuidance.swift` |
| `SwingStrokeScore` / `GolfImprover.strokeScore` / tips | `Shared/GolfImprover.swift` |
| `WatchLiveFace` v3 | `Shared/WatchLiveFace.swift` |
| `WatchCoachingCue` | `Shared/WatchCoachingCue.swift` |
| `WatchWristMount` (trail-right default) | `Shared/WatchWristPreference.swift` |

## Publishes (UI)

**Watch:** path score + explanation, improver cue/drill/miss, yardage F/M/B when mapped, last shot yards, hole/course/stroke count, club + ball-start, HR + avg HR, next-tip, trail-right wrist feel.

## Done

- Path / Improve / Yardage / HR pages show all required live-face fields.
- `SessionView` passes `liveFace`, cue tip/drill, `averageHeartRate`, and `liveFace.wristMount`.

## Gaps

- Physical Watch install still gated.
- Foreign WhoopGolfWatch compile blockers owned by watch-connectivity / error-fixer.

## Files

- `whoop-18birdies/watch/WhoopGolfWatchApp/WatchRoundFaceView.swift`
- `whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift`

## Evidence

- v3 keys: path score/label, club, ball-start, hole F/M/B, lastShotYards, strokeCount, courseName, wristMount.
- Wrist feel: `Feel · trail-right wrist`.

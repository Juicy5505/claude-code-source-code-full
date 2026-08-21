# watch-round-face

**Role:** Full golf UI maximizing Watch S5 + WHOOP 5 + phone (`com.alex.whoopgolf`).  
**Owns:** Watch face (`WatchRoundFaceView` / SessionView composition) and phone UI surfaces for strokes, companion status, session summary, pattern trends.  
**Does not own:** Path/tempo math, fusion reconciliation, WCSession receiver, ingest tokens.

## Status

- **building** — phone stroke board + Watch HR/next-tip face; compiling WhoopGolf + WhoopGolfWatch.

## Consumes

| Model | Path |
|---|---|
| `SwingPathStrokeScore` / `SwingPathGuidance.scoreStroke` | `Shared/SwingPathGuidance.swift` |
| `SwingStrokeScore` / `GolfImprover.strokeScore` / tips | `Shared/GolfImprover.swift` |
| `WatchLiveFace` | `Shared/WatchLiveFace.swift` |
| `WatchWristMount` (trail-right default) | `Shared/WatchWristPreference.swift` |
| `GolfSwingMetrics` / shot intervals | `Shared/GolfModels.swift` |
| Watch reachability / pending import | `WatchSupport` + `AppModel` |

## Publishes (UI)

**Watch:** path score + explanation, improver cue/drill/miss, yardage F/M/B when mapped, HR, next-tip (`postSwing`).  
**Phone:** stroke list + map, WHOOP readiness (Today), delayed import + Watch status card, live session summary, Trends miss/tempo/consistency.

## Constraints

- Trail-right default (D18). No physical Watch install. No secrets in notes.
- F/M/B stay empty without hole geometry. Yards labeled GPS displacement.

## Done when

WhoopGolf + WhoopGolfWatch compile with the three stroke capabilities on-wrist and the phone board/status/trends wired.

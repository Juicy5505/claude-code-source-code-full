# trail-right-motion — D19 both-required

**Status:** DONE  
**Wave:** per TASKS.md  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done

- `WatchWristMount.golferDefault == .trailRight` (shipped default; lead-left is override only).
- `pathSign`: trailRight = −1, leadLeft = +1. Corrected yaw = raw × pathSign; **positive ⇒ in-to-out**.
- `MotionManager` stores raw CoreMotion attitude; polarity applied only in `SwingPathGuidance` (via `SwingAnalysis.analyse` → `classify`).
- `classify` / `scoreStroke` / `scoreForShotChain` / `refineWithWhoop` remain the public path APIs for StrokeScoreShotChain + GolfImprover.
- Defaults on those APIs use `.golferDefault` (trail-right).

## Gaps

- None in owned files. (`scoreStroke` unit coverage lives under automated-tests / `SwingPathGuidanceTests` — classify + pathSign already covered; no owned-file change required.)

## Files (owned)

| Path | Role |
|------|------|
| `apple/Shared/WatchWristPreference.swift` | Mount enum, `golferDefault`, `pathSign`, load/save |
| `apple/Shared/SwingPathGuidance.swift` | `classify`, `scoreStroke`, shot-chain + WHOOP refine |
| `watch/WhoopGolfWatchApp/MotionManager.swift` | Raw 100 Hz device motion; no wrist flip |

## Evidence

### 1. Trail-right is golferDefault

```swift
// WatchWristPreference.swift
static let golferDefault: WatchWristMount = .trailRight
var pathSign: Double { self == .trailRight ? -1 : 1 }
```

`load()` writes/returns `golferDefault` when unset. Tests: `SwingPathGuidanceTests.testTrailRightDefaultIsTheShippedWrist`, `testLoadFallsBackToTrailRightWhenUnset`.

### 2. pathSign mirror math

| Raw yaw | Mount | Corrected | Path |
|--------:|-------|----------:|------|
| +20 | leadLeft (+1) | +20 | inToOut |
| +20 | trailRight (−1) | −20 | outToIn |
| −20 | leadLeft | −20 | outToIn |
| −20 | trailRight | +20 | inToOut |

Contract: after correction, `|yaw| < onPlaneDegrees (8°)` → onPlane; else sign selects in/out. Tests: `testTrailRightMirrorsLeadLeftPathClass`, `testNegativeYawMirrorFlipsPathClassAcrossMounts`, `testOnPlaneBandUsesCorrectedYaw`, `testOnPlaneBoundaryIsExclusiveOfThreshold`.

### 3. scoreStroke / classify usable by shot chain + improver

**API surface (`SwingPathGuidance`):**

- `classify(downswingYawDegrees:wrist:) -> (path, correctedYawDegrees)`
- `scoreStroke(downswingYawDegrees:tempoRatio:wrist:) -> SwingPathStrokeScore`
- `scoreForShotChain(...)` / `refineWithWhoop(live:...)` for delayed WHOOP
- Codable `SwingPathStrokeScore` with snake_case keys for the chain feed

**Consumers (foreign — verified call sites only):**

- `StrokeScoreShotChain.scorePath` → `SwingPathGuidance.scoreStroke` + `refineWithWhoop` on raw yaw; corrected-stored path avoids double `pathSign`.
- `GolfImprover.strokeScore(path:correctedYawDegrees:tempoRatio:wrist:)` composes coaching from classify outputs (commented contract in `scoreForShotChain`).
- Watch `SwingAnalysis` (`SwingDetector.swift`) → `classify(..., wrist: WatchWristMount.load())` then stores corrected yaw.

### 4. MotionManager honesty

Header documents: attitude raw; `pathSign` only in Shared guidance; tempo is time-based (no sign); accel magnitude scalar. No wrist flip in ingest/resolve.

## Build / test notes

- Unit: `WhoopGolfTests/SwingPathGuidanceTests` (default, mirror, on-plane, nil yaw).
- No code change this pass — owned sources already match D19 trail-right contract.

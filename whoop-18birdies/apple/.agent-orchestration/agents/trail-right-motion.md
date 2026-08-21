# trail-right-motion

**Status:** DONE (D19 — body-relative score feed)  
**Updated:** 2026-08-21

## Purpose

Trail-right CoreMotion → path class + **numeric score + explanation per stroke** for Watch Series 5. Feed stroke-score-shot-chain. WHOOP delayed yaw may refine; **Watch is live scorer**.

## Done

- Trail-right default + `pathSign` (−1 trail / +1 lead) + classify mirror.
- `load()` persists default when unset/corrupt.
- **`SwingPathStrokeScore`** Codable feed (`schema_version`, `score`, `path_class`, `corrected_yaw_deg`, `explanation`, `wrist`, `scorer`, `tempo_ratio`).
- **`scoreStroke`** — live Watch body-relative 0…100 + plain-language explanation.
- **`refineWithWhoop`** — 70/30 blend; scorer → `whoopRefined`.
- **`scoreForShotChain`** — single entry for shot-chain (Watch live ± optional WHOOP).
- Docs: compose with `GolfImprover.strokeScore` for drills/miss (improver owns coaching packet; this owns path math + live score).
- MotionManager: raw attitude; polarity/score downstream.

## Feed (stroke-score-shot-chain)

```swift
let pathScore = SwingPathGuidance.scoreForShotChain(
  watchDownswingYawDegrees: rawYawDeg,   // transition→impact, unwrapped
  tempoRatio: tempo,
  wrist: WatchWristMount.load(),         // trailRight default
  whoopDownswingYawDegrees: delayedYaw?, // nil = live only
  whoopWrist: .leadLeft                  // band mount when refining
)
// pathScore.score / .explanation / .pathClass / .scorer
// Optional coaching wrap:
GolfImprover.strokeScore(
  path: pathScore.pathClass,
  correctedYawDegrees: pathScore.correctedYawDegrees,
  tempoRatio: pathScore.tempoRatio,
  wrist: pathScore.wrist
)
```

## Gaps

- Session JSON / `GolfSwingMetrics` persistence + UI bind → **TRM-1** (not owned).
- Full-workspace build still red on **XS-1** (`WatchCoachingCue` Watch target membership) — outside ownership.
- GolfImprover keeps a parallel private `scorePath` curve; path **classify** stays Shared — HANDOFF asks shot-chain/UI to call `scoreForShotChain` first.

## Files touched

- `Shared/SwingPathGuidance.swift`
- `watch/.../MotionManager.swift` (docs)
- `.agent-orchestration/HANDOFFS.md` (TRM-1)
- this file

## Evidence

- Graphify: classify/score ← Shared; SwingAnalysis still calls classify.
- Contract: trail `pathSign=-1`; Gaussian σ=18° (~100 @ 0°, ~82 @ |8°|); WHOOP refine flips scorer.
- iOS/Watch full build: FAILED upstream XS-1 (WatchCoachingCue), not in these files.

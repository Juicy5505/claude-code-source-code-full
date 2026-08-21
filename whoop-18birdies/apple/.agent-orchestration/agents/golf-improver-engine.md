# golf-improver-engine

**Status:** DONE (H4 score+explanation)  
**Updated:** 2026-08-21  
**Own:** `whoop-18birdies/apple/Shared/GolfImprover.swift`  
  (models in-file: `SwingStrokeScore`, `ImproverTip`, `ImproverDrill`, `ImproverFocus`, `PathMissSeverity`)

## Done

- **Core loop H4:** each stroke can get a **path score (0…100) + explanation** via `GolfImprover.strokeScore(path:correctedYawDegrees:tempoRatio:wrist:…)`.
- Score uses mount-corrected yaw vs `SwingPathGuidance.onPlaneDegrees` (8°); severity `none|mild|moderate|severe`.
- **Coaching pack** `ImproverTip`: cue, primary drill, alternate drill, trail/lead miss advice, post-swing strip.
- Tempo-first when `|ratio − 3.0| > 0.6` (rush **and** slow) for cue + primary drill.
- Trail-right default copy; lead-left variants for path cues/drills/miss advice.
- **Stable** Watch/test string APIs kept: `cue` / `drill` / `consistencyCaption` (rush drill exact string preserved for tests).
- Phone helper: `phoneStrokeSummary(_:)` → `"on-plane · 92 — …explanation…"`.

## API for UI agents (Watch + phone)

| Call | Use |
|------|-----|
| `strokeScore(path:correctedYawDegrees:tempoRatio:wrist:tempoCV:id:)` | Stroke row: `pathScore`, `explanation`, `scoreHeadline`, nested `tip` |
| `tip(path:tempoRatio:wrist:…)` | IMPROVE page without allocating a stroke id |
| `cue` / `drill` | Existing Watch face strings |
| `phoneStrokeSummary` | Compact phone list/detail line |
| `SwingStrokeScore.missAdvice` / `.drillLine` | Convenience mirrors of tip fields |

**Inputs from trail-right-motion:** `SwingPathClass` + `correctedYawDegrees` from `SwingPathGuidance.classify`, plus `tempoRatio` from swing analysis. Wrist default `.golferDefault` = trail-right.

## Gaps

- Watch/phone **UI wiring** of `strokeScore` is owned by watch-round-face / phone surfaces — they still call `cue`/`drill` today. Models are ready to bind.
- `WatchRoundFaceView` / SessionView may still omit `wrist:` on `drill` (defaults trail-right). Lead-left Settings override needs that call site to pass `wrist` (watch-round-face).
- No dedicated SwiftUI view file yet (models-only); claim in HANDOFFS if a Shared coaching view is added later.

## Files touched

- `whoop-18birdies/apple/Shared/GolfImprover.swift`
- `whoop-18birdies/apple/.agent-orchestration/agents/golf-improver-engine.md` (this)
- `whoop-18birdies/apple/.agent-orchestration/HANDOFFS.md` (H4 note)

## Evidence

- Graphify prior: `GolfImprover` ↔ Watch face / `SwingPathGuidance.coachingLabel`.
- Tests (automated-tests): trail cue language, rush drill exact string, headcover / 9-to-3 / consistency bands — string contracts preserved.
- No secrets.

## graphify

```text
graphify query "GolfImprover ImproverTip SwingStrokeScore path score explanation"
```

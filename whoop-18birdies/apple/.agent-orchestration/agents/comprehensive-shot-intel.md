# comprehensive-shot-intel — D19 both-required

**Status:** DONE  
**Wave:** A (per TASKS.md)  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Gap-filled every verified stroke UI bind: club, path score/explanation, ball-start tendency, attack feel always surface (no nil-hide).
- Coherent `dossier` / `dossiers` / `enrichTrackingFields` — same derivation path; `defaultClub` shared; persisted ball-start detail kept only when bias still matches.
- Shared honest copy: `ComprehensiveShotIntelligence.tendencyDisclaimer` (“not launch-monitor carry, spin, or apex”).
- Display helpers: `clubDisplayName` / `clubShortCode` / `pathScoreLine` (+ dossier extensions).
- Stroke board + ComprehensiveTrackingBoard + PostRoundPathSummaryCard + Round club picker show tendency disclaimer and always-on chips.
- Post-round sheet adds dominant ball-start tile.

## Gaps
- Mac `xcodebuild` not run on this Linux cloud agent (`NO_XCODE`). Watch OS gate CLEARED — install is Alex device step.
- Attack detail not persisted on `GolfSwingMetrics` (by design — recompute via dossier; prefer not expand models).

## Files
- `Shared/ComprehensiveShotIntelligence.swift`
- `WhoopGolf/Views/GolfStrokePresentation.swift`
- `WhoopGolf/Views/GolfStrokeBoardView.swift`
- `WhoopGolf/Views/WatchCompanionPanels.swift` (`ComprehensiveTrackingBoard`, `PostRoundPathSummaryCard`)
- `WhoopGolf/Views/RoundView.swift` (club picker + stroke board empty copy)

## Evidence
- Tests owned by automated-tests: `ComprehensiveShotIntelligenceTests` in `WhoopGolfTests/DualWearableRequirementTests.swift` (`testEnrichTrackingFieldsPersistsClubAndBias`, bias mapping cases).
- Static: enrich + dossier share `dossier(for:sequence:wrist:defaultClub:)`.
- UI: stroke rows always emit non-optional `clubLabel` / `ballStartLabel` / `ballStartDetail` / `attackFeelLabel` / `attackDetail` / `pathScoreLabel`.

# automated-tests — D19 both-required

**Status:** DONE (NO_XCODE — Mac must compile/run)  
**Wave:** WAVE_A / regressions  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Gate outcomes: `missingBoth` / `missingWatch` / `missingWhoop` / `satisfied(hybrid)` + recovered-session-alone still blocked
- Trail-right polarity: `StrokeScoreShotChainTests` + `SwingPathGuidanceTests` (no double-flip of stored yaw)
- Yards preserved through `StrokeScoreShotChain.enrichSwingMetrics` and `ComprehensiveShotIntelligence.enrichTrackingFields`
- Hybrid `materializedObservation` / reconcile preserves Watch path + club (WHOOP may enrich peak/tempo)
- Ball-start bias mapping: mild→fade/draw, moderate/severe→pullFade/pushDraw, onPlane→straight, unknown→unknown

## Gaps
- **NO_XCODE** on Linux cloud — cannot execute XCTest here
- `WhoopGolfTests` membership for new/updated files still needs integrator single-writer pbxproj add (see HANDOFFS)

## Files
- `WhoopGolfTests/DualWearableRequirementTests.swift`
- `WhoopGolfTests/ComprehensiveShotIntelligenceTests.swift` (split out)
- `WhoopGolfTests/StrokeScoreShotChainTests.swift`
- `WhoopGolfTests/SwingPathGuidanceTests.swift` (trail-right polarity only)

## Evidence
- Test names (Mac): see STATUS return below / commit message
- Run on Mac: `xcodebuild test -scheme WhoopGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WhoopGolfTests`

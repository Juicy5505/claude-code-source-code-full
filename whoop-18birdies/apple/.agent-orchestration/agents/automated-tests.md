# automated-tests — D19 both-required

**Status:** DONE (sources ready; **NO_XCODE** — Mac must compile/run)  
**Wave:** WAVE_A / regressions  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Gate outcomes: `missingBoth` / `missingWatch` / `missingWhoop` / `satisfied(hybrid)` + recovered-session-alone still blocked
- Trail-right polarity: `StrokeScoreShotChainTests` + `SwingPathGuidanceTests` (no double-flip of stored yaw)
- Yards preserved through `StrokeScoreShotChain.enrichSwingMetrics` and `ComprehensiveShotIntelligence.enrichTrackingFields`
- Hybrid `materializedObservation` / reconcile preserves Watch path + club (WHOOP may enrich peak/tempo)
- Ball-start bias mapping: mild→fade/draw, moderate/severe→pullFade/pushDraw, onPlane→straight, unknown→unknown
- WhoopGolfTests Sources membership present for DualWearableRequirement / StrokeScoreShotChain / ComprehensiveShotIntelligence / SwingPathGuidance tests

## Gaps
- **NO_XCODE** on Linux cloud — cannot execute XCTest here; Alex Mac Xcode is ready → run one-paste script

## Files
- `WhoopGolfTests/DualWearableRequirementTests.swift`
- `WhoopGolfTests/ComprehensiveShotIntelligenceTests.swift`
- `WhoopGolfTests/StrokeScoreShotChainTests.swift`
- `WhoopGolfTests/SwingPathGuidanceTests.swift` (trail-right polarity only)

## Evidence
- **NO_XCODE** — static review only on this host
- Mac one-paste: `bash whoop-18birdies/apple/scripts/mac-d19-verify.sh`
- Or: `xcodebuild test -scheme WhoopGolf -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WhoopGolfTests/DualWearableRequirementTests -only-testing:WhoopGolfTests/ComprehensiveShotIntelligenceTests -only-testing:WhoopGolfTests/StrokeScoreShotChainTests -only-testing:WhoopGolfTests/SwingPathGuidanceTests`

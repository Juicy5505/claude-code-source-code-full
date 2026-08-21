# wearable-architecture — D19 both-required

**Status:** DONE  
**Wave:** WAVE_A (verified)  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Verified `ReconciledHybridSwing.materializedObservation` preserves Watch path/club coaching through hybrid enrich: `pathYawDegrees`, `pathClass`, `pathScore`, `pathExplanation`, `improverTip`, `club`, `ballStartBias`, `attackFeel`, `ballStartDetail` (Watch-first with WHOOP fallback when Watch nil).
- Confirmed `DualWearableFusion` HR ownership: hybrid/watch-only + `watchAppReady` → `.appleWatch` (Broadcast auto-start/scan blocked); WHOOP Broadcast only when Watch is not HR source (whoop-only or watch not ready); `whoopLiveIMUActive` → `.none` (never fight live IMU bond).
- Confirmed `hybridPlan` dual-maximize: `swingCapture == .appleWatchMotionWithWhoopEnrichment`, canonical `.appleWatch`, Watch live haptics when live, WHOOP delayed enrichment via constraints/`liveCaptureWithDelayedEnrichment`; no TOGGLE_IMU/Arming as golf path (`roundFusion.avoidsWhoop5LiveArming == true` all modes).
- Fused Settings/Today copy co-equal Watch + WHOOP; anti-double-count via Watch UUID/timestamp anchor.

## Gaps
- None in owned files. Physical Watch/WHOOP device soak and Xcode ship remain other roles.
- `DualWearableRequirementTests.testHybridMaterializationPreservesPathAndClub` asserts pathScore/pathClass/club; ballStartBias/attackFeel covered by source preserve but not asserted in that test (owned by automated-tests if extended).

## Files
- `whoop-18birdies/apple/Shared/SensorModeCoordinator.swift` (exclusive)
- `whoop-18birdies/apple/Shared/DualWearableFusion.swift` (exclusive)

## Evidence
- Preserve (enriched + awaiting): `SensorModeCoordinator.swift` `materializedObservation` ~L576–653 — Watch path/club/bias/feel kept; WHOOP wrist/tempo/peakG enrich.
- Hybrid plan: `hybridPlan` ~L449–501 — Watch live + WHOOP delayed; Arming explicitly not golf path in header/comments ~L7–15, L458–461.
- HR policy: `DualWearableFusion.heartRateOwner` ~L51–64; Broadcast gates ~L67–75; IMU bond yield ~L52–55, L84–85.
- Round fusion: `roundFusion` hybrid ~L111–121 — Watch live scoring + delayed WHOOP journal merge; `avoidsWhoop5LiveArming: true`.
- Tests (not owned, cite only): `DualWearableFusionTests` (Watch HR / IMU none / no Arming); `DualWearableRequirementTests.testHybridMaterializationPreservesPathAndClub`; `SensorModeCoordinatorTests` hybrid → `.appleWatchMotionWithWhoopEnrichment`.
- Code change this pass: **none** (already patched); status doc only.

# phone-yardage-bridge — D19 both-required

**Status:** DONE  
**Wave:** B (per TASKS.md)  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- `lastMeasuredShotYards(from:)` = newest measured swing N→N+1 phone GPS segment (`SwingShotInterval` / `.measured`, no hole-boundary exclusion). Newest swing stays pending until N+1 arrives.
- `makeLiveFace` fills Watch live-face v3: stroke yards + path score/label (`StrokeScoreShotChain.enrichLiveFace`) + club + ball-start (`ComprehensiveShotIntelligence.dossier`). Stroke yards pinned after enrich so journal fallback cannot invent yards.
- Honest empty: nil `lastShotYards` with fewer than 2 verified GPS endpoints; nil F/M/B without licensed hole map / usable phone fix. Facility search → always nil green targets.
- `AppModel.publishWatchLiveFace` thin publisher only (no startRound/admission rewrite).
- `WatchLiveFace` schema v3 docs: path/club/ball-start + honest-empty yards/map.

## Gaps
- Mac/Xcode build not runnable on Linux cloud (`NO_XCODE`); rely on existing unit tests.
- Licensed hole-geometry provider still optional — overlay stays empty until `applyHoleGreenTargets` supplies targets.

## Files
- `Shared/PhoneYardageBridge.swift`
- `Shared/WatchLiveFace.swift`
- `WhoopGolf/App/AppModel.swift` — `publishWatchLiveFace` only

## Evidence
- `PhoneYardageBridge.lastMeasuredShotYards` — walks newest-first measured intervals; returns nil for single swing / excluded hole transition.
- `PhoneYardageBridge.makeLiveFace` — sets `lastShotYards` from GPS chain; enriches `lastPathScore`/`lastPathLabel`/`strokeCount`; sets `lastBallStartLabel` + `activeClubCode` from latest swing dossier; re-pins `lastShotYards` after enrich.
- `AppModel.publishWatchLiveFace` — passes round swings + optional `activeHoleGreenTargets` + phone fix; publishes via `WatchSessionReceiver`.
- Tests (automated-tests owned): `PhoneYardageBridgeTests` (`testLastMeasuredShotYardsUsesFinalizedSwingChainNotPendingTail`, `testSingleSwingYieldsNoStrokeYards`, `testMakeLiveFaceKeepsStrokeYardsAndEmptyOverlayWithoutGeometry`, `testFacilitySearchNeverBecomesGreenMap`, `testExcludedHoleTransitionDoesNotPublishStrokeYards`); `StrokeScoreShotChainTests.testMakeLiveFaceIncludesPathScoreFromChain`.

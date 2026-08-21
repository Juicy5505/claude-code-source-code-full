# whoop-physio-merge — D19 both-required

**Status:** DONE  
**Wave:** per TASKS.md  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both. Delayed WHOOP + readiness; enrich after finalize; never Arming hang.

## Done
- Confirmed both import resolution paths call `finalizeWHOOPTriggeredShotIntervals()` then `StrokeScoreShotChain.enrichSwingMetrics` (path score / explanation persist) before atomic round save.
- Reinforced delayed-only comments on both enrich call sites — no live `TOGGLE_IMU` / Arming as golf path in `WhoopMotionImportService`.
- Overview readiness hero: recovery + day strain tiles + delayed-vs-Arming physiology caption; fusion board shows `delayedMergeCaption` + refuse-live Arming note.
- Today connection card: surfaces `delayedMergeCaption` + recovery/strain cloud + Check-for-swings / not-Arming copy.
- Settings WHOOP 5 motion inbox: delayed merge caption + enrich-after-finalize note under Check for WHOOP swings; Data promises PromiseRow corrected so delayed historical import is the WHOOP 5 golf path (live IMU experimental / never required).
- Existing refuse-live Settings copy retained on Live WHOOP wrist IMU + capability map rows.

## Gaps
- Unit assertions that imported rounds carry non-nil `pathScore` after import live in `WhoopGolfTests` (automated-tests ownership); this agent verified call-site ordering only.
- Wrist mount picker / trail-right defaults remain trail-right-motion ownership — not contested here.

## Files
- `WhoopGolf/Services/WhoopMotionImportService.swift`
- `WhoopGolf/Views/OverviewView.swift` (physio / readiness / fusion captions)
- `WhoopGolf/Views/TodayView.swift` (readiness connection / delayed merge captions)
- `WhoopGolf/Views/SettingsView.swift` (Check for WHOOP swings / delayed motion / refuse-live promises)
- `agents/whoop-physio-merge.md` (this file)

## Evidence
- Import → finalize → enrich (initial accept): `WhoopMotionImportService.swift` ~L472–477
- Import → finalize → enrich (review resolve): `WhoopMotionImportService.swift` ~L714–720
- `enrichSwingMetrics` persists path score: `Shared/StrokeScoreShotChain.swift` `enrichSwingMetrics`
- Overview recovery/strain + delayed captions: `OverviewView.swift` `readinessHero`, `fusionBoard`
- Today delayed merge: `TodayView.swift` `connectionCard`
- Settings Check for WHOOP swings + refuse-live PromiseRow: `SettingsView.swift` WHOOP 5 motion inbox + Data promises
- No `TOGGLE_IMU` / Arming symbols in `WhoopMotionImportService.swift` (rg clean)

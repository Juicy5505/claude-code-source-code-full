# HANDOFFS — blockers & ownership (D19 both-required civilization)

Manager clears conflicts. Agents append; do not steal files.

## Active blockers

| ID | From | Needs | Blocker | Manager action |
|----|------|-------|---------|----------------|
| XS-MAC | error-fixer-learner | Green WhoopGolf + WhoopGolfWatch | Linux cloud has **NO_XCODE** | Record static audit; Mac verify when host available |
| XS-2 | integrator | Single-writer `project.pbxproj` / `project.yml` | Concurrent membership thrash risk | All membership changes via HANDOFF only |
| XS-MEM-D19 | error-fixer-learner | pbxproj Sources membership (single writer) | Disk files exist; **WhoopGolf** Sources missing them → iPhone compile fail | Add PBXFileReference + WhoopGolf Sources (not Watch). Deduped Watch Shared allowlist already in `project.yml` |

## Ownership claims

| File / area | Owner |
|-------------|--------|
| DualWearableRequirement + Round gate + AppModel admission | dual-gate-admission |
| ComprehensiveShotIntelligence + club picker + tracking board | comprehensive-shot-intel |
| WatchRoundFaceView / SessionView | watch-round-face |
| WatchWristPreference / SwingPathGuidance / MotionManager | trail-right-motion |
| WatchSessionTransfer / WatchSessionReceiver / WC contracts | watch-connectivity |
| PhoneYardageBridge / WatchLiveFace / publishWatchLiveFace | phone-yardage-bridge |
| WhoopMotionImportService / Overview-Today readiness copy / Settings Check-for-swings | whoop-physio-merge |
| SensorModeCoordinator / DualWearableFusion | wearable-architecture |
| WhoopGolfTests gate/intel/path | automated-tests |
| docs/vault App Overview + D19 | vault-obsidian-graphify |
| LESSONS.md / compile fixes | error-fixer-learner |
| TASKS / STATUS / HANDOFFS / PRODUCT | manager |

## Membership requests (pbxproj single-writer)

| File | Target | Notes |
|------|--------|-------|
| `Shared/ComprehensiveShotIntelligence.swift` | **WhoopGolf only** | iPhone club/tracking intel; depends on `SwingPathGuidance` + `GolfSwingMetrics` / GolfModels. **Never** WhoopGolfWatch. |
| `Shared/DualWearableRequirement.swift` | **WhoopGolf only** | Round admission; depends on `SensorModeCoordinator` / capability types. **Never** WhoopGolfWatch. |
| `WhoopGolf/Views/OverviewView.swift` | **WhoopGolf** | Uses DualWearableRequirement; absent from pbxproj. |
| `WhoopGolfTests/DualWearableRequirementTests.swift` | **WhoopGolfTests** | Gate outcomes only. |
| `WhoopGolfTests/ComprehensiveShotIntelligenceTests.swift` | **WhoopGolfTests** | Ball-start, yards-on-enrich, hybrid materialize path+club. |
| `WhoopGolfTests/StrokeScoreShotChainTests.swift` | **WhoopGolfTests** | Path score, trail-right polarity, yards preserve, live face. |
| (cleanup) `DualWearableFusionTests.swift` | **WhoopGolfTests** | Duplicate PBXBuildFile entries in Sources — keep one. |

**Watch audit (2026-08-21, static):** WhoopGolfWatch Sources correctly **omit** ComprehensiveShotIntelligence, DualWearableRequirement, GolfModels, PhoneYardageBridge, StrokeScoreShotChain. Watch allowlist in `project.yml` is face/contract files only (`WatchLiveFace`, coaching/context, wrist/path/improver).

## Cleared (recent)

| ID | Note |
|----|------|
| D19-WIP | Dual gate + comprehensive tracking committed `bd81722` |
| H5 | Inter-swing yardage previously MET |
| H3 | Hybrid coordinator previously MET |

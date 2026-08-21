# HANDOFFS — blockers & ownership (D19 both-required civilization)

Manager clears conflicts. Agents append; do not steal files.

## Active blockers

| ID | From | Needs | Blocker | Manager action |
|----|------|-------|---------|----------------|
| XS-MAC | xcode-ship / cloud | Green WhoopGolf + WhoopGolfWatch + D19 tests | Linux cloud still **NO_XCODE**; Alex Mac Xcode is ready | Alex run `scripts/mac-d19-verify.sh` once; paste SUCCEEDED logs → clear NO_XCODE |
| XS-2 | integrator | Single-writer `project.pbxproj` / `project.yml` | Concurrent membership thrash risk | All membership changes via HANDOFF only |

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
| `WhoopGolf/Views/OverviewView.swift` | **WhoopGolf** | Uses DualWearableRequirement (membership applied). |
| `WhoopGolfTests/DualWearableRequirementTests.swift` | **WhoopGolfTests** | Gate outcomes only. |
| `WhoopGolfTests/ComprehensiveShotIntelligenceTests.swift` | **WhoopGolfTests** | Ball-start, yards-on-enrich, hybrid materialize path+club. |
| `WhoopGolfTests/StrokeScoreShotChainTests.swift` | **WhoopGolfTests** | Path score, trail-right polarity, yards preserve, live face. |

**Watch audit (2026-08-21, static recheck):** WhoopGolfWatch Sources include `WatchRoundContext` + face allowlist; correctly **omit** ComprehensiveShotIntelligence, DualWearableRequirement, GolfModels, PhoneYardageBridge, StrokeScoreShotChain. WhoopGolfTests membership includes DualWearableRequirement / ComprehensiveShotIntelligence / StrokeScoreShotChain / SwingPathGuidanceTests.

## Cleared (recent)

| ID | Note |
|----|------|
| XS-WATCH-OS | **CLEARED 2026-08-21** — Alex confirmed Watch OS updated and ready. Physical WhoopGolfWatch install from `apple/WhoopGolf.xcodeproj` is **unblocked**. Do **not** claim the Watch app is already on-device until Alex confirms install. Runbook: `docs/MAC-WATCH-INSTALL.md` |
| XS-DUP-FUSION | Removed duplicate `DualWearableFusionTests.swift` PBXBuildFile from WhoopGolfTests Sources (kept `C1A002F2…`) |
| XS-MEM-D19 | WhoopGolf (+tests) Sources now include DualWearableRequirement / ComprehensiveShotIntelligence / OverviewView; Watch still omit — static recheck OK |
| D19-WIP | Dual gate + comprehensive tracking committed `bd81722` |
| H5 | Inter-swing yardage previously MET |
| H3 | Hybrid coordinator previously MET |

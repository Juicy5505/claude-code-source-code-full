# error-fixer-learner — D19 both-required

**Status:** DONE (static; **NO_XCODE** — Alex Mac ready, cloud still missing xcodebuild)  
**Wave:** per TASKS.md  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Read `LESSONS.md` (L1–L5); consolidated **L6** (yml≠pbxproj), **L7** (dual admission ≠ SensorMode), **L8** (Watch Shared allowlist), **L9** (cloud Xcode-ready ≠ clear NO_XCODE).
- Static audit `project.yml` + `WhoopGolf.xcodeproj/project.pbxproj` Watch vs iPhone Shared membership.
- Deduped WhoopGolfWatch Shared sources in `project.yml`; documented ban list for iPhone-only Shared.
- Removed duplicate `DualWearableFusionTests` PBXBuildFile (`XS-DUP-FUSION`).
- Recorded membership requests in `HANDOFFS.md` (`XS-MEM-D19`); later single-writer commits registered missing WhoopGolf / test Sources — **cleared**.
- Shipped Mac one-paste `scripts/mac-d19-verify.sh` for green-build proof.

## Gaps
- **NO_XCODE** — Linux cloud has no `xcodebuild`; cannot green-build WhoopGolf / WhoopGolfWatch here (`XS-MAC`). Alex Mac Xcode is ready — run the one-paste script for compile proof.

## Files
- `LESSONS.md` (owned)
- `project.yml` Watch Shared allowlist (compile-hazard fix)
- `HANDOFFS.md` membership requests
- `scripts/mac-d19-verify.sh`
- Cross-agent: do not add Shared intel/gate files to Watch

## Evidence
- `which xcodebuild` → not found (**NO_XCODE**)
- Watch Sources: face/contract allowlist only; **no** ComprehensiveShotIntelligence / DualWearableRequirement / GolfModels / PhoneYardageBridge
- WhoopGolf Sources now include ComprehensiveShotIntelligence + DualWearableRequirement + OverviewView (post XS-MEM-D19)
- WhoopGolfTests include DualWearableRequirementTests / ComprehensiveShotIntelligenceTests / StrokeScoreShotChainTests / SwingPathGuidanceTests
- Watch incorrectly includes iPhone-only Shared?: **NONE**
- WatchRoundContext on WhoopGolfWatch Sources?: **YES**

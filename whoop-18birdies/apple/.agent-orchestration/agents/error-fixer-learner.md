# error-fixer-learner — D19 both-required

**Status:** DONE (static; **NO_XCODE**)  
**Wave:** per TASKS.md  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- Read `LESSONS.md` (L1–L5); consolidated **L6** (yml≠pbxproj), **L7** (dual admission ≠ SensorMode), **L8** (Watch Shared allowlist).
- Static audit `project.yml` + `WhoopGolf.xcodeproj/project.pbxproj` Watch vs iPhone Shared membership.
- Deduped WhoopGolfWatch Shared sources in `project.yml`; documented ban list for iPhone-only Shared.
- Recorded membership requests in `HANDOFFS.md` (`XS-MEM-D19`) — prefer HANDOFF over racing pbxproj (L4).

## Gaps
- **NO_XCODE** — Linux cloud has no `xcodebuild`; cannot green-build WhoopGolf / WhoopGolfWatch here (`XS-MAC`).
- Live `pbxproj` still missing WhoopGolf Sources for DualWearableRequirement, ComprehensiveShotIntelligence, OverviewView + related tests until single-writer applies HANDOFF.

## Files
- `LESSONS.md` (owned)
- `project.yml` Watch Shared allowlist (compile-hazard fix)
- `HANDOFFS.md` membership requests
- Cross-agent: do not add Shared intel/gate files to Watch

## Evidence
- `which xcodebuild` → not found (**NO_XCODE**)
- Watch Sources: face/contract allowlist only; **no** ComprehensiveShotIntelligence / DualWearableRequirement / GolfModels / PhoneYardageBridge
- WhoopGolf `path: Shared` in yml, but pbxproj lacks ComprehensiveShotIntelligence + DualWearableRequirement (+ OverviewView, DualWearableRequirementTests, StrokeScoreShotChainTests)
- Watch incorrectly includes iPhone-only Shared?: **NONE**

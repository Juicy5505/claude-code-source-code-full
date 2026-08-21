# xcode-ship

**Status:** WAITING_MAC (Alex: "xcode is good to go"; Watch OS **CLEARED**; cloud recheck still **NO_XCODE**)  
**Agent:** xcode-ship  
**Checked:** 2026-08-21  
**Scope:** build + report only on Mac; cloud prepares the one-paste recipe + install runbook

## Cloud recheck (this agent)

| Check | Result |
|-------|--------|
| `uname` | Linux |
| `which xcodebuild` | **not found** |
| Invented green build? | **No** — NO_XCODE stays until Mac SUCCEEDED logs |

## Mac one-paste (preferred)

```bash
bash whoop-18birdies/apple/scripts/mac-d19-verify.sh
```

## Expanded Mac commands

```bash
cd whoop-18birdies/apple
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' build
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build
xcodebuild -scheme WhoopGolf \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:WhoopGolfTests/DualWearableRequirementTests \
  -only-testing:WhoopGolfTests/ComprehensiveShotIntelligenceTests \
  -only-testing:WhoopGolfTests/StrokeScoreShotChainTests \
  -only-testing:WhoopGolfTests/SwingPathGuidanceTests \
  test
```

Do **not** pass `-derivedDataPath` under iCloud `~/Documents` (LESSONS L3).

## Static readiness (pre-Mac)

| Item | Status |
|------|--------|
| Watch Sources include `WatchRoundContext` | OK (fixes prior XS-1 missing-type failures) |
| Watch omit phone-only Shared ban list | OK |
| WhoopGolfTests D19 classes in pbxproj | OK |
| Duplicate `DualWearableFusionTests` Sources entry | Cleared |

## Prior Mac attempt (stale until re-run)

Earlier WhoopGolfWatch failures (`cannot find type 'WatchRoundContext'`) are believed fixed by Shared membership; **re-run required** — do not treat old FAILED logs as current.

## Handoff

**XS-MAC** remains until Alex pastes SUCCEEDED output from `mac-d19-verify.sh`.  
**XS-WATCH-OS CLEARED** — physical companion install allowed; follow `docs/MAC-WATCH-INSTALL.md`.  
**Ship-ready embed (2026-08-21):** WhoopGolfWatch Sources allowlist OK (18); orphaned duplicate WatchSessionReceiver PBXBuildFile removed. Download = Mac Run scheme **WhoopGolf** to iPhone. Do not claim Watch app already on-device from cloud.

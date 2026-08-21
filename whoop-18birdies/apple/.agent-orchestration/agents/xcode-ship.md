# xcode-ship

**Status:** FAILED  
**Agent:** xcode-ship  
**Checked:** 2026-08-21  
**Scope:** build + report only (no product source edits)

## Exact results

| Target | Command | Result |
|--------|---------|--------|
| **WhoopGolf** | `xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' build` | **BUILD FAILED** |
| **WhoopGolfWatch** | `xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build` | **BUILD FAILED** |
| **Tests compile** | `xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' -only-testing:WhoopGolfTests build-for-testing` | **TEST BUILD FAILED** |

Logs: `/tmp/whoopgolf-ios-build.log`, `/tmp/whoopgolf-watch-build.log`, `/tmp/whoopgolf-tests-build.log`

## Root cause (shared)

All three fail in embedded/target **WhoopGolfWatch** while compiling Watch sources. Phone app signing/validation proceeds until Watch compile aborts the scheme.

## Critical compile errors (file:line, no team IDs)

Unique Swift errors from latest WhoopGolfWatch + tests rebuilds:

1. `whoop-18birdies/watch/WhoopGolfWatchApp/WatchSessionTransfer.swift:11:47` — `cannot find type 'WatchRoundContext' in scope`
2. `whoop-18birdies/watch/WhoopGolfWatchApp/WatchSessionTransfer.swift:92:32` — `cannot find 'WatchRoundApplicationContextCodec' in scope`

Cascading failures reported by xcodebuild (same missing symbols): `SessionModel.swift`, `SessionView.swift`, SwiftEmitModule arm64 / arm64_32 for WhoopGolfWatch.

### First WhoopGolf pass (also noted)

Earlier iOS log also reported:

- `whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift:64:17` — `cannot find 'WatchRoundFaceView' in scope`

That line did **not** reappear as a unique error in the later isolated WhoopGolfWatch / tests runs (still blocked on `WatchRoundContext` / codec). error-fixer-learner should verify target membership for `WatchRoundFaceView.swift` + Shared round-context types.

## Likely fix direction (for error-fixer-learner)

- Ensure `WatchRoundContext` and `WatchRoundApplicationContextCodec` (likely under `apple/Shared/`) are members of the **WhoopGolfWatch** target (and iOS if needed).
- Confirm `WatchRoundFaceView.swift` is in WhoopGolfWatch compile sources if SessionView still references it.
- Do **not** change signing / team IDs.

## Handoff

Appended blocker **XS-1** → `HANDOFFS.md` for **error-fixer-learner**.

## Commands run

```bash
cd whoop-18birdies/apple
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' build
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' -only-testing:WhoopGolfTests build-for-testing
```

Note: first concurrent tests attempt hit DerivedData `build.db` locked; tests were re-run alone → still **TEST BUILD FAILED** on the same WatchSessionTransfer errors.

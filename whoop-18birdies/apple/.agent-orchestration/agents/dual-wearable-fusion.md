# dual-wearable-fusion — D19

Updated: 2026-08-21  
Status: **DONE**

## Purpose

Maximize Apple Watch Series 5 **and** WHOOP 5.0 together: SensorMode/provenance consumers, HR bond-fight rules, Settings contribution board, smart round fusion (Watch live score + delayed WHOOP journal merge + readiness before tee). Never primary-path live `TOGGLE_IMU` Arming on WHOOP 5.

## Done

- Graphify: SensorModeCoordinator, WhoopHeartRateProvider, Settings/Today fused status, HybridSwingReconciler.
- New `Shared/DualWearableFusion.swift`:
  - `HeartRateOwner` policy (Watch vs Broadcast vs none; IMU forces none)
  - `shouldAutoStartWhoopBroadcast` / `shouldAllowWhoopBroadcastScan`
  - `RoundFusionPlan` (Watch live scoring; delayed WHOOP journal merge; no Arming)
  - `contributionsToday` board for Settings / preflight
- `AppModel`: round start/resume uses fusion HR policy (no Broadcast when Watch owns HR); IMU disconnect re-applies policy
- `SettingsView`: Today's contributions card; Broadcast Scan gated by policy; Live HR row uses owner
- `RoundView` preflight: readiness-before-round card when snapshot exists
- Tests: `DualWearableFusionTests` (5 cases)
- HANDOFFS claim for dual-wearable-fusion files
- Session 07 one-line append (vault)

## Gaps

- None blocking for owned fusion policy. Physical Watch install still ops-gated.
- `SensorModeCoordinator` remains wearable-architecture owned; fusion consumes its plan helpers.

## Files touched

- `Shared/DualWearableFusion.swift` (new)
- `WhoopGolfTests/DualWearableFusionTests.swift` (new)
- `WhoopGolf/App/AppModel.swift` (HR fusion policy)
- `WhoopGolf/Views/SettingsView.swift` (contributions + Broadcast gate)
- `WhoopGolf/Views/RoundView.swift` (preflight readiness)
- `WhoopGolf.xcodeproj/project.pbxproj`
- `.agent-orchestration/agents/dual-wearable-fusion.md`
- `.agent-orchestration/HANDOFFS.md`

## Evidence

- Hybrid + Watch ready → HR owner `.appleWatch`, Broadcast auto-start/scan false
- WHOOP-only → Broadcast allowed
- Live IMU → HR `.none` (bond fight avoided)
- Hybrid round fusion: live `.appleWatch`, delayed `.whoopMotion`, merge on Check, `avoidsWhoop5LiveArming`

## Secrets

None.

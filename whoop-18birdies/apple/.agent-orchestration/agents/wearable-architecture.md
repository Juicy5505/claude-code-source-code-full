# wearable-architecture — D19 dual maximize

Updated: 2026-08-21  
Status: **DONE**

## Purpose

Stop Watch-only D18-as-exclusive. **D19**: Apple Watch Series + WHOOP 5.0 co-equal contributors; fused Settings/Today status. WHOOP delayed-import stays; no live IMU Arming as primary.

## Done

- Graphify: SensorModeCoordinator / SettingsView / TodayView / HybridSwingReconciler.
- Appended vault **D19** (does not rewrite D15; supersedes D18 exclusive framing only).
- `Shared/SensorModeCoordinator.swift`:
  - Docs reframed to D19 dual maximize
  - `AdaptiveSensorPlan` helpers: `isDualMaximize`, `fusedStatusTitle`, `fusedStatusDetail`, Watch/WHOOP contributor status + detail
  - Hybrid still Watch-anchors shot UUID (anti-double-count), WHOOP delayed fuse co-equal
- `WhoopGolf/Views/SettingsView.swift`: adaptive card uses fused helpers; WHOOP row no longer “owns swing timing” via live IMU; Live IMU card demoted; capability map Live IMU = NOT PRIMARY
- `WhoopGolf/Views/TodayView.swift`: CONNECTION HEALTH → WEARABLE FUSION with fused title/detail + WHOOP Motion pill

## Gaps

- RoundView hybrid badge copy may still say “Watch owns” — outside claim; optional follow-up.
- Unit tests for `fusedStatusTitle` not added (automated-tests owns test files).
- Full `WhoopGolf` scheme build currently fails on **unrelated** Watch/shared symbols (see HANDOFFS **XS-1**); no errors in SensorModeCoordinator / phone Settings / Today from this pass.

## Files touched

- `Shared/SensorModeCoordinator.swift`
- `WhoopGolf/Views/SettingsView.swift`
- `WhoopGolf/Views/TodayView.swift`
- `.agent-orchestration/agents/wearable-architecture.md`
- `.agent-orchestration/HANDOFFS.md`

## Evidence

- Mode table unchanged functionally: both sources → `.hybrid` with `.appleWatchMotionWithWhoopEnrichment`
- Product copy now “Dual maximize · Watch + WHOOP” / co-equal contributors
- Live Arming not presented as primary golf path

## Secrets

None.

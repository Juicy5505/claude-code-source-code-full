# D19 — Hybrid maximize-both (Watch + WHOOP)

Date: 2026-08-21  
Status: Active product decision  
Supersedes for wearable priority: live WHOOP IMU (see D18 history; do not delete)  
Related: D15 modes retained; D16 graphify control loop

## Decision

Ship **one** golfer-facing app that maximizes **both**:

1. **Apple Watch Series 5** on the **trail (right)** wrist — live motion, path score + explanation, improver, HR, on-wrist face
2. **WHOOP 5.0** — delayed historical swing import + readiness/recovery/strain; refuse live Arming hang
3. **iPhone GPS** — swing-to-swing shot yards only

## Non-goals

- Second golf home-screen icon (Whoop Swing / Kit A as install target)
- Live WHOOP raw IMU as the primary golf path on firmware 5.0
- Inventing green F/M/B from Apple Maps facility search
- Secrets in vault notes (tokens, team IDs, UDIDs, LAN IPs)

## Implementation anchors

- Stroke domain: `GolfSwingMetrics.pathScore` / `pathExplanation` / `improverTip` + `shotYards` via intervals
- Chain: `StrokeScoreShotChain`, `PhoneYardageBridge`, `SwingShotIntervalCalculator`
- Fusion: `DualWearableFusion`, `HybridSwingReconciler`, `SensorModeCoordinator.hybridPlan`
- UI: Overview tab, Round stroke board, Watch `WatchRoundFaceView`, Trends miss/tempo/sparkline/post-round sheet

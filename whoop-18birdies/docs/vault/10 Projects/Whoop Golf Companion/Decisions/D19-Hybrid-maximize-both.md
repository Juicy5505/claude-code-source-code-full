# D19 — Hybrid maximize-both (Watch + WHOOP)

Date: 2026-08-21  
Status: Active product decision  
Supersedes for wearable priority: live WHOOP IMU (see D18 history; do not delete)  
Related: D15 modes retained as **diagnostic** only; D16 graphify control loop

## Decision

Ship **one** golfer-facing app that maximizes **both**:

1. **Apple Watch Series 5** on the **trail (right)** wrist — live motion, path score + explanation, improver, HR, on-wrist face
2. **WHOOP 5.0** — delayed historical swing import + readiness/recovery/strain; refuse live Arming hang
3. **iPhone GPS** — swing-to-swing shot yards only

## Admission (both-required)

**New rounds require both wearables.** Product start is gated by `DualWearableRequirement`:

- Apple Watch live-capture must be proven **and**
- WHOOP swing source must be proven (delayed import / Check for WHOOP swings — not live `TOGGLE_IMU`)

Watch-only, WHOOP-only, and manual remain **diagnostic plan modes** inside `SensorModeCoordinator` only — they are **not** startable product rounds under D19. Existing on-disk drafts stay readable.

D15’s three modes remain historical contract documentation. D19 execution is **Hybrid maximize-both** with this hard dual gate.

## Comprehensive tracking (shipped by decision)

Club-in-hand · path score/explanation · ball-start tendency (not radar) · attack feel · Hybrid fusion caption · Overview health glass · Obsidian App Overview · graphify checkpoints

## Non-goals

- Second golf home-screen icon (Whoop Swing / Kit A as install target)
- Live WHOOP raw IMU as the primary golf path on firmware 5.0
- Inventing green F/M/B from Apple Maps facility search
- Secrets in vault notes (tokens, team IDs, UDIDs, LAN IPs, raw HR streams)
- Starting a new round with only one wearable proven

## Implementation anchors

- Admission: `DualWearableRequirement`, `AppModel.dualWearableAdmission` / `canStartDualWearableRound`, Round + Overview preflight
- Stroke domain: `GolfSwingMetrics.pathScore` / `pathExplanation` / `improverTip` + `shotYards` via intervals
- Chain: `StrokeScoreShotChain`, `PhoneYardageBridge`, `SwingShotIntervalCalculator`
- Fusion: `DualWearableFusion`, `HybridSwingReconciler`, `SensorModeCoordinator.hybridPlan`
- UI: Overview tab, Round stroke board, Watch `WatchRoundFaceView`, Trends miss/tempo/sparkline/post-round sheet

## Graphify

After each wave/slice: `graphify update .` under `whoop-18birdies/apple`; vault `graphify update` when mounted. Full cadence table: [[App Overview]].

# WHOOP Golf — Orchestration STATUS (D19 dual-wearable)

Updated: 2026-08-21 (cloud agent — Overview + stroke persist + WHOOP enrich + tests)  
Outcome: **SOFTWARE_SLICE_COMPLETE** (xcodebuild / device install still Mac-gated)  
Product bible: `PRODUCT.md` · Vault decision: **D19**

## Mandate (one line)

Maximize **Apple Watch Series 5** (live, trail-right) **and** **WHOOP 5.0** (delayed + readiness/recovery/strain) in one app. Not Watch-only. Not WHOOP-only.

## Done criteria (software-complete)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | WhoopGolf + WhoopGolfWatch BUILD SUCCEEDED | **PENDING on Mac** — Linux cloud has no `xcodebuild` |
| 2 | Watch face: path + improver + yards + HR + hole | **MET** (+ phone `lastPathScore` badge) |
| 3 | trail-right default | **MET** |
| 4 | Stroke score + plain-language explanation | **MET** — persisted on `GolfSwingMetrics` + Round board |
| 5 | Inter-swing GPS shot yardage | **MET** |
| 6 | Phone: Overview + WHOOP readiness/recovery/strain/delayed | **MET** — Overview tab + fusion board |
| 7 | Trends miss / tempo sparkline / post-round sheet | **MET** |
| 8 | Hybrid coordinator; no live-IMU hang | **MET** (+ delayed enrich after import) |
| 9 | Unit tests for score polarity / yards / hybrid | **ADDED** `StrokeScoreShotChainTests` (run on Mac) |
| 10 | Vault App Overview + D19 note | **MET** (`docs/vault/...`) |
| 11 | Physical Watch install | **GATED** on user OS-update ping |

## Notes

- Persist: `pathScore` / `pathExplanation` / `improverTip` via `StrokeScoreShotChain.enrichSwingMetrics` on Watch import + WHOOP delayed import.
- Live face: `PhoneYardageBridge.makeLiveFace` now fills path score / stroke count for Watch.
- Overview: `AppModel.Tab.overview` + `OverviewView`.

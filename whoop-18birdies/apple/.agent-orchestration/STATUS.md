# WHOOP Golf — Orchestration STATUS (D19 both-required civilization)

Updated: 2026-08-21 (Mac-readiness after Alex: "xcode is good to go")  
Outcome: **SOFTWARE_COMPLETE** — Mac `xcodebuild` still required for green-build proof  
Cloud recheck: `which xcodebuild` → **not found** (Linux) → **NO_XCODE** remains; do **not** clear until a real SUCCEEDED log lands  
Product bible: `PRODUCT.md` · Vault: **D19 both-required**

## Mandate

Maximize **Apple Watch Series 5** (live, trail-right) **and** **WHOOP 5.0** (delayed + physiology) in one app. **New rounds require both.**

## Agent board

| Role | Status | Notes |
|------|--------|-------|
| manager | DONE | Waves A–C closed; pbxproj membership applied |
| error-fixer-learner | DONE | LESSONS L6–L8; NO_XCODE; Shared allowlist; pbxproj HANDOFF applied; duplicate FusionTests entry removed |
| dual-gate-admission | DONE | DualWearableRequirement + startRound + Round CTA |
| comprehensive-shot-intel | DONE | Club / ball-start / attack dossier + boards |
| trail-right-motion | DONE | Trail-right polarity evidence |
| wearable-architecture | DONE | Hybrid preserve path/club; fusion HR policy |
| watch-round-face | DONE | Score, club, ball-start, improver, HR, yards |
| watch-connectivity | DONE | Live face v3 Codable sync |
| phone-yardage-bridge | DONE | N→N+1 yards + face enrichment |
| whoop-physio-merge | DONE | Delayed enrich + Overview/Today/Settings copy |
| automated-tests | DONE | Gate + chain + hybrid preserve tests (Mac run) |
| vault-obsidian-graphify | DONE | App Overview + D19 both-required |
| xcode-ship | WAITING_MAC | Alex Mac Xcode ready; cloud still NO_XCODE — run `scripts/mac-d19-verify.sh` |

## Software-complete checklist

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Builds green | **PENDING Mac** (`NO_XCODE` here); static membership OK (WatchRoundContext on Watch; phone-only Shared off Watch) |
| 2 | Dual gate blocks single-wearable start | **MET** |
| 3 | Watch face complete | **MET** |
| 4 | trail-right default | **MET** |
| 5 | Stroke score+club+ball+yards | **MET** |
| 6 | Inter-swing GPS yards | **MET** |
| 7 | Overview + WHOOP physio | **MET** |
| 8 | Hybrid no double-count / no Arming | **MET** |
| 9 | Tests | **MET** (sources + pbxproj; run on Mac via script below) |
| 10 | LESSONS ≥3 | **MET** (L1–L8) |
| 11 | Vault overview | **MET**; Watch install **OS-gated** (do not claim installed) |

## Mac one-paste (Alex)

Alex signaled Xcode is ready. From repo root on the Mac:

```bash
bash whoop-18birdies/apple/scripts/mac-d19-verify.sh
```

Equivalent expanded commands (do **not** use `-derivedDataPath` under iCloud `~/Documents` — LESSONS L3):

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

If `iPhone 16` is missing, use `iPhone 15` or any booted iOS Simulator destination from `xcodebuild -scheme WhoopGolf -showdestinations`.

Physical Watch install only after Alex confirms Watch OS update done — **not** part of green-build proof.

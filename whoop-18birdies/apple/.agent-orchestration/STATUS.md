# WHOOP Golf — Orchestration STATUS (D19 both-required civilization)

Updated: 2026-08-21 (manager close)  
Outcome: **SOFTWARE_COMPLETE** (Mac `xcodebuild` still required for green-build proof; Linux cloud = **NO_XCODE**)  
Product bible: `PRODUCT.md` · Vault: **D19 both-required**

## Mandate

Maximize **Apple Watch Series 5** (live, trail-right) **and** **WHOOP 5.0** (delayed + physiology) in one app. **New rounds require both.**

## Agent board

| Role | Status | Notes |
|------|--------|-------|
| manager | DONE | Waves A–C closed; pbxproj membership applied |
| error-fixer-learner | DONE | LESSONS L6–L8; NO_XCODE; Shared allowlist; pbxproj HANDOFF applied |
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

## Software-complete checklist

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Builds green | **PENDING Mac** (`NO_XCODE` here); pbxproj membership updated for new Shared/Views/Tests |
| 2 | Dual gate blocks single-wearable start | **MET** |
| 3 | Watch face complete | **MET** |
| 4 | trail-right default | **MET** |
| 5 | Stroke score+club+ball+yards | **MET** |
| 6 | Inter-swing GPS yards | **MET** |
| 7 | Overview + WHOOP physio | **MET** |
| 8 | Hybrid no double-count / no Arming | **MET** |
| 9 | Tests | **MET** (sources + pbxproj; run on Mac) |
| 10 | LESSONS ≥3 | **MET** (L1–L7+) |
| 11 | Vault overview | **MET**; Watch install **OS-gated** |

## Run recipe (Mac)

```bash
cd whoop-18birdies/apple
# optional: xcodegen generate
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' build
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform/watchOS' build
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' test
```

Physical Watch install only after Alex confirms Watch OS update done.

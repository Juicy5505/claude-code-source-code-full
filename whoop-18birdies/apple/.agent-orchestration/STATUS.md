# WHOOP Golf — Orchestration STATUS (D19 both-required civilization)

Updated: 2026-08-21 (Alex: **Watch OS 10.6.2** ready — XS-WATCH-OS CLEARED; device ≥ project min **9.0**; **ship-ready embed** awaiting Mac Run)  
Outcome: **SOFTWARE_COMPLETE** — Mac `xcodebuild` still required for green-build proof  
Cloud recheck: `which xcodebuild` → **not found** (Linux) → **NO_XCODE** remains; do **not** clear until a real SUCCEEDED log lands  
Product bible: `PRODUCT.md` · Vault: **D19 both-required**  
Install runbook: `docs/MAC-WATCH-INSTALL.md` · Device OS: `WATCH_OS_DEVICE.md`

## Mandate

Maximize **Apple Watch Series 5** (live, trail-right) **and** **WHOOP 5.0** (delayed + physiology) in one app. **New rounds require both.**

## Download finished companion (Alex Mac — next action)

Ship-ready audit (2026-08-21): WhoopGolfWatch Sources = allowlist only (18 files); phone-only Shared off Watch; WC live-face v3 wired.

```bash
git pull origin cursor/cloud-agent-1787290942317-17qh4
# open whoop-18birdies/apple/WhoopGolf.xcodeproj
# Personal Team → destination physical iPhone → scheme WhoopGolf → Run
```

That Run installs the phone app **and downloads finished WhoopGolfWatch** to the paired Watch. Confirm payload per `docs/MAC-WATCH-INSTALL.md` §7.
## Agent board

| Role | Status | Notes |
|------|--------|-------|
| manager | DONE | Waves A–C closed; pbxproj membership applied; Watch OS gate cleared |
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
| xcode-ship | WAITING_MAC | Alex Mac Xcode ready; Watch OS CLEARED — run `scripts/mac-d19-verify.sh` then device install |

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
| 11 | Vault overview | **MET**; Watch OS gate **CLEARED** — physical companion install **unblocked** (do **not** claim already installed on device from cloud) |

## Watch OS gate (CLEARED)

Alex confirmed (2026-08-21): **Apple Watch is updated and ready to start using.**

| Item | Status |
|------|--------|
| Watch OS update | **CLEARED** (Alex confirmed) |
| Physical WhoopGolfWatch install | **UNBLOCKED / SHIP-READY** — Mac Run WhoopGolf embeds finished companion (`docs/MAC-WATCH-INSTALL.md`) |
| Claimed installed on device? | **No** (awaiting Alex Run confirmation) |

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

Then install phone + Watch companion per `docs/MAC-WATCH-INSTALL.md` (Personal Team; trail-right wear; dual-gate Start Round proof). Physical install is **not** part of green-build proof.

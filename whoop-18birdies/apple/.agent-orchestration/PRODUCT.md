# PRODUCT.md — WHOOP Golf dual-wearable bible

**Mandate date:** 2026-08-21  
**Decision:** Vault **D19** (does not rewrite D15 / D18 history)  
**Canonical app:** `whoop-18birdies/apple/WhoopGolf.xcodeproj` · bundle `com.alex.whoopgolf` · **one golf icon**

> **STOP:** Watch-only priority is over. **STOP:** WHOOP-only priority is over.  
> **STOP:** New rounds without both wearables.  
> Build fully to maximize **Apple Watch Series 5** AND **WHOOP 5.0** in one golf app. No approval gates for product features. Manager does not implement; agents do.

---

## Product north star

One golfer-facing app that uses every capability Alex wears:

| Source | Role |
|--------|------|
| **Apple Watch Series 5** (trail **right** wrist) | Primary **live** motion/swing path score + explanation, HR, on-wrist UX (path, improver, yards, hole, club, ball-start label), workout ownership |
| **WHOOP 5.0** | **Delayed** motion import / Check for WHOOP swings; readiness / recovery / strain; optional HR Broadcast when Watch is not HR owner; **never** hang on live `TOGGLE_IMU` / Arming |
| **iPhone GPS** | Distance between consecutive **verified** swings (= that shot’s yardage); course context; round map |

### Admission (D19 both-required)

- **New rounds require both** Apple Watch live-capture proven **and** WHOOP swing source proven (`DualWearableRequirement`).
- Watch-only / WHOOP-only / manual remain **diagnostic plan modes** in `SensorModeCoordinator` only — they are **not startable products**.
- Existing drafts on disk stay readable.

D15’s three modes remain historical contract documentation. D19 execution is **Hybrid maximize-both** with a hard dual gate.

---

## Core product loops (must ship)

### 1. Swing path relative to body
- Each **verified** stroke gets a **numeric score** + **plain-language explanation**.
- Story from trail-right Watch motion (path, tempo).
- When WHOOP delayed motion matches the same window, enrich without double-counting.

### 2. Shot yardage
- **Yardage for shot N** = phone GPS distance between verified swing N and swing N+1. Last swing stays pending.
- Honest labeling: GPS displacement, not carry / launch-monitor.

### 3. Comprehensive tracking (shipped by decision)
- Club-in-hand (golfer-selected; sensors never invent club)
- Derived ball-start **tendency** (not radar carry/spin)
- Attack/delivery feel (coaching)
- Hybrid fusion caption (Watch live + WHOOP enrich)
- Overview health glass + Obsidian App Overview + graphify checkpoints

### 4. UI uses every capability

**Watch face:** path score · explanation · improver · yards · HR · hole · club · ball-start label  

**Phone:** Round stroke board + comprehensive board · Overview fusion/readiness · Trends miss/tempo · Settings Check for WHOOP swings · dual gate preflight

---

## Sensor truth (non-negotiable)

1. Watch S5 trail-right = primary live motion + on-wrist coaching display.
2. WHOOP 5.0 = delayed import + physiology; never block UX on live Arming.
3. Phone GPS = inter-swing distances + course context.
4. Provenance honest; never label phone GPS as WHOOP hardware.
5. One icon; companion lives in apple/ WhoopGolf (not Kit A install target).
6. Physical Watch companion install is **allowed** (Watch OS gate CLEARED 2026-08-21). Follow `docs/MAC-WATCH-INSTALL.md`; do not claim on-device install from cloud.

---

## Software-complete (Outcome = SOFTWARE_COMPLETE)

| # | Criterion |
|---|-----------|
| 1 | WhoopGolf + WhoopGolfWatch `BUILD SUCCEEDED` (Mac) |
| 2 | DualWearableRequirement blocks start unless Watch + WHOOP |
| 3 | Watch face: path + improver + yards + HR + hole + club/ball labels |
| 4 | trail-right default |
| 5 | Verified strokes: score + explanation + club + ball-start + yards |
| 6 | Inter-swing phone GPS yardage |
| 7 | Overview + WHOOP readiness/recovery/strain + delayed merge |
| 8 | Hybrid reconcile; no live-IMU hang; no double-count |
| 9 | Tests for gate / polarity / yards / hybrid preserve |
| 10 | `LESSONS.md` ≥ 3 patterns |
| 11 | Vault App Overview sanitized; STATUS Outcome complete; Watch OS gate CLEARED — install unblocked |

---

## Agent civilization (12 roles)

| Role | Purpose |
|------|---------|
| **manager** | TASKS / STATUS / HANDOFFS / PRODUCT only — no product code |
| **error-fixer-learner** | Cross-agent compile fixes + LESSONS + build verify |
| dual-gate-admission | Both-required start gate |
| comprehensive-shot-intel | Club / path / ball-start / attack dossier + UI |
| watch-round-face | On-wrist max UX |
| trail-right-motion | Body-relative path polarity |
| watch-connectivity | WCSession live face + round ID |
| phone-yardage-bridge | Swing-to-swing GPS yards |
| whoop-physio-merge | Delayed WHOOP + readiness surfaces |
| wearable-architecture | Hybrid reconcile + DualWearableFusion |
| automated-tests | Regressions |
| vault-obsidian-graphify | App Overview + graphify checkpoints |

See `TASKS.md` for exclusive file ownership.

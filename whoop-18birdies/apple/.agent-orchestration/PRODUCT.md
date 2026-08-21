# PRODUCT.md — WHOOP Golf dual-wearable bible

**Mandate date:** 2026-08-21  
**Decision:** Vault **D19** (does not rewrite D15 / D18)  
**Canonical app:** `whoop-18birdies/apple/WhoopGolf.xcodeproj` · bundle `com.alex.whoopgolf` · **one golf icon**

> **STOP:** Watch-only priority is over. **STOP:** WHOOP-only priority is over.  
> Build fully to maximize **Apple Watch Series 5** AND **WHOOP 5.0** in one golf app. No approval gates for product features. Manager does not implement; agents do.

---

## Product north star

One golfer-facing app that uses every capability Alex wears:

| Source | Role |
|--------|------|
| **Apple Watch Series 5** (trail **right** wrist) | Primary **live** motion/swing path, HR, on-wrist UX (path cue, improver, yards, hole), workout ownership when selected |
| **WHOOP 5.0** | **Delayed** motion import / Check for WHOOP swings; readiness / recovery / strain; optional HR Broadcast when not conflicting with Watch workout; **never** hang on live `TOGGLE_IMU` / Arming (firmware refuses live raw IMU) |
| **iPhone GPS** | Distance between consecutive **verified** swings (= that shot’s yardage); course context; round map |

D15’s three modes (WHOOP-only / Watch-only / Hybrid) remain the long-term contract. **D19 execution priority** is **Hybrid maximize-both**: ship the richest Hybrid experience by default; Watch-only and WHOOP-delayed-only remain honest fallbacks when a sensor is missing.

---

## Core product loops (must ship)

### 1. Swing path relative to body
- Each **verified** stroke gets a **numeric score** + **plain-language explanation**.
- Story from trail-right Watch motion (path, tempo, face/path narrative).
- When WHOOP delayed motion is available for the same window, merge provenance-honestly into explanation (do not relabel Watch as WHOOP or invent IMU).

### 2. Shot yardage
- Track each verified swing.
- **Yardage for shot N** = GPS distance between verified swing N and swing N+1 (phone GPS). Last swing stays pending.
- Optional heuristics: tee / approach / putt (useful labels, never fake precision).
- UI must say shot/GPS displacement honestly (see D5 provenance spirit).

### 3. UI uses every capability on him

**Watch face (live):**
- Path cue · improver · yards · HR · hole (honest empty when no hole map)

**Phone:**
- Round map + stroke list with scores / explanations / shot distances
- WHOOP readiness / recovery / strain / delayed swings
- Watch connection status
- **Expand (agents invent high-value extras without asking):** stroke journal, session summary, consistency trends, miss pattern (left/right), tempo history, “next shot” coaching, and more that clearly help a round

---

## Sensor truth (non-negotiable)

1. Watch S5 trail-right = primary live motion + on-wrist coaching display.
2. WHOOP 5.0 = delayed import path + physiology; **do not** block UX waiting for live raw IMU Arming.
3. Phone GPS = inter-swing distances + course context.
4. Provenance in UI (D2): never silent demo substitution; never label phone GPS as WHOOP hardware (D14).
5. One icon; Kit A standalone is not the golfer-facing install; companion lives in apple/ WhoopGolf.
6. Physical Watch install still waits until Alex confirms Watch OS update done (ops gate only — software continues).

---

## Software-complete (Outcome = COMPLETE)

| # | Criterion |
|---|-----------|
| 1 | WhoopGolf + WhoopGolfWatch `BUILD SUCCEEDED` |
| 2 | Watch face shows path + improver + yards + HR + hole (honest empties OK) |
| 3 | trail-right is default wrist |
| 4 | Verified strokes expose **score + plain-language explanation** (Watch and/or phone) |
| 5 | Inter-swing phone GPS yardage between consecutive verified swings |
| 6 | Phone surfaces Watch connection + WHOOP readiness/recovery/strain/delayed swings |
| 7 | At least three expanded phone surfaces shipped or clearly wired: journal / summary / trends / miss pattern / tempo history / next-shot coaching (agents choose high-value set) |
| 8 | SensorModeCoordinator Hybrid path maximizes Watch live + WHOOP delayed; no live-IMU hang |
| 9 | Tests compile; trail-right / path / face honesty covered |
| 10 | `LESSONS.md` ≥ 3 learned fix patterns |
| 11 | STATUS Outcome = COMPLETE with Run recipe (Watch install after OS update) |

---

## Agent roster (purposes under D19)

| Agent | Purpose under dual-wearable |
|-------|----------------------------|
| watch-round-face | Watch live face: path, improver, yards, HR, hole |
| trail-right-motion | Trail-right CoreMotion → path class / inputs for score |
| watch-connectivity | WCSession: live face, wrist, session JSON phone↔Watch |
| phone-yardage-bridge | Inter-swing GPS yardage + tee/approach/putt heuristics + round map/list distances |
| watch-healthkit | Watch HK workout + HR for face |
| xcode-ship | Green builds both schemes + tests compile signal |
| wearable-architecture | Hybrid maximize-both in SensorModeCoordinator; WHOOP delayed; no TOGGLE_IMU hang |
| golf-improver-engine | Score + explanation + next-shot / miss / tempo coaching APIs (+ phone coaching UI) |
| automated-tests | Unit coverage for path, trail-right, yardage contracts, face honesty |
| tailscale-ingest | `wb serve` / delayed WHOOP ingest reachability (no secrets logged) |
| error-fixer-learner | Compile fixes + LESSONS.md (≥3 patterns) |

See `TASKS.md` for exclusive file ownership.

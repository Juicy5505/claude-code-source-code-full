# TASKS — D19 dual-wearable (manager-owned)

Workspace: `/Users/alex/Documents/claude-code-source-code-full`  
Canonical: `whoop-18birdies/apple/WhoopGolf.xcodeproj` · `com.alex.whoopgolf`  
Bible: `PRODUCT.md` · Decision: **D19**

**Rules**
1. Graphify first before code exploration: `graphify query "<topic>"`.
2. Write/update `.agent-orchestration/agents/<name>.md` (Status / Done / Gaps / Files / Evidence). Mark **D19** in the header.
3. Exclusive ownership below. Foreign file → HANDOFFS.md.
4. No secrets. No physical Watch install.
5. Prefer gap-fill; invent high-value golf UX without asking (PRODUCT §3).
6. **Not Watch-only. Not WHOOP-only.** Hybrid maximize-both.

---

## 1. watch-round-face
**Purpose:** Watch live face uses every on-wrist capability.  
**Own:** `whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift`, `SettingsView.swift`  
**D19 Do:**
- Keep path + improver + yards (already verified C0).
- Confirm/show **HR** and **hole** on the live face (honest empty OK).
- Re-file `agents/watch-round-face.md` with Status DONE under D19 or list Gaps.
**Follow-up resume if agent idle:** reopen with “D19: HR + hole tiles on SessionView”.

## 2. trail-right-motion
**Purpose:** Trail-right motion → path class / score inputs.  
**Own:** `Shared/WatchWristPreference.swift`, `Shared/SwingPathGuidance.swift`, `watch/.../MotionManager.swift`  
**D19 Do:**
- Keep trail-right default + mirror math (DONE).
- Ensure APIs expose what golf-improver needs for **score + explanation** (document; minimal glue if missing).
- Status remains DONE unless improver needs a new Shared helper in these files.

## 3. watch-connectivity
**Purpose:** WCSession sync for Hybrid UX.  
**Own:** `watch/.../WatchSessionTransfer.swift`, `WatchSupport/WatchSessionReceiver.swift`  
**D19 Do:**
- Activate session; live face publish/receive (yards, hole, path-related fields, HR if carried).
- Session JSON aligned with phone importer; wrist sync.
- File first `agents/watch-connectivity.md` (still missing).
**Follow-up:** resume agent — “file status + fix any missing liveFace keys for HR/hole/yards”.

## 4. phone-yardage-bridge
**Purpose:** Inter-swing GPS yardage + round geography UI.  
**Own:** `Shared/WatchLiveFace.swift`; yardage/publish in `WhoopGolf/App/AppModel.swift`; phone round distance UI in `WhoopGolf/Views/RoundView.swift` (distance/list sections only — HANDOFF if contested)  
**D19 Do:**
- Shot N yardage = GPS distance swing N → N+1; last pending.
- Tee/approach/putt heuristics if useful.
- Round map/list shows per-stroke distances; honest labeling.
- File `agents/phone-yardage-bridge.md`.
**Follow-up:** resume — “implement inter-swing yardage + list rows”.

## 5. watch-healthkit
**Purpose:** Watch workout + HR for face.  
**Own:** `watch/.../WorkoutManager.swift`  
**D19 Do:** Wire/confirm HK start/stop + HR updates consumed by SessionView. File status md.  
**Follow-up:** resume if no report.

## 6. xcode-ship
**Purpose:** Builds green.  
**Own:** `agents/xcode-ship.md` only (no product edits).  
**D19 Do:**
```bash
cd whoop-18birdies/apple
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' build
xcodebuild -scheme WhoopGolfWatch -destination 'generic/platform=watchOS' build
# tests compile signal
xcodebuild -scheme WhoopGolf -destination 'generic/platform=iOS' -only-testing:WhoopGolfTests build-for-testing
```
Report SUCCEEDED/FAILED; failures → HANDOFFS for error-fixer.  
**Follow-up:** resume immediately — critical path for criterion 1/9.

## 7. wearable-architecture
**Purpose:** Hybrid maximize Watch live + WHOOP delayed.  
**Own:** `Shared/SensorModeCoordinator.swift`  
**D19 Do (re-aim):**
- Cancel Watch-only-as-default execution bias from C0.
- Prefer Hybrid plan when both available; Watch live motion + WHOOP delayed/physiology.
- **Never** block UX on live TOGGLE_IMU / Arming failure — degrade to delayed Check for WHOOP swings.
- Surface mode selection honestly for phone UI consumers.
- Update `agents/wearable-architecture.md` with Hybrid evidence.
**Follow-up:** resume — “D19 Hybrid maximize-both; no IMU hang”.

## 8. golf-improver-engine
**Purpose:** Score + plain-language explanation + expanded coaching.  
**Own:** `Shared/GolfImprover.swift`; new Shared helpers if needed (`Shared/SwingStrokeScore.swift` OK to create); phone coaching/trends UI under `WhoopGolf/Views/` files you create or HANDOFF-claim (e.g. `StrokeJournalView`, trends section)  
**D19 Do:**
- Each verified stroke → **score + explanation** (path/tempo/face-path from trail-right; WHOOP delayed when available via provenance fields).
- Ship APIs + UI hooks for: next-shot coaching, miss left/right, tempo history (pick ≥2 phone surfaces).
- File status md.
**Follow-up:** resume — “score+explanation + next-shot/miss/tempo surfaces”.

## 9. automated-tests
**Purpose:** Dual-wearable regressions.  
**Own:** `WhoopGolfTests/SwingPathGuidanceTests.swift` + new `WhoopGolfTests/*Stroke*` / yardage tests you add  
**D19 Do:** trail-right, path mirror, face honesty, score/yardage contracts as APIs stabilize. File status.  
**Follow-up:** resume after improver/yardage APIs land.

## 10. tailscale-ingest
**Purpose:** Delayed WHOOP / bridge ingest reachability.  
**Own:** `agents/tailscale-ingest.md` only  
**D19 Do:** DONE (REACHABLE_LOCAL). Optional refresh if bind mode changes for phone reachability — still no secrets.  
**Note:** localhost-only bind means phone needs Tailscale-reachable bind — document only.

## 11. error-fixer-learner
**Purpose:** Green builds + institutional memory.  
**Own:** `LESSONS.md`; product files only after HANDOFFS claim  
**D19 Do:**
- Write ≥3 patterns (Symptom → Cause → Fix): e.g. trail-right unset, invented hole map, WHOOP live IMU hang, Shared membership watchOS, inter-swing pending last shot.
- Fix compile breaks from xcode-ship.
- File `agents/error-fixer-learner.md`.
**Follow-up:** resume now — LESSONS body empty.

---

## Resume queue (manager → next spawn)

Priority order if agents must be re-launched:
1. xcode-ship  
2. error-fixer-learner (LESSONS ≥3)  
3. wearable-architecture (Hybrid)  
4. golf-improver-engine (score+explanation)  
5. phone-yardage-bridge (inter-swing yards)  
6. watch-connectivity / watch-healthkit  
7. watch-round-face D19 reopen (HR+hole)  
8. automated-tests  

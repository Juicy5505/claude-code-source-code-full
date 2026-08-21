# TASKS — D19 both-required agent civilization (manager-owned)

Workspace: `/workspace`  
Canonical: `whoop-18birdies/apple/WhoopGolf.xcodeproj` · `com.alex.whoopgolf`  
Bible: `PRODUCT.md` · Decision: **D19 both-required**

**Rules**
1. Graphify first before broad exploration when available.
2. Write/update `.agent-orchestration/agents/<name>.md` (Status / Done / Gaps / Files / Evidence). Mark **D19** in the header.
3. Exclusive ownership below. Foreign file → HANDOFFS.md.
4. No secrets. No physical Watch install.
5. Prefer gap-fill; invent high-value golf UX without asking.
6. **New rounds require Watch + WHOOP.** Not Watch-only starts. Not WHOOP-only starts.

---

## Manager
**Own:** TASKS.md, STATUS.md, HANDOFFS.md, PRODUCT.md  
**Do:** Delegate one concrete next task per agent; clear HANDOFFS; never write product Swift.

## Error-fixer-learner
**Own:** LESSONS.md, cross-agent compile breaks, build verify notes  
**Do:** Search LESSONS before fixing; append patterns; static-audit `project.yml` on Linux; xcodebuild on Mac when present. Never rewrite product policy.

---

## 1. dual-gate-admission
**Purpose:** Both-required start gate.  
**Own:** `Shared/DualWearableRequirement.swift`; Round preflight dual-gate card + start `.disabled`; `AppModel` `dualWearableAdmission` / `canStartDualWearableRound` / `startRound` gate  
**Do:** Ensure start is impossible unless `.satisfied`; copy honest; tests already seeded — gap-fill only.

## 2. comprehensive-shot-intel
**Purpose:** Club + path + ball-start + attack dossier.  
**Own:** `Shared/ComprehensiveShotIntelligence.swift`; stroke board/presentation tracking display; Round club picker + `ComprehensiveTrackingBoard` in `WatchCompanionPanels.swift` / Round sections you already own  
**Do:** Gap-fill UI bind; keep “tendency not radar” copy.

## 3. watch-round-face
**Purpose:** On-wrist max UX.  
**Own:** `watch/WhoopGolfWatchApp/WatchRoundFaceView.swift`, `SessionView.swift`  
**Do:** Confirm score, explanation, yards, HR, hole, club/ball labels, improver screens.

## 4. trail-right-motion
**Purpose:** Body-relative path polarity.  
**Own:** `Shared/WatchWristPreference.swift`, `Shared/SwingPathGuidance.swift`, `watch/.../MotionManager.swift`  
**Do:** Keep trail-right default + mirror math; document APIs for score chain.

## 5. watch-connectivity
**Purpose:** WCSession sync.  
**Own:** `watch/.../WatchSessionTransfer.swift`, `WatchSupport/WatchSessionReceiver.swift`, Shared WC contracts (`WatchRoundContext`, `WatchCoachingCue`, live face codec consumers)  
**Do:** Live face v3 keys (club/ball/path score) publish/receive; round ID link.

## 6. phone-yardage-bridge
**Purpose:** Swing-to-swing GPS yards.  
**Own:** `Shared/PhoneYardageBridge.swift`, `Shared/WatchLiveFace.swift`, AppModel `publishWatchLiveFace`  
**Do:** Keep N→N+1 yards; face enrichment with path/club/ball labels.

## 7. whoop-physio-merge
**Purpose:** Delayed WHOOP + readiness.  
**Own:** `WhoopGolf/Services/WhoopMotionImportService.swift`; Overview/Today readiness+fusion copy; Settings Check-for-swings sections  
**Do:** Enrich after finalize; never Arming hang; surface recovery/strain.

## 8. wearable-architecture
**Purpose:** Hybrid reconcile no double-count.  
**Own:** `Shared/SensorModeCoordinator.swift`, `Shared/DualWearableFusion.swift`  
**Do:** Preserve path/club on `materializedObservation`; HR ownership rules; fused status.

## 9. automated-tests
**Purpose:** Regressions.  
**Own:** `WhoopGolfTests/DualWearableRequirementTests.swift`, `StrokeScoreShotChainTests.swift`, related swing/path tests you add  
**Do:** Gate, polarity, yards, hybrid preserve, ball-start.

## 10. vault-obsidian-graphify
**Purpose:** Health+app overview loop.  
**Own:** `docs/vault/10 Projects/Whoop Golf Companion/**`, Cursor memory mirrors, STATUS graphify checkpoint notes  
**Do:** Sanitize App Overview; D19 decision note; no secrets; document graphify cadence.

---

## Integrator (manager-routed)
**Own:** `project.yml` / `project.pbxproj` single-writer when membership changes requested via HANDOFFS.

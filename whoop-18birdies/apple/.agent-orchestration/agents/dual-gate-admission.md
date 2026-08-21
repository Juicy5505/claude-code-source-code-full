# dual-gate-admission — D19 both-required

**Status:** DONE  
**Wave:** WAVE_A  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- `DualWearableRequirement` evaluates Watch live-capture + WHOOP swing source; only `.satisfied` sets `allowsStart`.
- `AppModel.startRound` returns early when `!admission.allowsStart` and forces `RoundRecorder.hybrid` (ignores Watch-only / WHOOP-only / manual preference).
- Round preflight: dual-gate card, PreflightRow Watch/WHOOP **Required for every round** states, start button `.disabled(!canStartDualWearableRound)`.
- CTA copy centralized via `DualWearableRequirement.startButtonTitle(for:)` so blocked states name Watch, WHOOP, or both.
- Detail copy explicitly states Watch-only / WHOOP-only starts are not allowed.

## Gaps
- None for admission gate (Mac `BUILD SUCCEEDED` / device prove-out owned by build-verify / install-prove roles).

## Files
- `Shared/DualWearableRequirement.swift`
- `WhoopGolf/Views/RoundView.swift` (dual-gate card, PreflightRow Watch/WHOOP, start button)
- `WhoopGolf/App/AppModel.swift` (`dualWearableAdmission` / `canStartDualWearableRound` / `startRound` gate only)

## Evidence
- Policy: `DualWearableRequirement.evaluate` → missingWatch / missingWhoop / missingBoth / hybridDegraded all `allowsStart == false`.
- UI: Round start Label uses `startButtonTitle(for:)`; button disabled + opacity 0.45 when gated; accessibilityHint carries blocked detail.
- Server gate: `AppModel.startRound` `guard admission.allowsStart else { notice = …; return }`.
- Tests (owned by wearable-tests): `DualWearableRequirementTests` — `testMissingBothBlocksStart`, `testWatchOnlyIsMissingWhoop`, `testWhoopOnlyIsMissingWatch`, `testBothProvenSatisfiesHybrid`.

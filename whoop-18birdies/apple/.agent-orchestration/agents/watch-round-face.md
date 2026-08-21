# watch-round-face

**Status:** DONE (D19)  
**Agent:** watch-round-face  
**Checked:** 2026-08-21  
**Decision:** D19 dual-wearable  
**graphify:** `graphify query "SessionView HR hole GolfImprover drill wrist"`

## Verdict

Live Watch face already showed path / improver / yards / HR (C0). D19 reopen: confirmed HR + hole; N1 face drill already passed `wrist:`; gap-fill only for always-visible honest empty hole line.

## Done (D19)

- [x] **HR** on live face — `SessionView` `tile("HR", … ?? "—")`; wired `onReceive(workout.$heartRate)` → `session.currentHR` (honest empty `—`)
- [x] **Hole** on live face — `WatchRoundFaceView` yardage page always shows `HOLE N` or `HOLE —`
- [x] **N1 wrist on drill** — `GolfImprover.drill(path:tempoRatio:wrist:)` with `wrist` from `SessionView` → `WatchRoundFaceView`
- [x] Path + improver + yards retained (TabView pages PATH / IMPROVE / YARDAGE)
- [x] Settings wrist picker still defaults trail-right via `WatchWristMount.golferDefault`

## Gaps

None for owned face UI. Non-face leftover: `WatchSessionTransfer` still calls `drill` without `wrist:` — noted under HANDOFFS N1 for watch-connectivity.

## Evidence

| Surface | Where | Behavior |
|---------|-------|----------|
| HR | `SessionView` L75–77, L115 | `tile("HR", session.currentHR.map { "\($0)" } ?? "—")` |
| Hole | `WatchRoundFaceView` yardageScreen | `HOLE \(n)` or `HOLE —` |
| Drill wrist | `WatchRoundFaceView` improverScreen | `GolfImprover.drill(…, wrist: wrist)` |
| Cue wrist | same | `GolfImprover.cue(…, wrist: wrist)` |
| Wrist mount | `SessionView` → face | `wrist: WatchWristMount.load()` |

## Files touched

| File | Action |
|------|--------|
| `WatchRoundFaceView.swift` | gap-fill: always-visible hole line (`HOLE —`) |
| `SessionView.swift` | verified only (HR already present) |
| `SettingsView.swift` | verified only |
| `agents/watch-round-face.md` | this report |
| `HANDOFFS.md` | claimed `WatchRoundFaceView`; updated N1 |

## HANDOFFS

- Claimed ownership of `WhoopGolfWatchApp/WatchRoundFaceView.swift` (face TabView under watch app).
- N1 face side cleared; Transfer-side drill wrist still for watch-connectivity.

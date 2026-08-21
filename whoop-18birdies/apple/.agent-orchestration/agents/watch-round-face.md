# watch-round-face — D19 both-required

**Status:** DONE  
**Wave:** per TASKS.md  
**Mandate:** Hybrid maximize Watch + WHOOP; new rounds require both.

## Done
- `WatchRoundFaceView` pages show path score + explanation, improver cue/drill/miss, yardage (hole / F-M-B / last shot / stroke count / course), live + avg HR, next tip, club code, ball-start label, trail-right wrist feel.
- Prefer phone `WatchLiveFace` v3 for score/label, hole map, club, ball-start, strokeCount, courseName, and `wristMount`.
- Prefer durable `WatchCoachingCue` tip/drill when present; fall back to local `GolfImprover.strokeScore`.
- `SessionView` wires `phoneLink.liveFace`, `coachingCue`, `workout.averageHeartRate`, and `liveFace.wristMount` into the face.

## Gaps
- Physical Watch install / on-device visual QA still gated (board rule).
- WhoopGolfWatch build may still fail on foreign connectivity types (see watch-healthkit / watch-connectivity HANDOFFS) — not owned here.

## Files
- `whoop-18birdies/watch/WhoopGolfWatchApp/WatchRoundFaceView.swift`
- `whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift`
- `whoop-18birdies/apple/.agent-orchestration/agents/watch-round-face.md`

## Evidence
- Live face v3 fields consumed: `lastPathScore`, `lastPathLabel`, `activeClubCode`, `lastBallStartLabel`, `holeNumber`, `frontYards`/`middleYards`/`backYards`, `lastShotYards`, `strokeCount`, `courseName`, `wristMount`.
- Session composition: `WatchRoundFaceView(... liveFace: phoneLink.liveFace, averageHeartRateBPM: workout.averageHeartRate, wrist: phoneLink.liveFace.wristMount, phoneImproverTip/Drill: coachingCue ...)`.
- Trail-right feel copy: `Feel · trail-right wrist` when `liveFace.wristMount == .trailRight`.

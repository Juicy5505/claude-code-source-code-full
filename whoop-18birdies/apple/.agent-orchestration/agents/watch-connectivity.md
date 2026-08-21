# watch-connectivity

**Status:** DONE (D19 connectivity contract)  
**Agent:** watch-connectivity  
**Checked:** 2026-08-21  
**Decision:** D19 dual-wearable  
**graphify:** `graphify query "WCSession WatchSessionTransfer WatchLiveFace"`

## Verdict

WCSession path is wired end-to-end for live face (yards/hole/wrist), coaching (path/improver/HR), round identity, and session JSON file transfer. N1 Transfer-side drill wrist is already explicit. Fixed a wrist-sync wipe that could clear yards/hole from application context.

## Done

- [x] **Activate** — `WatchSessionTransfer.activate()` / `WatchSessionReceiver.activate()` set delegate + activate; Watch applies `receivedApplicationContext` on activate
- [x] **N1 wrist on drill** — `sendLiveSwing` uses `WatchWristMount.load()` for both `GolfImprover.cue` and `GolfImprover.drill` (HANDOFFS N1 Transfer leftover cleared)
- [x] **Live face publish (phone → Watch)** — `AppModel.publishWatchLiveFace` → `WatchSessionReceiver.publishLiveFace` → `WatchLiveFaceCodec.merge` into `updateApplicationContext`
- [x] **Live face receive (Watch)** — `WatchSessionTransfer.apply` decodes full `WatchLiveFace` (hole, F/M/B, lastShotYards, path score/label, strokeCount, wrist, courseName)
- [x] **Yards / hole fields** — carried on `WatchLiveFace` schema v2 keys; honest nil when no map / no measured shot
- [x] **HR** — not on live-face envelope; carried Watch→phone on `WatchCoachingCue.heartRateBPM` / userInfo `"hr"` via `sendLiveSwing` + `transferUserInfo`; phone stores `lastWatchHeartRate`
- [x] **Wrist sync** — `setWrist` + coaching userInfo + message; durable when unreachable
- [x] **Wrist wipe fix** — `setWrist` no longer merges an empty `WatchLiveFace(wristMount:)`; preserves context/local yards/hole before re-merge
- [x] **Session JSON** — Watch `transferSession` file + metadata (`sessionID`, `mode`, `schemaVersion`, optional `roundID`); phone `WatchSessionPayloadDecoder` + importer path
- [x] **Shared types on disk** — `Shared/WatchRoundContext.swift`, `WatchLiveFace.swift`, `WatchCoachingCue.swift` exist; pbx currently lists them for iOS + Watch (see Gaps / XS-2)

## Gaps

| Gap | Owner | Notes |
|-----|-------|-------|
| XS-1 / XS-2 build green | error-fixer-learner + integrator | Types exist; Watch build still fails if `project.pbxproj` membership regresses. Do **not** edit pbx here — route to integrator single-writer. |
| Phone inbound live-face | by design | `WatchSessionReceiver.applyInboundApplicationContext` only applies wrist from face decode; phone remains authoritative for yards/hole via `publishLiveFace`. |
| Physical Watch install | ops | Gated on Alex Watch OS update — no install this pass. |
| Device smoke | deferred | No paired Watch exercise this session; contract verified in source + graphify. |

## Evidence

| Direction | Mechanism | Keys / fields |
|-----------|-----------|---------------|
| Phone → Watch live face | applicationContext | `com.alex.whoopgolf.live-face` → holeNumber, front/middle/backYards, lastShotYards, lastPath*, strokeCount, wristMount, courseName |
| Phone → Watch round ID | applicationContext | `com.alex.whoopgolf.round-context` active/cleared envelope |
| Phone → Watch coaching | applicationContext | `com.alex.whoopgolf.coaching` |
| Watch → Phone coaching / HR | transferUserInfo + sendMessage | kind=coaching; pathCue, improverTip/Drill, wristMount, peakG, **hr** |
| Watch → Phone session | transferFile | JSON schema v1 + metadata sessionID/mode/roundID |
| Watch local face apply | didReceiveApplicationContext | full `liveFace = face` |

## Files touched

| File | Action |
|------|--------|
| `watch/.../WatchSessionTransfer.swift` | N1 verified already fixed; `setWrist` preserves yards/hole |
| `WatchSupport/WatchSessionReceiver.swift` | verified publish/receive (no code change) |
| `agents/watch-connectivity.md` | this report |
| `HANDOFFS.md` | N1 Transfer side → DONE |

## Coordinate note (XS-1)

`WatchRoundContext` / `WatchRoundApplicationContextCodec` are present in `Shared/WatchRoundContext.swift` and referenced from Transfer. If WhoopGolfWatch still fails “cannot find type”, it is **pbx membership**, not missing Shared source — integrator XS-2.

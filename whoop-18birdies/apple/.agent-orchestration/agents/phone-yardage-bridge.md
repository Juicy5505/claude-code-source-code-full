# phone-yardage-bridge

Updated: 2026-08-21
Status: **DONE** (software)

## Purpose

Phone GPS + course/hole context → yards the Watch can show.

## Mandate (locked)

- **Stroke yards** = distance between consecutive verified swings (phone GPS), via `SwingShotIntervalCalculator` → `ShotDistanceCalculator`. Newest swing stays pending until the next arrives.
- **Front / mid / back** = optional green targeting overlay from authorized `GolfHoleGreenTargets` only.
- **`GolfCourseLocator`** = facility identity only. Never invents pins or stroke yards.
- Empty yards OK when chain/geometry missing — never fake.

## Done

- Fixed bug: `publishWatchLiveFace` used `swings.last?.shotInterval` (always nil). Now uses `PhoneYardageBridge.lastMeasuredShotYards` over the finalized shot chain.
- `PhoneYardageBridge.makeLiveFace` builds Watch payload: stroke yards from swings + optional F/M/B overlay.
- AppModel wires bridge; clears green targets on round start/finish; refreshes overlay on GPS updates during a live round.
- Facility search fail-closed: `greenTargetsFromFacilitySearch` always returns nil.
- Tests: `WhoopGolfTests/PhoneYardageBridgeTests.swift`.

## Files touched

- `Shared/PhoneYardageBridge.swift` (new)
- `Shared/WatchLiveFace.swift` (docs: stroke vs overlay)
- `Shared/ShotDistanceCalculator.swift` (coord-pair haversine helper)
- `WhoopGolf/App/AppModel.swift` (publish path)
- `WhoopGolfTests/PhoneYardageBridgeTests.swift` (new)
- `WhoopGolf.xcodeproj/project.pbxproj` (iOS + tests membership; not Watch target)

## Gaps / next

- No licensed hole-map provider yet — F/M/B stay empty until `applyHoleGreenTargets` is fed by an authorized source.
- Physical Watch install gated on Alex’s OS update.
- Full `xcodebuild test` currently blocked by **other agents’** tree breakage (missing `GolfTheme` colors, missing `DualWearableFusionTests.swift` path, IMU type mismatches). PhoneYardageBridge sources + tests are on disk and registered for WhoopGolf / WhoopGolfTests only (not Watch). Re-run `PhoneYardageBridgeTests` once integrator clears `project.pbxproj` / theme membership.

## Evidence

- Graphify: `SwingShotIntervalCalculator` → `ShotDistanceCalculator.displacementYards`; `PhoneYardageBridge` → `WatchLiveFace`.
- Contract: last swing has `shotInterval == nil`; prior swings carry measured A→B yards.
- Bug fix: AppModel no longer reads `swings.last?.shotInterval` for Watch `lastShotYards`.

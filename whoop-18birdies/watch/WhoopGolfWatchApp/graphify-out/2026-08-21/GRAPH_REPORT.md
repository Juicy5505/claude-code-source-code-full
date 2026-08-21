# Graph Report - whoop-18birdies/watch/WhoopGolfWatchApp  (2026-08-21)

## Corpus Check
- 12 files · ~9,647 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 215 nodes · 399 edges · 9 communities
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 33 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7bc4d7f6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- SessionModel
- WatchRoundFaceView
- Double
- SessionView
- WorkoutManager
- WatchSessionTransfer
- Foundation
- MotionManager
- GPSSourceCheck

## God Nodes (most connected - your core abstractions)
1. `SessionModel` - 32 edges
2. `MotionManager` - 22 edges
3. `SessionView` - 20 edges
4. `WorkoutManager` - 20 edges
5. `WatchRoundFaceView` - 17 edges
6. `WatchSessionTransfer` - 16 edges
7. `LocationManager` - 15 edges
8. `Swing` - 14 edges
9. `.body` - 12 edges
10. `AdaptiveThreshold` - 12 edges

## Surprising Connections (you probably didn't know these)
- `SessionView` --calls--> `GPSSourceCheck`  [INFERRED]
  whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift → whoop-18birdies/watch/WhoopGolfWatchApp/GPSSourceCheck.swift
- `MotionManager` --calls--> `AdaptiveThreshold`  [INFERRED]
  whoop-18birdies/watch/WhoopGolfWatchApp/MotionManager.swift → whoop-18birdies/watch/WhoopGolfWatchApp/SwingDetector.swift
- `SessionView` --calls--> `MotionManager`  [INFERRED]
  whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift → whoop-18birdies/watch/WhoopGolfWatchApp/MotionManager.swift
- `.body` --references--> `SessionModel`  [INFERRED]
  whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift → whoop-18birdies/watch/WhoopGolfWatchApp/SessionModel.swift
- `SessionView` --calls--> `WorkoutManager`  [INFERRED]
  whoop-18birdies/watch/WhoopGolfWatchApp/SessionView.swift → whoop-18birdies/watch/WhoopGolfWatchApp/WorkoutManager.swift

## Import Cycles
- None detected.

## Communities (9 total, 0 thin omitted)

### Community 0 - "SessionModel"
Cohesion: 0.12
Nodes (23): Codable, Identifiable, GeoPoint, SessionLog, SessionModel, .ingestToken, .ingestURL, .longestYards (+15 more)

### Community 1 - "WatchRoundFaceView"
Cohesion: 0.08
Nodes (25): App, Scene, SettingsView, .body, Void, SwiftUI, View, Double (+17 more)

### Community 2 - "Double"
Cohesion: 0.16
Nodes (12): AdaptiveThreshold, .isReady, MotionSample, Bool, Double, Int, String, SwingPathClass (+4 more)

### Community 3 - "SessionView"
Cohesion: 0.11
Nodes (16): CLLocationManager, CLLocationManagerDelegate, LocationManager, CLLocation, Error, String, ObservableObject, SessionView (+8 more)

### Community 4 - "WorkoutManager"
Cohesion: 0.12
Nodes (15): HKLiveWorkoutBuilder, HKLiveWorkoutBuilderDelegate, HKSampleType, HKWorkoutRouteBuilder, HKWorkoutSession, HKWorkoutSessionDelegate, HKWorkoutSessionState, Set (+7 more)

### Community 5 - "WatchSessionTransfer"
Cohesion: 0.13
Nodes (15): Any, NSObject, UUID, WatchRoundContext, Data, Double, Error, Int (+7 more)

### Community 6 - "Foundation"
Cohesion: 0.12
Nodes (12): Combine, CoreLocation, Foundation, HealthKit, IngestSettings, .isConfigured, .token, .url (+4 more)

### Community 7 - "MotionManager"
Cohesion: 0.14
Nodes (13): CoreMotion, MainActor, MotionManager, .achievedRateHz, .bufferMax, .isAvailable, .walkingFraction, Bool (+5 more)

### Community 8 - "GPSSourceCheck"
Cohesion: 0.31
Nodes (7): CLLocationDistance, GPSSourceCheck, CLLocation, Date, Double, String, TimeInterval

## Knowledge Gaps
- **24 isolated node(s):** `.url`, `.token`, `.isConfigured`, `CoreMotion`, `.bufferMax` (+19 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SessionView` connect `SessionView` to `SessionModel`, `WatchRoundFaceView`, `WorkoutManager`, `Foundation`, `MotionManager`, `GPSSourceCheck`?**
  _High betweenness centrality (0.300) - this node is a cross-community bridge._
- **Why does `MotionManager` connect `MotionManager` to `Double`, `SessionView`?**
  _High betweenness centrality (0.249) - this node is a cross-community bridge._
- **Why does `SessionModel` connect `SessionModel` to `WatchRoundFaceView`, `SessionView`, `Foundation`?**
  _High betweenness centrality (0.241) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `SessionModel` (e.g. with `.body` and `.drainOutbox()`) actually correct?**
  _`SessionModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `MotionManager` (e.g. with `AdaptiveThreshold` and `SessionView`) actually correct?**
  _`MotionManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `SessionView` (e.g. with `GPSSourceCheck` and `LocationManager`) actually correct?**
  _`SessionView` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.url`, `.token`, `.isConfigured` to the rest of the system?**
  _24 weakly-connected nodes found - possible documentation gaps or missing edges._
# Graph Report - whoop-18birdies/apple/Shared  (2026-08-21)

## Corpus Check
- 16 files · ~19,759 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 751 nodes · 2040 edges · 34 communities (32 shown, 2 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 24 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7bc4d7f6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Equatable
- CodingKeys
- String
- GolfRound
- CodingKeys
- Codable
- Foundation
- ReconciledHybridSwing
- WatchRoundContext
- Hashable
- SensorModeCoordinator.swift
- Sendable
- GolfHoleGreenTargets
- MetricSource
- AutomaticHoleTransitionEvidence
- .encode
- AdaptiveSensorPlan
- LocationFix
- GolfHoleTransitionGeometry
- GolfSwingMetrics
- SensorModeConstraint
- .evaluate
- DataProvenance
- RoundRecorder
- WhoopWristQualityReason
- SwingShotDistanceStatus
- AdaptiveSensorMode
- SensorModeOperationalState
- SwingCapturePlan
- Configuration
- ShotSpatialProvider
- ShotConfirmationHapticRoute
- ShotConfirmationTiming
- .encode

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 122 edges
2. `GolfRound` - 48 edges
3. `GolfSwingMetrics` - 38 edges
4. `WatchWristMount` - 38 edges
5. `CodingKeys` - 31 edges
6. `invalidEnvelope` - 28 edges
7. `AdaptiveSensorPlan` - 26 edges
8. `MetricSource` - 26 edges
9. `SwingPathClass` - 24 edges
10. `WhoopMotionWristAnalysis` - 23 edges

## Surprising Connections (you probably didn't know these)
- `GolfHoleGeometryAttribution` --references--> `String`  [EXTRACTED]
  whoop-18birdies/apple/Shared/AutomaticHoleTransitionEngine.swift → whoop-18birdies/apple/Shared/WhoopMotionTransferModels.swift
- `GolfHoleGreenTargets` --references--> `GolfHoleGeometryAttribution`  [EXTRACTED]
  whoop-18birdies/apple/Shared/PhoneYardageBridge.swift → whoop-18birdies/apple/Shared/AutomaticHoleTransitionEngine.swift
- `GolfHoleTransitionGeometry` --references--> `String`  [EXTRACTED]
  whoop-18birdies/apple/Shared/AutomaticHoleTransitionEngine.swift → whoop-18birdies/apple/Shared/WhoopMotionTransferModels.swift
- `AutomaticHoleTransitionAction` --implements--> `String`  [EXTRACTED]
  whoop-18birdies/apple/Shared/AutomaticHoleTransitionEngine.swift → whoop-18birdies/apple/Shared/WhoopMotionTransferModels.swift
- `AutomaticHoleTransitionConfidence` --implements--> `String`  [EXTRACTED]
  whoop-18birdies/apple/Shared/AutomaticHoleTransitionEngine.swift → whoop-18birdies/apple/Shared/WhoopMotionTransferModels.swift

## Import Cycles
- None detected.

## Communities (34 total, 2 thin omitted)

### Community 0 - "Equatable"
Cohesion: 0.07
Nodes (66): CryptoKit, Equatable, Int64, K, KeyedDecodingContainer, UInt8, Bool, ClosedRange (+58 more)

### Community 1 - "CodingKeys"
Cohesion: 0.02
Nodes (94): CodingKeys, algorithm, angularAxisConcentration, apiVersion, backswingSeconds, baseUnixSeconds, batchID, bpm (+86 more)

### Community 2 - "String"
Cohesion: 0.06
Nodes (58): GolfImprover, ImproverDrill, .displayLine, ImproverFocus, pathInToOut, pathOnPlane, pathOutToIn, tempoRush (+50 more)

### Community 3 - "GolfRound"
Cohesion: 0.11
Nodes (30): Set, holes, GolfHoleCount, eighteen, .id, nine, GolfRound, .currentPar (+22 more)

### Community 4 - "CodingKeys"
Cohesion: 0.05
Nodes (38): CodingKey, CodingKeys, capturedAt, courseName, currentHole, currentPar, displacementFromPreviousYards, distanceToNextYards (+30 more)

### Community 5 - "Codable"
Cohesion: 0.12
Nodes (26): Codable, APIProvenance, Component, .id, DayResponse, Freshness, GolfReadiness, Physiology (+18 more)

### Community 6 - "Foundation"
Cohesion: 0.10
Nodes (17): Data, Foundation, HeartRateMeasurement, HeartRateMeasurementParser, Double, Int, ShotDistanceCalculator, SwingShotIntervalDisposition (+9 more)

### Community 7 - "ReconciledHybridSwing"
Cohesion: 0.09
Nodes (24): HybridSwingReconciler, HybridSwingReconciliationResult, .canonicalSwings, HybridSwingResolution, watchCanonicalAwaitingWhoop, watchCanonicalWithWhoopEnrichment, HybridSwingReviewItem, .candidateIDs (+16 more)

### Community 8 - "WatchRoundContext"
Cohesion: 0.12
Nodes (21): LocalizedError, Envelope, State, active, cleared, Any, Date, Int (+13 more)

### Community 9 - "Hashable"
Cohesion: 0.12
Nodes (21): RoundLifecycle, draft, finished, SwingHoleAssignment, SwingHoleAssignmentMethod, .displayName, manualCorrection, manualUnassignment (+13 more)

### Community 10 - "SensorModeCoordinator.swift"
Cohesion: 0.16
Nodes (14): AppleWatchSensorCapabilities, .canCaptureLive, .hasSwingSource, IPhoneLocationCapability, approximate, .isAvailable, precise, unavailable (+6 more)

### Community 11 - "Sendable"
Cohesion: 0.16
Nodes (17): AutomaticHoleTransitionAction, advance, remain, review, useRecordedBoundary, AutomaticHoleTransitionConfidence, confirmed, high (+9 more)

### Community 12 - "GolfHoleGreenTargets"
Cohesion: 0.24
Nodes (10): GolfCourseCandidate, GolfHoleGreenTargets, .isValid, GolfHoleYardageProviding, GreenYards, .hasAny, PhoneYardageBridge, Bool (+2 more)

### Community 13 - "MetricSource"
Cohesion: 0.12
Nodes (16): MetricSource, appleWatch, demo, derived, healthKit, iphoneGPS, manual, .symbol (+8 more)

### Community 14 - "AutomaticHoleTransitionEvidence"
Cohesion: 0.14
Nodes (14): AutomaticHoleTransitionEvidence, enteredHoleScore, explicitAppleWatchGPSLocation, explicitIPhoneGPSLocation, licensedCurrentGreenRegion, licensedNextTeeRegion, longInterSwingPause, meaningfulGPSDisplacement (+6 more)

### Community 15 - ".encode"
Cohesion: 0.26
Nodes (3): KeyedEncodingContainer, T, Encoder

### Community 16 - "AdaptiveSensorPlan"
Cohesion: 0.25
Nodes (8): AdaptiveSensorPlan, .fusedStatusDetail, .fusedStatusTitle, .isDualMaximize, .watchContributorDetail, .watchContributorStatus, .whoopContributorDetail, SensorModeCoordinator

### Community 17 - "LocationFix"
Cohesion: 0.28
Nodes (9): LocationFix, .isUsableForShotDistance, ShotRecord, Decoder, Double, UUID, SwingShotInterval, .algorithmVersion (+1 more)

### Community 18 - "GolfHoleTransitionGeometry"
Cohesion: 0.31
Nodes (8): AutomaticHoleTransitionContext, GolfHoleSpatialRegion, .isValid, GolfHoleTransitionGeometry, .isValid, Bool, Int, UUID

### Community 19 - "GolfSwingMetrics"
Cohesion: 0.31
Nodes (5): GolfSwingMetrics, Bool, Double, TimeInterval, SwingShotIntervalCalculator

### Community 20 - "SensorModeConstraint"
Cohesion: 0.18
Nodes (11): .whoopContributorStatus, SensorModeConstraint, approximateIPhoneLocation, iphoneLocationUnavailable, noSwingSensorAvailable, watchNotReachable, watchSynchronizedLocationUnavailable, whoopBandHapticUnavailable (+3 more)

### Community 22 - "DataProvenance"
Cohesion: 0.27
Nodes (8): .materializedObservation, DataProvenance, DataQuality, estimated, stale, unavailable, verified, Date

### Community 23 - "RoundRecorder"
Cohesion: 0.25
Nodes (8): RoundRecorder, .adaptiveSensorMode, appleWatch, .displayName, hybrid, .id, iphone, whoop5

### Community 24 - "WhoopWristQualityReason"
Cohesion: 0.25
Nodes (8): WhoopWristQualityReason, accelerometerSaturation, coverageGap, gyroscopeSaturation, insufficientWindow, noAddressPause, sampleRateMismatch, transitionUnresolved

### Community 25 - "SwingShotDistanceStatus"
Cohesion: 0.29
Nodes (7): SwingShotDistanceStatus, lowHorizontalAccuracy, measured, missingHorizontalAccuracy, missingLocation, nonIncreasingTimestamps, staleLocation

### Community 26 - "AdaptiveSensorMode"
Cohesion: 0.33
Nodes (6): CaseIterable, AdaptiveSensorMode, appleWatchOnly, hybrid, unavailable, whoopOnly

### Community 27 - "SensorModeOperationalState"
Cohesion: 0.33
Nodes (6): SensorModeOperationalState, delayedPostRoundCapture, distanceUnavailable, liveCaptureWithDelayedEnrichment, ready, unavailable

### Community 28 - "SwingCapturePlan"
Cohesion: 0.33
Nodes (6): SwingCapturePlan, appleWatchMotion, appleWatchMotionWithWhoopEnrichment, none, whoopAuthorizedLiveMotion, whoopHistoricalMotion

### Community 29 - "Configuration"
Cohesion: 0.80
Nodes (3): Configuration, Double, TimeInterval

### Community 30 - "ShotSpatialProvider"
Cohesion: 0.40
Nodes (4): ShotSpatialProvider, appleWatchGPS, iphoneGPS, unavailable

### Community 31 - "ShotConfirmationHapticRoute"
Cohesion: 0.40
Nodes (5): ShotConfirmationHapticRoute, appleWatchLocal, iphone, unavailable, whoopBandAuthorizedProvider

### Community 32 - "ShotConfirmationTiming"
Cohesion: 0.50
Nodes (4): ShotConfirmationTiming, delayedAtHistoricalImport, immediateAtLiveDetection, unavailable

## Knowledge Gaps
- **355 isolated node(s):** `.isValid`, `.isComplete`, `remain`, `review`, `advance` (+350 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `Equatable`, `CodingKeys`, `GolfRound`, `CodingKeys`, `Codable`, `Foundation`, `ReconciledHybridSwing`, `WatchRoundContext`, `Hashable`, `SensorModeCoordinator.swift`, `Sendable`, `GolfHoleGreenTargets`, `MetricSource`, `AutomaticHoleTransitionEvidence`, `AdaptiveSensorPlan`, `LocationFix`, `GolfHoleTransitionGeometry`, `SensorModeConstraint`, `DataProvenance`, `RoundRecorder`, `WhoopWristQualityReason`, `SwingShotDistanceStatus`, `AdaptiveSensorMode`, `SensorModeOperationalState`, `SwingCapturePlan`, `ShotSpatialProvider`, `ShotConfirmationHapticRoute`, `ShotConfirmationTiming`?**
  _High betweenness centrality (0.401) - this node is a cross-community bridge._
- **Why does `CodingKeys` connect `CodingKeys` to `Equatable`, `String`, `CodingKeys`, `.encode`, `AdaptiveSensorMode`?**
  _High betweenness centrality (0.238) - this node is a cross-community bridge._
- **Why does `GolfRound` connect `GolfRound` to `.encode`, `String`, `CodingKeys`, `Codable`, `Hashable`, `Sendable`, `LocationFix`, `GolfHoleTransitionGeometry`, `GolfSwingMetrics`, `RoundRecorder`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **What connects `.isValid`, `.isComplete`, `remain` to the rest of the system?**
  _355 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Equatable` be split into smaller, more focused modules?**
  _Cohesion score 0.0749084249084249 - nodes in this community are weakly interconnected._
- **Should `CodingKeys` be split into smaller, more focused modules?**
  _Cohesion score 0.02127659574468085 - nodes in this community are weakly interconnected._
- **Should `String` be split into smaller, more focused modules?**
  _Cohesion score 0.05518394648829431 - nodes in this community are weakly interconnected._
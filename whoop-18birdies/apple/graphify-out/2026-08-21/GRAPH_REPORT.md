# Graph Report - apple  (2026-08-21)

## Corpus Check
- 91 files · ~133,918 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2464 nodes · 6582 edges · 128 communities (121 shown, 7 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 551 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7bc4d7f6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- LocationRoundService
- CodingKeys
- IPhoneLocationCapability
- GolfCourseCandidate
- WatchSessionImporter
- GolfCard
- LiveRoundView
- IMUMotionManager
- String
- SettingsView
- Sendable
- TodayView
- HoleResult
- WhoopMotionImportState
- .init
- CodingKeys
- UUID
- .init
- DayResponse
- GolfRound
- WhoopMotionEnvelope
- View
- WhoopBLEManager
- Hashable
- WhoopMotionImportService
- String
- ContentView
- WhoopHeartRateProvider
- WhoopBridgeClient
- TestLocationManager
- CodingKeys
- .reconcile
- BridgeSyncState
- BridgeRoundOutbox
- BridgePairingClient
- AutomaticHoleTransitionDecision
- State
- .interval
- .decode
- WatchSessionReceiver
- UInt8
- String
- DataProvenance
- BridgeHTTPResult
- Data
- AdaptiveSensorPlan
- CodingKeys
- String
- .testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely
- Foundation
- .append
- State
- SwingStrokeScore
- SwingPathStrokeScore
- WhoopBridgeClient.swift
- .encode
- LocationFix
- DualWearableFusion
- BridgePairingClientError
- RoundFileStore
- WhoopCommand
- WhoopMotionImportError
- claudeTests
- golf-improver-engine
- LocalizedError
- GolfStrokePresentation
- AutomaticHoleTransitionEvidence
- WhoopBridgeError
- WhoopGeneration
- Whoop5DiscoveryScanner.swift
- .fallbackURL
- String
- WhoopPacketType
- Whoop5DiscoveredBand
- MotionFixture
- TASKS — D19 dual-wearable (manager-owned)
- State
- Whoop5DiscoveryScanner
- State
- BridgeRoundPayload
- String
- RoundRecorder
- WhoopWristQualityReason
- AppModel
- watch-round-face
- GolfHoleGreenTargets
- DataMode
- CourseLookupState
- WatchRoundContext
- WHOOP Golf — Orchestration STATUS (D19 dual-wearable)
- PermissionState
- SensorModeConstraint
- WatchLiveFace
- SensorCapabilitySnapshot
- CBUUID
- PostRoundCompactValue
- .encode
- .holeAssignment
- .finalizingIntervals
- trail-right-motion
- wearable-architecture — D19 dual maximize
- ReceivedWatchSession
- HANDOFFS — blockers & ownership (D19)
- Tab
- PostRoundWristRotationCard
- Agent: tailscale-ingest
- PRODUCT.md — WHOOP Golf dual-wearable bible
- xcode-ship
- watch-healthkit
- ReconciledHybridSwing
- WatchCoachingCue
- phone-yardage-bridge
- LESSONS — WHOOP Golf error-fixer
- SwingHoleAssignmentMethod
- Bool
- BridgePairingClient.swift
- String
- SwingShotDistanceStatus
- claudeUITestsLaunchTests
- SwingPathGuidanceTests
- WatchWristMount
- TrendsView
- CodingKeys
- CodingKeys
- CoreLocation
- WatchRoundContextTests
- WhoopFrame
- String

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 122 edges
2. `GolfRound` - 119 edges
3. `AppModel` - 72 edges
4. `GolfSwingMetrics` - 57 edges
5. `DataProvenance` - 50 edges
6. `LocationFix` - 49 edges
7. `WatchWristMount` - 48 edges
8. `WhoopMotionImportService` - 44 edges
9. `WhoopBLEManager` - 43 edges
10. `AdaptiveSensorPlan` - 40 edges

## Surprising Connections (you probably didn't know these)
- `.body` --references--> `ShotRecord`  [INFERRED]
  WhoopGolf/Views/RoundView.swift → Shared/GolfModels.swift
- `.recentRounds` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/Views/TrendsView.swift → Shared/GolfModels.swift
- `.body` --references--> `GolfSwingMetrics`  [INFERRED]
  WhoopGolf/Views/TrendsView.swift → Shared/GolfModels.swift
- `.sensorCapabilities` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/App/AppModel.swift → Shared/GolfModels.swift
- `.body` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/Views/RoundView.swift → Shared/GolfModels.swift

## Import Cycles
- None detected.

## Communities (128 total, 7 thin omitted)

### Community 0 - "LocationRoundService"
Cohesion: 0.14
Nodes (12): CLLocation, CLLocationManagerDelegate, Never, UInt64, LocationRoundService, CLAccuracyAuthorization, CLAuthorizationStatus, CLLocationManager (+4 more)

### Community 1 - "CodingKeys"
Cohesion: 0.02
Nodes (92): CodingKeys, algorithm, angularAxisConcentration, apiVersion, backswingSeconds, baseUnixSeconds, batchID, bpm (+84 more)

### Community 2 - "IPhoneLocationCapability"
Cohesion: 0.22
Nodes (6): IPhoneLocationCapability, approximate, .isAvailable, precise, unavailable, Bool

### Community 3 - "GolfCourseCandidate"
Cohesion: 0.08
Nodes (32): MKLocalSearch, AppleMapsGolfCourseSearchProvider, Configuration, GolfCourseCandidate, GolfCourseLocator, GolfCourseMatchConfidence, high, low (+24 more)

### Community 4 - "WatchSessionImporter"
Cohesion: 0.07
Nodes (39): PendingWatchSession, Date, FileManager, Int, String, URL, WatchImportRegistry, WatchImportRegistryEntry (+31 more)

### Community 5 - "GolfCard"
Cohesion: 0.08
Nodes (47): GolfCard, .body, Content, PostRoundDetailView, .body, .measurementBoundary, .presentation, .reviewedRound (+39 more)

### Community 6 - "LiveRoundView"
Cohesion: 0.05
Nodes (48): EighteenBirdiesCompanionCard, .body, CourseCandidateButton, .body, LiveRoundView, .body, .gpsDetail, .gpsValue (+40 more)

### Community 7 - "IMUMotionManager"
Cohesion: 0.09
Nodes (24): IMUMotionManager, .achievedRateHz, .bufferMax, Int, MainActor, TimeInterval, Void, AdaptiveThreshold (+16 more)

### Community 8 - "String"
Cohesion: 0.08
Nodes (33): DataQuality, estimated, stale, unavailable, verified, CorrectionNeededBadge, .body, PostRoundComparisonRow (+25 more)

### Community 9 - "SettingsView"
Cohesion: 0.07
Nodes (34): Binding, UIKit, .body, CapabilityRow, .body, PromiseRow, .body, SettingsConnectionRow (+26 more)

### Community 10 - "Sendable"
Cohesion: 0.12
Nodes (48): Codable, Equatable, Sendable, WhoopMotionComponent, WhoopMotionContractError, .errorDescription, invalidRequest, WhoopMotionHeartRate (+40 more)

### Community 11 - "TodayView"
Cohesion: 0.15
Nodes (13): AppModel.DataMode, .isError, Bool, Date, String, TodayView, .body, .dataBadge (+5 more)

### Community 12 - "HoleResult"
Cohesion: 0.12
Nodes (14): Encodable, .enteredStrokes, .grossScore, .runningScoreToPar, .totalPar, HoleResult, .id, fix() (+6 more)

### Community 13 - "WhoopMotionImportState"
Cohesion: 0.25
Nodes (8): WhoopMotionImportState, imported, importedWithNeedsReview, reviewed, stagedCrossSourceConflict, stagedLocationUnavailable, stagedNeedsReview, stagedRoundUnavailable

### Community 14 - ".init"
Cohesion: 0.20
Nodes (9): K, KeyedDecodingContainer, Bool, ClosedRange, Decoder, Double, Set, invalidEnvelope (+1 more)

### Community 15 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, capturedAt, courseName, currentHole, currentPar, displacementFromPreviousYards, distanceToNextYards, distanceUncertaintyYards (+19 more)

### Community 16 - "UUID"
Cohesion: 0.24
Nodes (10): ReadResult, RoundLocationJournal, Bool, Date, Double, JSONDecoder, JSONEncoder, URL (+2 more)

### Community 17 - ".init"
Cohesion: 0.22
Nodes (10): Error, OSStatus, String, UserDefaults, KeychainError, status, KeychainStore, PairedBridgeCredential (+2 more)

### Community 18 - "DayResponse"
Cohesion: 0.11
Nodes (21): HeartRateMeasurement, HeartRateMeasurementParser, Double, Int, APIProvenance, Component, .id, DayResponse (+13 more)

### Community 19 - "GolfRound"
Cohesion: 0.20
Nodes (14): GolfRound, .hasCompletePars, .hasCompleteStrokes, .isFinished, .isScoreComplete, .localDate, .parredHoleCount, .scoredHoleCount (+6 more)

### Community 20 - "WhoopMotionEnvelope"
Cohesion: 0.16
Nodes (17): gaps, Date, Int, TimeInterval, WhoopMotionCoverage, WhoopMotionEnvelope, WhoopMotionFrameCoverage, continuous (+9 more)

### Community 21 - "View"
Cohesion: 0.10
Nodes (24): SwiftUI, View, Color, ConnectionPill, .body, MetricTile, .body, SourceBadge (+16 more)

### Community 22 - "WhoopBLEManager"
Cohesion: 0.16
Nodes (9): CBCentralManager, CBCharacteristic, CBPeripheral, CBService, MainActor, TimeInterval, Timer, Void (+1 more)

### Community 23 - "Hashable"
Cohesion: 0.12
Nodes (32): Hashable, Identifiable, GolfHoleCount, eighteen, .id, nine, GolfSwingMetrics, HoleTransition (+24 more)

### Community 24 - "WhoopMotionImportService"
Cohesion: 0.17
Nodes (10): records, Date, FileManager, JSONDecoder, TimeInterval, URL, WhoopMotionImportRegistry, WhoopMotionImportRegistryEntry (+2 more)

### Community 25 - "String"
Cohesion: 0.21
Nodes (11): CodingKey, BridgePairingCodingKey, PairingClaimBody, PairingPlaintext, PairingStatusResponse, Bool, Date, Decoder (+3 more)

### Community 26 - "ContentView"
Cohesion: 0.13
Nodes (13): claudeApp, .body, Scene, ContentView, .body, NavigationViewWrapper, .body, Content (+5 more)

### Community 27 - "WhoopHeartRateProvider"
Cohesion: 0.14
Nodes (15): CBPeripheralDelegate, Any, Bool, CBCentralManager, CBCharacteristic, CBPeripheral, CBService, Date (+7 more)

### Community 28 - "WhoopBridgeClient"
Cohesion: 0.22
Nodes (6): BridgeConfiguration, JSONDecoder, URL, URLRequest, WhoopBridgeClient, WhoopMotionBridgeClientTests

### Community 29 - "TestLocationManager"
Cohesion: 0.14
Nodes (10): CLLocationManager, LocationRoundServiceAuthorizationTests, LocationTestContext, CLAccuracyAuthorization, CLAuthorizationStatus, LocationRoundService, Void, TestLocationManager (+2 more)

### Community 30 - "CodingKeys"
Cohesion: 0.09
Nodes (23): CodingKeys, altitude, autoThreshold, backswingSeconds, completedAt, downswingSeconds, heartRateBPM, horizontalAccuracy (+15 more)

### Community 31 - ".reconcile"
Cohesion: 0.12
Nodes (17): HybridSwingReconciler, HybridSwingReconciliationResult, .canonicalSwings, HybridSwingReviewItem, .candidateIDs, HybridSwingReviewReason, ambiguousCrossSourceMatch, duplicateIdentity (+9 more)

### Community 32 - "BridgeSyncState"
Cohesion: 0.22
Nodes (9): BridgeSyncState, failed, idle, queued, synced, syncing, unconfigured, Date (+1 more)

### Community 33 - "BridgeRoundOutbox"
Cohesion: 0.25
Nodes (9): BridgeRoundOutbox, BridgeRoundOutboxEntry, BridgeRoundUploading, Envelope, FlushResult, JSONEncoder, BridgeRoundOutboxTests, FailingRoundUploader (+1 more)

### Community 34 - "BridgePairingClient"
Cohesion: 0.23
Nodes (6): DateFormatter, BridgePairingClient, JSONDecoder, JSONEncoder, T, URLRequest

### Community 35 - "AutomaticHoleTransitionDecision"
Cohesion: 0.14
Nodes (19): AutomaticHoleTransitionContext, AutomaticHoleTransitionDecision, AutomaticHoleTransitionEngine, Configuration, GolfHoleGeometryAttribution, .isComplete, GolfHoleGeometryProviding, GolfHoleSpatialRegion (+11 more)

### Community 36 - "State"
Cohesion: 0.11
Nodes (16): HealthKit, ObservableObject, HealthAuthorizationError, .errorDescription, workoutSaveFailed, workoutWriteNotAuthorised, HealthAuthorizationService, State (+8 more)

### Community 37 - ".interval"
Cohesion: 0.15
Nodes (10): ShotDistanceCalculator, Double, Bool, Double, TimeInterval, SwingShotIntervalCalculator, SwingShotIntervalDisposition, withholdConfirmedHoleTransition (+2 more)

### Community 38 - ".decode"
Cohesion: 0.12
Nodes (17): Bool, Decoder, WatchSessionPayloadDecoder, WatchSessionPayloadError, duplicateSwingIndex, .errorDescription, invalidSampleRate, invalidSessionID (+9 more)

### Community 39 - "WatchSessionReceiver"
Cohesion: 0.13
Nodes (11): UserDefaults, Any, Error, WatchSessionReceiver, WatchSessionRecoveryFailure, .id, WatchSessionRecoverySnapshot, WCSession (+3 more)

### Community 40 - "UInt8"
Cohesion: 0.32
Nodes (7): Int16, UInt16, UInt32, UInt8, Bool, Int, WhoopFraming

### Community 41 - "String"
Cohesion: 0.21
Nodes (12): GolfImprover, ScoredPath, Double, TempoBand, rushing, slow, SwingPathClass, inToOut (+4 more)

### Community 42 - "DataProvenance"
Cohesion: 0.11
Nodes (15): DataProvenance, MetricSource, appleWatch, demo, derived, healthKit, iphoneGPS, manual (+7 more)

### Community 43 - "BridgeHTTPResult"
Cohesion: 0.22
Nodes (7): BridgeHTTPResult, RecordingBridgeTransport, Int, URLRequest, MotionBridgeTransport, Int, URLRequest

### Community 44 - "Data"
Cohesion: 0.26
Nodes (7): Curve25519, SymmetricKey, BridgePairingOffer, BridgePairingSession, Data, PairingSealedResponse, Encoder

### Community 45 - "AdaptiveSensorPlan"
Cohesion: 0.07
Nodes (32): AdaptiveSensorPlan, .fusedStatusDetail, .fusedStatusTitle, .isDualMaximize, .watchContributorDetail, .watchContributorStatus, .whoopContributorDetail, SensorModeOperationalState (+24 more)

### Community 46 - "CodingKeys"
Cohesion: 0.12
Nodes (16): CodingKeys, baseURL, bearerToken, ciphertext, expiresAt, kind, macPublicKey, nonce (+8 more)

### Community 47 - "String"
Cohesion: 0.18
Nodes (8): Bool, ClosedRange, Double, String, WhoopMotionPullResult, available, notModified, pending

### Community 48 - ".testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely"
Cohesion: 0.18
Nodes (7): BridgePairingClientTests, PairingCredentialRecorder, PairingRecordingTransport, Bool, Int, String, URLRequest

### Community 49 - "Foundation"
Cohesion: 0.20
Nodes (5): CryptoKit, Foundation, Security, WhoopGolf, XCTest

### Community 50 - ".append"
Cohesion: 0.35
Nodes (4): RoundLocationJournalTests, Date, Double, URL

### Community 51 - "State"
Cohesion: 0.14
Nodes (12): State, acquiring, denied, failed, idle, needsPermission, ready, reducedAccuracy (+4 more)

### Community 52 - "SwingStrokeScore"
Cohesion: 0.10
Nodes (22): ImproverDrill, .displayLine, ImproverFocus, pathInToOut, pathOnPlane, pathOutToIn, tempoRush, tempoSlow (+14 more)

### Community 53 - "SwingPathStrokeScore"
Cohesion: 0.33
Nodes (7): Double, Int, SwingPathGuidance, SwingPathScorer, watchLive, whoopRefined, SwingPathStrokeScore

### Community 54 - "WhoopBridgeClient.swift"
Cohesion: 0.20
Nodes (8): BridgeHTTPTransport, BridgeRoundOutboxError, corrupt, .errorDescription, flushAlreadyRunning, unavailable, URLSession, URLSessionBridgeTransport

### Community 55 - ".encode"
Cohesion: 0.26
Nodes (3): KeyedEncodingContainer, Encoder, T

### Community 56 - "LocationFix"
Cohesion: 0.17
Nodes (11): LocationFix, .isUsableForShotDistance, Configuration, Record, RoundLocationCorrelation, Int, TimeInterval, Request (+3 more)

### Community 57 - "DualWearableFusion"
Cohesion: 0.19
Nodes (15): ContributionBoard, ContributionContext, .heartRateContext, ContributionLine, DualWearableFusion, HeartRateContext, HeartRateOwner, appleWatch (+7 more)

### Community 58 - "BridgePairingClientError"
Cohesion: 0.14
Nodes (14): StaticString, UInt, BridgePairingClientError, authenticationFailed, conflict, .errorDescription, expired, invalidOffer (+6 more)

### Community 59 - "RoundFileStore"
Cohesion: 0.21
Nodes (9): RoundFileStore, Snapshot, Int, JSONDecoder, JSONEncoder, URL, RoundFileStoreTests, URL (+1 more)

### Community 60 - "WhoopCommand"
Cohesion: 0.14
Nodes (13): WhoopCommand, exitHighFreqSync, getAdvertisingName, getBatteryLevel, getClock, getDataRange, getHelloHarvard, sendR10R11Realtime (+5 more)

### Community 61 - "WhoopMotionImportError"
Cohesion: 0.14
Nodes (14): WhoopMotionImportError, .errorDescription, identityCollision, inboxCorrupt, inboxMissing, locationUnavailable, payloadTooLarge, registryCorrupt (+6 more)

### Community 62 - "claudeTests"
Cohesion: 0.15
Nodes (3): claudeTests, claudeUITests, measure

### Community 63 - "golf-improver-engine"
Cohesion: 0.25
Nodes (7): API for UI agents (Watch + phone), Done, Evidence, Files touched, Gaps, golf-improver-engine, graphify

### Community 64 - "LocalizedError"
Cohesion: 0.12
Nodes (17): LocalizedError, WatchSessionReceiveError, .errorDescription, fileTooLarge, identityCollision, metadataMismatch, StoreError, .errorDescription (+9 more)

### Community 65 - "GolfStrokePresentation"
Cohesion: 0.20
Nodes (15): MapKit, GolfStrokeBoardView, .body, .hasMapPoints, MappedStroke, StrokeBoardRowView, .body, StrokeMapView (+7 more)

### Community 66 - "AutomaticHoleTransitionEvidence"
Cohesion: 0.08
Nodes (26): AutomaticHoleTransitionAction, advance, remain, review, useRecordedBoundary, AutomaticHoleTransitionConfidence, confirmed, high (+18 more)

### Community 67 - "WhoopBridgeError"
Cohesion: 0.12
Nodes (15): BridgeRoundUploadResponse, Int, WhoopBridgeError, .errorDescription, http, invalidConfiguration, invalidResponse, invalidRoundPayload (+7 more)

### Community 68 - "WhoopGeneration"
Cohesion: 0.38
Nodes (4): WhoopCommands, WhoopGeneration, whoop4, whoop5

### Community 69 - "Whoop5DiscoveryScanner.swift"
Cohesion: 0.33
Nodes (3): CoreBluetooth, String, .nilIfEmpty

### Community 70 - ".fallbackURL"
Cohesion: 0.20
Nodes (4): EighteenBirdiesCompanionLink, Bool, URL, EighteenBirdiesCompanionLinkTests

### Community 71 - "String"
Cohesion: 0.33
Nodes (6): Any, Error, Int, NSNumber, String, WhoopLiveIMUPolicy

### Community 72 - "WhoopPacketType"
Cohesion: 0.20
Nodes (8): WhoopPacketType, command, commandResponse, historicalIMUStream, realtimeData, realtimeIMUStream, realtimeRawData, WhoopReassembler

### Community 73 - "Whoop5DiscoveredBand"
Cohesion: 0.29
Nodes (8): Any, CBPeripheral, Date, Int, NSNumber, String, Whoop5DiscoveredBand, .signalLabel

### Community 74 - "MotionFixture"
Cohesion: 0.18
Nodes (10): events, MotionFixture, .decoder, .encoder, Any, JSONDecoder, JSONEncoder, String (+2 more)

### Community 75 - "TASKS — D19 dual-wearable (manager-owned)"
Cohesion: 0.14
Nodes (13): 10. tailscale-ingest, 11. error-fixer-learner, 1. watch-round-face, 2. trail-right-motion, 3. watch-connectivity, 4. phone-yardage-bridge, 5. watch-healthkit, 6. xcode-ship (+5 more)

### Community 76 - "State"
Cohesion: 0.22
Nodes (9): State, bluetoothOff, found, idle, noBandFound, scanning, unauthorised, unavailable (+1 more)

### Community 77 - "Whoop5DiscoveryScanner"
Cohesion: 0.31
Nodes (6): CBCentralManagerDelegate, NSObject, CBCentralManager, TimeInterval, Timer, Whoop5DiscoveryScanner

### Community 78 - "State"
Cohesion: 0.22
Nodes (9): State, bluetoothOff, connecting, failed, idle, scanning, stale, streaming (+1 more)

### Community 79 - "BridgeRoundPayload"
Cohesion: 0.22
Nodes (6): BridgeRoundPayload, .outboxID, Date, Decoder, BridgeRoundPayloadTests, RecordingRoundUploader

### Community 80 - "String"
Cohesion: 0.06
Nodes (48): AnyKey, CodingKeys, batchID, decision, eventID, payloadSHA256, recordedAt, recordedBy (+40 more)

### Community 81 - "RoundRecorder"
Cohesion: 0.14
Nodes (14): CaseIterable, RoundRecorder, .adaptiveSensorMode, appleWatch, .displayName, hybrid, .id, iphone (+6 more)

### Community 82 - "WhoopWristQualityReason"
Cohesion: 0.25
Nodes (8): WhoopWristQualityReason, accelerometerSaturation, coverageGap, gyroscopeSaturation, insufficientWindow, noAddressPause, sampleRateMismatch, transitionUnresolved

### Community 83 - "AppModel"
Cohesion: 0.14
Nodes (11): AnyCancellable, App, AppModel, .adaptiveSensorPlan, .recommendedRoundRecorder, Set, Scene, WhoopGolfApp (+3 more)

### Community 84 - "watch-round-face"
Cohesion: 0.25
Nodes (7): Done (D19), Evidence, Files touched, Gaps, HANDOFFS, Verdict, watch-round-face

### Community 85 - "GolfHoleGreenTargets"
Cohesion: 0.27
Nodes (10): GolfHoleGreenTargets, .isValid, GolfHoleYardageProviding, GreenYards, .hasAny, PhoneYardageBridge, Bool, Double (+2 more)

### Community 86 - "DataMode"
Cohesion: 0.33
Nodes (6): DataMode, demo, error, live, loading, unconfigured

### Community 87 - "CourseLookupState"
Cohesion: 0.22
Nodes (9): CourseLookupState, ambiguous, confirmed, failed, idle, locating, noneNearby, searching (+1 more)

### Community 88 - "WatchRoundContext"
Cohesion: 0.16
Nodes (17): Envelope, State, active, cleared, Any, Date, Int, String (+9 more)

### Community 89 - "WHOOP Golf — Orchestration STATUS (D19 dual-wearable)"
Cohesion: 0.22
Nodes (8): Agent board (re-assigned under D19), Cycle log, Done criteria (software-complete), Hard constraints, Mandate (one line), Ownership (see TASKS.md), Run recipe (draft — finalize at COMPLETE), WHOOP Golf — Orchestration STATUS (D19 dual-wearable)

### Community 90 - "PermissionState"
Cohesion: 0.22
Nodes (9): PermissionState, always, denied, notRequested, requestingAlways, requestingWhenInUse, restricted, whenInUse (+1 more)

### Community 91 - "SensorModeConstraint"
Cohesion: 0.16
Nodes (12): .whoopContributorStatus, SensorModeConstraint, approximateIPhoneLocation, iphoneLocationUnavailable, noSwingSensorAvailable, watchNotReachable, watchSynchronizedLocationUnavailable, whoopBandHapticUnavailable (+4 more)

### Community 92 - "WatchLiveFace"
Cohesion: 0.23
Nodes (7): Any, Bool, Int, String, WatchLiveFace, .hasHoleMap, WatchLiveFaceCodec

### Community 93 - "SensorCapabilitySnapshot"
Cohesion: 0.23
Nodes (10): AppleWatchSensorCapabilities, .canCaptureLive, .hasSwingSource, SensorCapabilitySnapshot, WhoopSensorCapabilities, .canCaptureLive, .canReconstructPostRound, .hasSwingSource (+2 more)

### Community 94 - "CBUUID"
Cohesion: 0.70
Nodes (4): CBUUID, Gen4, Gen5, WhoopUUIDs

### Community 95 - "PostRoundCompactValue"
Cohesion: 0.67
Nodes (3): PostRoundCompactValue, .body, .body

### Community 98 - ".finalizingIntervals"
Cohesion: 0.33
Nodes (3): PhoneYardageBridgeTests, Date, Double

### Community 99 - "trail-right-motion"
Cohesion: 0.25
Nodes (7): Done, Evidence, Feed (stroke-score-shot-chain), Files touched, Gaps, Purpose, trail-right-motion

### Community 100 - "wearable-architecture — D19 dual maximize"
Cohesion: 0.25
Nodes (7): Done, Evidence, Files touched, Gaps, Purpose, Secrets, wearable-architecture — D19 dual maximize

### Community 101 - "ReceivedWatchSession"
Cohesion: 0.18
Nodes (18): Decodable, WatchConnectivity, Notification.Name, ReceivedWatchSession, Date, Double, FileManager, Int (+10 more)

### Community 102 - "HANDOFFS — blockers & ownership (D19)"
Cohesion: 0.33
Nodes (5): Active blockers, Agent-noted (non-blocking), Cleared, HANDOFFS — blockers & ownership (D19), Ownership claims (D19)

### Community 103 - "Tab"
Cohesion: 0.40
Nodes (5): Tab, round, settings, today, trends

### Community 104 - "PostRoundWristRotationCard"
Cohesion: 0.50
Nodes (4): PostRoundWristRotationCard, .accessibilitySummary, .body, .points

### Community 105 - "Agent: tailscale-ingest"
Cohesion: 0.40
Nodes (4): Agent purpose, Agent: tailscale-ingest, Phone → ingest checklist, Probe results (localhost only)

### Community 106 - "PRODUCT.md — WHOOP Golf dual-wearable bible"
Cohesion: 0.20
Nodes (9): 1. Swing path relative to body, 2. Shot yardage, 3. UI uses every capability on him, Agent roster (purposes under D19), Core product loops (must ship), PRODUCT.md — WHOOP Golf dual-wearable bible, Product north star, Sensor truth (non-negotiable) (+1 more)

### Community 107 - "xcode-ship"
Cohesion: 0.22
Nodes (8): Commands run, Critical compile errors (file:line, no team IDs), Exact results, First WhoopGolf pass (also noted), Handoff, Likely fix direction (for error-fixer-learner), Root cause (shared), xcode-ship

### Community 108 - "watch-healthkit"
Cohesion: 0.25
Nodes (7): Done, Evidence, Files touched, Gaps / blockers (not owned), Purpose, watch-healthkit, Wiring evidence (read-only; other agents own these)

### Community 109 - "ReconciledHybridSwing"
Cohesion: 0.20
Nodes (10): HybridSwingResolution, watchCanonicalAwaitingWhoop, watchCanonicalWithWhoopEnrichment, ReconciledHybridSwing, .attachedWristAnalysis, .canonicalCapturedAt, .canonicalID, .materializedObservation (+2 more)

### Community 110 - "WatchCoachingCue"
Cohesion: 0.40
Nodes (6): Any, Double, Int, String, WatchCoachingCue, WatchCoachingCueCodec

### Community 111 - "phone-yardage-bridge"
Cohesion: 0.25
Nodes (7): Done, Evidence, Files touched, Gaps / next, Mandate (locked), phone-yardage-bridge, Purpose

### Community 112 - "LESSONS — WHOOP Golf error-fixer"
Cohesion: 0.29
Nodes (6): L1 — A phone↔Watch contract type must live in `Shared/`, not in `WatchSupport/`, L2 — `Shared/` does not mean "compiles on watchOS", L3 — Building inside iCloud-synced `~/Documents` breaks device code signing, L4 — Two agents editing `project.pbxproj` clobber each other silently, L5 — Default arguments hide a stale call site, LESSONS — WHOOP Golf error-fixer

### Community 113 - "SwingHoleAssignmentMethod"
Cohesion: 0.33
Nodes (6): SwingHoleAssignmentMethod, .displayName, manualCorrection, manualUnassignment, roundTimeline, unavailable

### Community 114 - "Bool"
Cohesion: 0.38
Nodes (4): holes, .currentPar, .currentStrokes, Bool

### Community 115 - "BridgePairingClient.swift"
Cohesion: 0.25
Nodes (5): BridgePairingCredentialStoring, BridgePairingStrictDecoding, KeychainBridgePairingCredentialStore, URLSession, URLSessionBridgePairingTransport

### Community 116 - "String"
Cohesion: 0.14
Nodes (19): Int64, String, UInt8, WhoopMotionClassification, WhoopMotionCodingKey, WhoopMotionDecision, accepted, needsReview (+11 more)

### Community 117 - "SwingShotDistanceStatus"
Cohesion: 0.29
Nodes (7): SwingShotDistanceStatus, lowHorizontalAccuracy, measured, missingHorizontalAccuracy, missingLocation, nonIncreasingTimestamps, staleLocation

### Community 118 - "claudeUITestsLaunchTests"
Cohesion: 0.33
Nodes (3): claudeUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool

### Community 120 - "WatchWristMount"
Cohesion: 0.13
Nodes (17): Double, WatchWristMount, .coachingName, .detail, .displayName, .id, leadLeft, .pathSign (+9 more)

### Community 121 - "TrendsView"
Cohesion: 0.18
Nodes (11): GolfBackground, .body, .body, TrendsView, .body, .bridgeProgressLabel, .finishedRounds, .header (+3 more)

### Community 122 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, course, endedAt, grossScore, holes, localDate, par, startedAt

### Community 123 - "CodingKeys"
Cohesion: 0.22
Nodes (9): CodingKeys, correctedYawDegrees, explanation, pathClass, schemaVersion, score, scorer, tempoRatio (+1 more)

## Knowledge Gaps
- **787 isolated node(s):** `.isValid`, `.isComplete`, `remain`, `review`, `advance` (+782 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `GolfCourseCandidate`, `WatchSessionImporter`, `GolfCard`, `LiveRoundView`, `IMUMotionManager`, `String`, `SettingsView`, `TodayView`, `.init`, `DayResponse`, `GolfRound`, `View`, `WhoopBLEManager`, `WhoopMotionImportService`, `WhoopHeartRateProvider`, `BridgeSyncState`, `BridgeRoundOutbox`, `State`, `WatchSessionReceiver`, `AdaptiveSensorPlan`, `RoundFileStore`, `Whoop5DiscoveryScanner`, `String`, `RoundRecorder`, `GolfHoleGreenTargets`, `DataMode`, `CourseLookupState`, `SensorCapabilitySnapshot`, `ReceivedWatchSession`, `Tab`, `WatchWristMount`, `TrendsView`, `CoreLocation`?**
  _High betweenness centrality (0.122) - this node is a cross-community bridge._
- **Why does `GolfRound` connect `GolfRound` to `WatchSessionImporter`, `GolfCard`, `LiveRoundView`, `String`, `Sendable`, `HoleResult`, `CodingKeys`, `UUID`, `View`, `Hashable`, `WhoopMotionImportService`, `AutomaticHoleTransitionDecision`, `State`, `String`, `DataProvenance`, `RoundFileStore`, `BridgeRoundPayload`, `RoundRecorder`, `AppModel`, `SensorCapabilitySnapshot`, `.encode`, `.holeAssignment`, `Bool`, `WatchWristMount`, `TrendsView`?**
  _High betweenness centrality (0.082) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `GolfCourseCandidate`, `WatchSessionImporter`, `IMUMotionManager`, `SettingsView`, `Sendable`, `DayResponse`, `Hashable`, `ContentView`, `TestLocationManager`, `AutomaticHoleTransitionDecision`, `State`, `.interval`, `DataProvenance`, `AdaptiveSensorPlan`, `SwingStrokeScore`, `SwingPathStrokeScore`, `WhoopBridgeClient.swift`, `LocationFix`, `DualWearableFusion`, `WhoopCommand`, `Whoop5DiscoveryScanner.swift`, `.fallbackURL`, `WhoopPacketType`, `String`, `GolfHoleGreenTargets`, `WatchRoundContext`, `WatchLiveFace`, `ReceivedWatchSession`, `WatchCoachingCue`, `BridgePairingClient.swift`, `WatchWristMount`, `CoreLocation`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **Are the 28 inferred relationships involving `GolfRound` (e.g. with `.sensorCapabilities` and `.importBatch()`) actually correct?**
  _`GolfRound` has 28 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.isValid`, `.isComplete`, `remain` to the rest of the system?**
  _787 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `LocationRoundService` be split into smaller, more focused modules?**
  _Cohesion score 0.14112903225806453 - nodes in this community are weakly interconnected._
- **Should `CodingKeys` be split into smaller, more focused modules?**
  _Cohesion score 0.021739130434782608 - nodes in this community are weakly interconnected._
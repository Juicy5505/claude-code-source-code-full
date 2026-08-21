# Graph Report - apple  (2026-08-21)

## Corpus Check
- 95 files · ~137,925 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2565 nodes · 6851 edges · 122 communities (119 shown, 3 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 559 edges (avg confidence: 0.8)
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
- TrendsView.swift
- LiveRoundView
- IMUMotionManager
- String
- SettingsView
- Sendable
- TodayView
- GolfRound
- Identifiable
- String
- CodingKeys
- LocationFix
- .init
- DayResponse
- RoundFileStore
- WhoopMotionEnvelope
- View
- WhoopBLEManager
- SwingShotInterval
- WhoopMotionImportService
- BridgePairingClient.swift
- ContentView
- WhoopHeartRateProvider
- BridgeConfiguration
- TestLocationManager
- CodingKeys
- GolfSwingMetrics
- BridgeSyncState
- BridgeRoundOutbox
- BridgePairingClient
- AutomaticHoleTransitionDecision
- GolfHoleTransitionGeometry
- .interval
- WatchSessionReceiver.swift
- WatchSessionReceiver
- UInt8
- String
- MetricSource
- RecordingBridgeTransport
- Data
- AdaptiveSensorPlan
- CodingKeys
- WhoopBridgeClient
- BridgeHTTPResult
- Foundation
- .append
- State
- PendingWhoopMotionReviewBatch
- WatchWristMount
- BridgeRoundOutboxError
- .encode
- DataProvenance
- DualWearableFusion
- BridgePairingClientError
- .testDraftIsResumableButExcludedFromHistoryUntilFinished
- WhoopCommand
- WatchStrokeChainSummary
- claudeTests
- golf-improver-engine
- WatchSessionReceiveError
- GolfStrokePresentation
- AutomaticHoleTransitionEvidence
- WhoopBridgeError
- WhoopGeneration
- CoreModelTests.swift
- XCTestCase
- String
- WhoopPacketType
- Whoop5DiscoveryScanner
- UUID
- TASKS — D19 dual-wearable (manager-owned)
- State
- watch-connectivity — agent status
- CoreModelTests
- BridgeRoundPayload
- String
- RoundRecorder
- WhoopWristQualityReason
- AppModel
- watch-round-face
- GolfHoleGreenTargets
- .decode
- CourseLookupState
- WatchRoundContext
- WHOOP Golf — Orchestration STATUS (D19 dual-wearable)
- PermissionState
- SensorModeConstraint
- WatchLiveFace
- SensorCapabilitySnapshot
- CBUUID
- CorrectionNeededBadge
- integrator (Claude Code) — build + cross-target integration
- MotionBridgeTransport
- dual-wearable-fusion — D19
- trail-right-motion
- wearable-architecture — D19 dual maximize
- WatchSessionRecoveryFailure
- HANDOFFS — blockers & ownership (D19)
- HybridSwingReviewReason
- WhoopWristTracePhase
- Agent: tailscale-ingest
- PRODUCT.md — WHOOP Golf dual-wearable bible
- xcode-ship
- watch-healthkit
- ShotYardageKind
- WatchCoachingCue
- phone-yardage-bridge
- LESSONS — WHOOP Golf error-fixer
- SwingHoleAssignmentMethod
- WhoopMotionPullResult
- WhoopMotionEvent
- SwingPathGuidanceTests
- TrendsView
- CodingKeys
- CodingKeys
- WhoopFrame
- String

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 122 edges
2. `GolfRound` - 121 edges
3. `AppModel` - 72 edges
4. `GolfSwingMetrics` - 63 edges
5. `WatchWristMount` - 57 edges
6. `DataProvenance` - 51 edges
7. `LocationFix` - 49 edges
8. `WhoopMotionImportService` - 44 edges
9. `WhoopBLEManager` - 43 edges
10. `AdaptiveSensorPlan` - 40 edges

## Surprising Connections (you probably didn't know these)
- `.recentRounds` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/Views/TrendsView.swift → Shared/GolfModels.swift
- `.body` --references--> `GolfSwingMetrics`  [INFERRED]
  WhoopGolf/Views/TrendsView.swift → Shared/GolfModels.swift
- `.body` --references--> `ShotRecord`  [INFERRED]
  WhoopGolf/Views/RoundView.swift → Shared/GolfModels.swift
- `.sensorCapabilities` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/App/AppModel.swift → Shared/GolfModels.swift
- `.body` --references--> `GolfRound`  [INFERRED]
  WhoopGolf/Views/RoundView.swift → Shared/GolfModels.swift

## Import Cycles
- None detected.

## Communities (122 total, 3 thin omitted)

### Community 0 - "LocationRoundService"
Cohesion: 0.22
Nodes (9): CLLocationManagerDelegate, Never, UInt64, LocationRoundService, CLAccuracyAuthorization, CLAuthorizationStatus, CLLocationManager, UserDefaults (+1 more)

### Community 1 - "CodingKeys"
Cohesion: 0.02
Nodes (91): CodingKey, CodingKeys, algorithm, angularAxisConcentration, apiVersion, backswingSeconds, baseUnixSeconds, batchID (+83 more)

### Community 2 - "IPhoneLocationCapability"
Cohesion: 0.20
Nodes (6): IPhoneLocationCapability, approximate, .isAvailable, precise, unavailable, Bool

### Community 3 - "GolfCourseCandidate"
Cohesion: 0.08
Nodes (32): MKLocalSearch, AppleMapsGolfCourseSearchProvider, Configuration, GolfCourseCandidate, GolfCourseLocator, GolfCourseMatchConfidence, high, low (+24 more)

### Community 4 - "WatchSessionImporter"
Cohesion: 0.07
Nodes (41): ReceivedWatchSession, WatchSessionMode, range, round, PendingWatchSession, Date, FileManager, Int (+33 more)

### Community 5 - "TrendsView.swift"
Cohesion: 0.08
Nodes (44): SwingHoleAssignment, PostRoundDetailView, .body, .measurementBoundary, .presentation, .roundSummary, .scorecard, .sourceStatus (+36 more)

### Community 6 - "LiveRoundView"
Cohesion: 0.05
Nodes (42): CourseCandidateButton, .body, LiveRoundView, .gpsDetail, .gpsValue, .heartRateDetail, .recordingSourceLabel, .scorecardSummary (+34 more)

### Community 7 - "IMUMotionManager"
Cohesion: 0.09
Nodes (24): IMUMotionManager, .achievedRateHz, .bufferMax, Int, MainActor, TimeInterval, Void, AdaptiveThreshold (+16 more)

### Community 8 - "String"
Cohesion: 0.09
Nodes (27): PostRoundComparisonRow, .body, .hero, PostRoundFirstLateAnalysis, PostRoundFormat, PostRoundHistoryRow, .body, PostRoundMetricCapsule (+19 more)

### Community 9 - "SettingsView"
Cohesion: 0.09
Nodes (21): Binding, .body, SettingsView, .adaptiveModeBadge, .adaptiveModeColor, .body, .bridgeSyncBadge, .bridgeSyncColor (+13 more)

### Community 10 - "Sendable"
Cohesion: 0.11
Nodes (53): Codable, Equatable, Hashable, Sendable, RoundLifecycle, draft, finished, HybridSwingResolution (+45 more)

### Community 11 - "TodayView"
Cohesion: 0.16
Nodes (13): AppModel.DataMode, .isError, Bool, Date, String, TodayView, .body, .dataBadge (+5 more)

### Community 12 - "GolfRound"
Cohesion: 0.10
Nodes (21): Set, holes, GolfRound, .currentPar, .currentStrokes, .enteredStrokes, .grossScore, .hasCompletePars (+13 more)

### Community 13 - "Identifiable"
Cohesion: 0.10
Nodes (27): Identifiable, PathHint, RoundStrokeJournal, .id, .latestSummaryLine, .meanPathScore, .measuredShotYards, .strokeCount (+19 more)

### Community 14 - "String"
Cohesion: 0.19
Nodes (12): K, KeyedDecodingContainer, Bool, ClosedRange, Decoder, Double, Int, Set (+4 more)

### Community 15 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, capturedAt, courseName, currentHole, currentPar, displacementFromPreviousYards, distanceToNextYards, distanceUncertaintyYards (+19 more)

### Community 16 - "LocationFix"
Cohesion: 0.18
Nodes (12): LocationFix, .isUsableForShotDistance, Configuration, ReadResult, Record, RoundLocationJournal, Bool, Int (+4 more)

### Community 17 - ".init"
Cohesion: 0.19
Nodes (10): Error, OSStatus, UserDefaults, KeychainBridgePairingCredentialStore, KeychainError, status, KeychainStore, PairedBridgeCredential (+2 more)

### Community 18 - "DayResponse"
Cohesion: 0.21
Nodes (15): APIProvenance, Component, .id, DayResponse, Freshness, GolfReadiness, Physiology, ReadinessSnapshot (+7 more)

### Community 19 - "RoundFileStore"
Cohesion: 0.12
Nodes (21): classification, events, features, orientation, RoundFileStore, JSONDecoder, JSONEncoder, URL (+13 more)

### Community 20 - "WhoopMotionEnvelope"
Cohesion: 0.15
Nodes (15): Date, TimeInterval, WhoopMotionCoverage, WhoopMotionEnvelope, WhoopMotionFrameCoverage, continuous, gapped, unknown (+7 more)

### Community 21 - "View"
Cohesion: 0.10
Nodes (31): SwiftUI, View, EighteenBirdiesCompanionCard, .body, Color, ConnectionPill, .body, GolfCard (+23 more)

### Community 22 - "WhoopBLEManager"
Cohesion: 0.16
Nodes (8): CBCentralManager, CBCharacteristic, CBService, MainActor, TimeInterval, Timer, Void, WhoopBLEManager

### Community 23 - "SwingShotInterval"
Cohesion: 0.08
Nodes (33): GolfHoleCount, eighteen, .id, nine, HoleTransition, .id, ShotRecord, Date (+25 more)

### Community 24 - "WhoopMotionImportService"
Cohesion: 0.11
Nodes (20): records, LocationRoundService, Bool, Date, FileManager, JSONDecoder, TimeInterval, URL (+12 more)

### Community 25 - "BridgePairingClient.swift"
Cohesion: 0.19
Nodes (12): Encodable, BridgePairingCodingKey, BridgePairingStrictDecoding, PairingClaimBody, PairingPlaintext, PairingProofBody, PairingSealedResponse, PairingStatusResponse (+4 more)

### Community 26 - "ContentView"
Cohesion: 0.13
Nodes (13): claudeApp, .body, Scene, ContentView, .body, NavigationViewWrapper, .body, Content (+5 more)

### Community 27 - "WhoopHeartRateProvider"
Cohesion: 0.08
Nodes (26): CBCentralManagerDelegate, CBPeripheralDelegate, NSObject, State, bluetoothOff, connecting, failed, idle (+18 more)

### Community 28 - "BridgeConfiguration"
Cohesion: 0.32
Nodes (4): BridgeConfiguration, JSONEncoder, URL, URLRequest

### Community 29 - "TestLocationManager"
Cohesion: 0.17
Nodes (7): CLLocationManager, LocationRoundServiceAuthorizationTests, CLAccuracyAuthorization, CLAuthorizationStatus, TestLocationManager, .accuracyAuthorization, .authorizationStatus

### Community 30 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, altitude, autoThreshold, backswingSeconds, completedAt, downswingSeconds, heartRateBPM, horizontalAccuracy (+17 more)

### Community 31 - "GolfSwingMetrics"
Cohesion: 0.13
Nodes (19): GolfSwingMetrics, .resolvedPathClass, HybridSwingReconciler, HybridSwingReconciliationResult, .canonicalSwings, HybridSwingReviewItem, .candidateIDs, ReconciledHybridSwing (+11 more)

### Community 32 - "BridgeSyncState"
Cohesion: 0.12
Nodes (16): BridgeSyncState, failed, idle, queued, synced, syncing, unconfigured, DataMode (+8 more)

### Community 33 - "BridgeRoundOutbox"
Cohesion: 0.27
Nodes (8): BridgeRoundOutbox, BridgeRoundOutboxEntry, BridgeRoundUploading, Envelope, FlushResult, BridgeRoundOutboxTests, FailingRoundUploader, URL

### Community 34 - "BridgePairingClient"
Cohesion: 0.22
Nodes (6): DateFormatter, BridgePairingClient, Bool, JSONDecoder, JSONEncoder, T

### Community 35 - "AutomaticHoleTransitionDecision"
Cohesion: 0.25
Nodes (6): AutomaticHoleTransitionContext, AutomaticHoleTransitionDecision, Date, AutomaticHoleTransitionEngineTests, Date, Double

### Community 36 - "GolfHoleTransitionGeometry"
Cohesion: 0.11
Nodes (25): AutomaticHoleTransitionAction, advance, remain, review, useRecordedBoundary, AutomaticHoleTransitionConfidence, confirmed, high (+17 more)

### Community 37 - ".interval"
Cohesion: 0.15
Nodes (10): ShotDistanceCalculator, Double, Bool, Double, TimeInterval, SwingShotIntervalCalculator, SwingShotIntervalDisposition, withholdConfirmedHoleTransition (+2 more)

### Community 38 - "WatchSessionReceiver.swift"
Cohesion: 0.14
Nodes (21): Decodable, WatchConnectivity, Notification.Name, Bool, Date, Double, Int, WatchSessionLocationPayload (+13 more)

### Community 39 - "WatchSessionReceiver"
Cohesion: 0.14
Nodes (7): UserDefaults, Error, WatchSessionReceiver, WCSession, WCSessionActivationState, WCSessionDelegate, WCSessionFile

### Community 40 - "UInt8"
Cohesion: 0.32
Nodes (7): Int16, UInt16, UInt32, UInt8, Bool, Int, WhoopFraming

### Community 41 - "String"
Cohesion: 0.10
Nodes (33): GolfImprover, ImproverDrill, .displayLine, ImproverFocus, pathInToOut, pathOnPlane, pathOutToIn, tempoRush (+25 more)

### Community 42 - "MetricSource"
Cohesion: 0.13
Nodes (14): SwingLocationObservation, .hasValidCoordinate, MetricSource, appleWatch, demo, derived, healthKit, iphoneGPS (+6 more)

### Community 43 - "RecordingBridgeTransport"
Cohesion: 0.24
Nodes (4): BridgeRoundPayloadTests, RecordingBridgeTransport, Int, URLRequest

### Community 44 - "Data"
Cohesion: 0.29
Nodes (7): Curve25519, SymmetricKey, BridgePairingOffer, BridgePairingSession, Data, Encoder, String

### Community 45 - "AdaptiveSensorPlan"
Cohesion: 0.08
Nodes (28): AdaptiveSensorPlan, .fusedStatusDetail, .fusedStatusTitle, .isDualMaximize, .watchContributorDetail, .watchContributorStatus, .whoopContributorDetail, SensorModeOperationalState (+20 more)

### Community 46 - "CodingKeys"
Cohesion: 0.13
Nodes (15): CodingKeys, baseURL, bearerToken, ciphertext, expiresAt, kind, macPublicKey, nonce (+7 more)

### Community 47 - "WhoopBridgeClient"
Cohesion: 0.24
Nodes (6): Bool, ClosedRange, Double, String, WhoopBridgeClient, http

### Community 48 - "BridgeHTTPResult"
Cohesion: 0.12
Nodes (12): BridgePairingCredentialStoring, URLRequest, URLSession, URLSessionBridgePairingTransport, BridgeHTTPResult, BridgePairingClientTests, PairingCredentialRecorder, PairingRecordingTransport (+4 more)

### Community 49 - "Foundation"
Cohesion: 0.14
Nodes (7): Combine, CoreLocation, CryptoKit, Foundation, Security, WhoopGolf, XCTest

### Community 50 - ".append"
Cohesion: 0.32
Nodes (4): RoundLocationJournalTests, Date, Double, URL

### Community 51 - "State"
Cohesion: 0.12
Nodes (14): State, acquiring, denied, failed, idle, needsPermission, ready, reducedAccuracy (+6 more)

### Community 52 - "PendingWhoopMotionReviewBatch"
Cohesion: 0.11
Nodes (23): UIKit, PendingWhoopMotionEventDetail, .id, PendingWhoopMotionReviewBatch, .id, .undecidedCount, WhoopMotionReviewPendingReason, crossSourceConflict (+15 more)

### Community 53 - "WatchWristMount"
Cohesion: 0.18
Nodes (16): Double, Int, SwingPathGuidance, SwingPathScorer, watchLive, whoopRefined, SwingPathStrokeScore, Double (+8 more)

### Community 54 - "BridgeRoundOutboxError"
Cohesion: 0.40
Nodes (5): BridgeRoundOutboxError, corrupt, .errorDescription, flushAlreadyRunning, unavailable

### Community 55 - ".encode"
Cohesion: 0.26
Nodes (3): KeyedEncodingContainer, Encoder, T

### Community 56 - "DataProvenance"
Cohesion: 0.18
Nodes (10): DataProvenance, Date, RoundLocationCorrelation, LegacyGolfSwingMetrics, Date, Double, Request, Date (+2 more)

### Community 57 - "DualWearableFusion"
Cohesion: 0.19
Nodes (15): ContributionBoard, ContributionContext, .heartRateContext, ContributionLine, DualWearableFusion, HeartRateContext, HeartRateOwner, appleWatch (+7 more)

### Community 58 - "BridgePairingClientError"
Cohesion: 0.14
Nodes (14): StaticString, UInt, BridgePairingClientError, authenticationFailed, conflict, .errorDescription, expired, invalidOffer (+6 more)

### Community 59 - ".testDraftIsResumableButExcludedFromHistoryUntilFinished"
Cohesion: 0.36
Nodes (4): Snapshot, Int, RoundFileStoreTests, URL

### Community 60 - "WhoopCommand"
Cohesion: 0.14
Nodes (13): WhoopCommand, exitHighFreqSync, getAdvertisingName, getBatteryLevel, getClock, getDataRange, getHelloHarvard, sendR10R11Realtime (+5 more)

### Community 61 - "WatchStrokeChainSummary"
Cohesion: 0.21
Nodes (7): StrokeJournalStore, Any, JSONDecoder, JSONEncoder, URL, WatchStrokeChainSummary, WatchStrokeChainSummaryCodec

### Community 62 - "claudeTests"
Cohesion: 0.15
Nodes (3): claudeTests, claudeUITests, measure

### Community 63 - "golf-improver-engine"
Cohesion: 0.25
Nodes (7): API for UI agents (Watch + phone), Done, Evidence, Files touched, Gaps, golf-improver-engine, graphify

### Community 64 - "WatchSessionReceiveError"
Cohesion: 0.40
Nodes (5): WatchSessionReceiveError, .errorDescription, fileTooLarge, identityCollision, metadataMismatch

### Community 65 - "GolfStrokePresentation"
Cohesion: 0.11
Nodes (25): MapKit, GolfStrokeBoardView, .body, .hasMapPoints, MappedStroke, StrokeBoardRowView, .body, StrokeMapView (+17 more)

### Community 66 - "AutomaticHoleTransitionEvidence"
Cohesion: 0.14
Nodes (14): AutomaticHoleTransitionEvidence, enteredHoleScore, explicitAppleWatchGPSLocation, explicitIPhoneGPSLocation, licensedCurrentGreenRegion, licensedNextTeeRegion, longInterSwingPause, meaningfulGPSDisplacement (+6 more)

### Community 67 - "WhoopBridgeError"
Cohesion: 0.10
Nodes (17): BridgeHTTPTransport, Int, JSONDecoder, URLSession, URLSessionBridgeTransport, WhoopBridgeError, .errorDescription, invalidConfiguration (+9 more)

### Community 68 - "WhoopGeneration"
Cohesion: 0.38
Nodes (4): WhoopCommands, WhoopGeneration, whoop4, whoop5

### Community 69 - "CoreModelTests.swift"
Cohesion: 0.23
Nodes (9): fix(), LegacyRoundFixture, LegacyShotFixture, LocationTestContext, Date, Double, Int, LocationRoundService (+1 more)

### Community 70 - "XCTestCase"
Cohesion: 0.12
Nodes (8): claudeUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool, EighteenBirdiesCompanionLink, Bool, URL, EighteenBirdiesCompanionLinkTests, XCTestCase

### Community 71 - "String"
Cohesion: 0.29
Nodes (7): Any, CBPeripheral, Error, Int, NSNumber, String, WhoopLiveIMUPolicy

### Community 72 - "WhoopPacketType"
Cohesion: 0.20
Nodes (8): WhoopPacketType, command, commandResponse, historicalIMUStream, realtimeData, realtimeIMUStream, realtimeRawData, WhoopReassembler

### Community 73 - "Whoop5DiscoveryScanner"
Cohesion: 0.16
Nodes (14): String, .nilIfEmpty, Any, CBCentralManager, CBPeripheral, Date, Int, NSNumber (+6 more)

### Community 74 - "UUID"
Cohesion: 0.26
Nodes (5): CLLocation, Error, Task, UUID, .version

### Community 75 - "TASKS — D19 dual-wearable (manager-owned)"
Cohesion: 0.14
Nodes (13): 10. tailscale-ingest, 11. error-fixer-learner, 1. watch-round-face, 2. trail-right-motion, 3. watch-connectivity, 4. phone-yardage-bridge, 5. watch-healthkit, 6. xcode-ship (+5 more)

### Community 76 - "State"
Cohesion: 0.22
Nodes (9): State, bluetoothOff, found, idle, noBandFound, scanning, unauthorised, unavailable (+1 more)

### Community 77 - "watch-connectivity — agent status"
Cohesion: 0.15
Nodes (12): Done, Evidence, Files touched, Gaps / blockers, Misc, Next (not this agent), Phone inbound handlers (were missing), Phone → Watch (`applicationContext`, latest-wins) (+4 more)

### Community 78 - "CoreModelTests"
Cohesion: 0.21
Nodes (6): HeartRateMeasurement, HeartRateMeasurementParser, Double, Int, CoreModelTests, String

### Community 79 - "BridgeRoundPayload"
Cohesion: 0.27
Nodes (5): BridgeRoundPayload, .outboxID, Date, Decoder, RecordingRoundUploader

### Community 80 - "String"
Cohesion: 0.05
Nodes (51): AnyKey, CodingKeys, batchID, decision, eventID, payloadSHA256, recordedAt, recordedBy (+43 more)

### Community 81 - "RoundRecorder"
Cohesion: 0.15
Nodes (14): CaseIterable, RoundRecorder, .adaptiveSensorMode, appleWatch, .displayName, hybrid, .id, iphone (+6 more)

### Community 82 - "WhoopWristQualityReason"
Cohesion: 0.25
Nodes (8): WhoopWristQualityReason, accelerometerSaturation, coverageGap, gyroscopeSaturation, insufficientWindow, noAddressPause, sampleRateMismatch, transitionUnresolved

### Community 83 - "AppModel"
Cohesion: 0.08
Nodes (23): AnyCancellable, App, ObservableObject, AppModel, .adaptiveSensorPlan, .recommendedRoundRecorder, Set, Tab (+15 more)

### Community 84 - "watch-round-face"
Cohesion: 0.25
Nodes (7): Done (D19), Evidence, Files touched, Gaps, HANDOFFS, Verdict, watch-round-face

### Community 85 - "GolfHoleGreenTargets"
Cohesion: 0.15
Nodes (13): GolfHoleGreenTargets, .isValid, GolfHoleYardageProviding, GreenYards, .hasAny, PhoneYardageBridge, Bool, Double (+5 more)

### Community 86 - ".decode"
Cohesion: 0.27
Nodes (5): Decoder, Bool, Int, String, WatchYardageBridgeTests

### Community 87 - "CourseLookupState"
Cohesion: 0.22
Nodes (9): CourseLookupState, ambiguous, confirmed, failed, idle, locating, noneNearby, searching (+1 more)

### Community 88 - "WatchRoundContext"
Cohesion: 0.05
Nodes (45): HealthKit, LocalizedError, StoreError, .errorDescription, unavailable, Envelope, State, active (+37 more)

### Community 89 - "WHOOP Golf — Orchestration STATUS (D19 dual-wearable)"
Cohesion: 0.29
Nodes (6): Agent board, Cycle log, Done criteria (software-complete), Mandate (one line), Run recipe (draft), WHOOP Golf — Orchestration STATUS (D19 dual-wearable)

### Community 90 - "PermissionState"
Cohesion: 0.22
Nodes (9): PermissionState, always, denied, notRequested, requestingAlways, requestingWhenInUse, restricted, whenInUse (+1 more)

### Community 91 - "SensorModeConstraint"
Cohesion: 0.16
Nodes (12): .whoopContributorStatus, SensorModeConstraint, approximateIPhoneLocation, iphoneLocationUnavailable, noSwingSensorAvailable, watchNotReachable, watchSynchronizedLocationUnavailable, whoopBandHapticUnavailable (+4 more)

### Community 92 - "WatchLiveFace"
Cohesion: 0.25
Nodes (7): Any, Bool, Int, String, WatchLiveFace, .hasHoleMap, WatchLiveFaceCodec

### Community 93 - "SensorCapabilitySnapshot"
Cohesion: 0.22
Nodes (10): AppleWatchSensorCapabilities, .canCaptureLive, .hasSwingSource, SensorCapabilitySnapshot, WhoopSensorCapabilities, .canCaptureLive, .canReconstructPostRound, .hasSwingSource (+2 more)

### Community 94 - "CBUUID"
Cohesion: 0.36
Nodes (5): CBUUID, CoreBluetooth, Gen4, Gen5, WhoopUUIDs

### Community 95 - "CorrectionNeededBadge"
Cohesion: 0.40
Nodes (5): CorrectionNeededBadge, .body, PostRoundCompactValue, .body, .body

### Community 96 - "integrator (Claude Code) — build + cross-target integration"
Cohesion: 0.20
Nodes (9): Also fixed: device code signing, Blocker — `project.pbxproj` write war, Evidence, integrator (Claude Code) — build + cross-target integration, Landed on disk (source — verified present), Not done, Required target membership (please do not revert), Verified green (before the pbxproj was overwritten) (+1 more)

### Community 97 - "MotionBridgeTransport"
Cohesion: 0.31
Nodes (4): MotionBridgeTransport, Int, URLRequest, WhoopMotionBridgeClientTests

### Community 98 - "dual-wearable-fusion — D19"
Cohesion: 0.25
Nodes (7): Done, dual-wearable-fusion — D19, Evidence, Files touched, Gaps, Purpose, Secrets

### Community 99 - "trail-right-motion"
Cohesion: 0.25
Nodes (7): Done, Evidence, Feed (stroke-score-shot-chain), Files touched, Gaps, Purpose, trail-right-motion

### Community 100 - "wearable-architecture — D19 dual maximize"
Cohesion: 0.25
Nodes (7): Done, Evidence, Files touched, Gaps, Purpose, Secrets, wearable-architecture — D19 dual maximize

### Community 101 - "WatchSessionRecoveryFailure"
Cohesion: 0.21
Nodes (11): Any, FileManager, URL, takeOwnershipOfWatchSession(), invalidPayload, WatchSessionRecoveryFailure, .id, WatchSessionRecoveryScanner (+3 more)

### Community 102 - "HANDOFFS — blockers & ownership (D19)"
Cohesion: 0.33
Nodes (5): Active blockers, Agent-noted (non-blocking), Cleared, HANDOFFS — blockers & ownership (D19), Ownership claims (D19)

### Community 103 - "HybridSwingReviewReason"
Cohesion: 0.29
Nodes (7): HybridSwingReviewReason, ambiguousCrossSourceMatch, duplicateIdentity, invalidTimestamp, subsecondSameSourceConflict, unmatchedWhoopCandidate, unsupportedSource

### Community 104 - "WhoopWristTracePhase"
Cohesion: 0.29
Nodes (7): WhoopWristTracePhase, backswing, downswing, impact, takeaway, transition, unresolved

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

### Community 109 - "ShotYardageKind"
Cohesion: 0.33
Nodes (6): ShotYardageKind, measured, pending, tee, unavailable, withheld

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

### Community 114 - "WhoopMotionPullResult"
Cohesion: 0.50
Nodes (4): WhoopMotionPullResult, available, notModified, pending

### Community 116 - "WhoopMotionEvent"
Cohesion: 0.10
Nodes (22): DataQuality, estimated, stale, unavailable, verified, Int64, UInt8, WhoopMotionClassification (+14 more)

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
- **829 isolated node(s):** `.isValid`, `.isComplete`, `remain`, `review`, `advance` (+824 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `GolfCourseCandidate`, `WatchSessionImporter`, `TrendsView.swift`, `LiveRoundView`, `IMUMotionManager`, `SettingsView`, `TodayView`, `GolfRound`, `.init`, `DayResponse`, `RoundFileStore`, `View`, `WhoopBLEManager`, `WhoopMotionImportService`, `WhoopHeartRateProvider`, `BridgeSyncState`, `BridgeRoundOutbox`, `WatchSessionReceiver`, `AdaptiveSensorPlan`, `Foundation`, `PendingWhoopMotionReviewBatch`, `WatchWristMount`, `Whoop5DiscoveryScanner`, `String`, `RoundRecorder`, `GolfHoleGreenTargets`, `CourseLookupState`, `SensorCapabilitySnapshot`, `TrendsView`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Why does `UUID` connect `UUID` to `LocationRoundService`, `WatchSessionImporter`, `TrendsView.swift`, `Sendable`, `GolfRound`, `Identifiable`, `String`, `LocationFix`, `WhoopMotionEnvelope`, `SwingShotInterval`, `WhoopMotionImportService`, `BridgeConfiguration`, `GolfSwingMetrics`, `AutomaticHoleTransitionDecision`, `WatchSessionReceiver.swift`, `WatchSessionReceiver`, `String`, `WhoopBridgeClient`, `Foundation`, `.append`, `State`, `PendingWhoopMotionReviewBatch`, `DataProvenance`, `WatchStrokeChainSummary`, `GolfStrokePresentation`, `CoreModelTests.swift`, `Whoop5DiscoveryScanner`, `String`, `.decode`, `WatchRoundContext`, `MotionBridgeTransport`, `WatchSessionRecoveryFailure`, `WhoopMotionEvent`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Why does `GolfRound` connect `GolfRound` to `WatchSessionImporter`, `TrendsView.swift`, `LiveRoundView`, `String`, `Sendable`, `Identifiable`, `CodingKeys`, `RoundFileStore`, `View`, `SwingShotInterval`, `WhoopMotionImportService`, `GolfSwingMetrics`, `AutomaticHoleTransitionDecision`, `GolfHoleTransitionGeometry`, `WatchSessionReceiver`, `String`, `.testDraftIsResumableButExcludedFromHistoryUntilFinished`, `WatchStrokeChainSummary`, `GolfStrokePresentation`, `CoreModelTests.swift`, `UUID`, `BridgeRoundPayload`, `RoundRecorder`, `AppModel`, `SensorCapabilitySnapshot`, `TrendsView`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Are the 28 inferred relationships involving `GolfRound` (e.g. with `.sensorCapabilities` and `.importBatch()`) actually correct?**
  _`GolfRound` has 28 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.isValid`, `.isComplete`, `remain` to the rest of the system?**
  _829 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CodingKeys` be split into smaller, more focused modules?**
  _Cohesion score 0.02197802197802198 - nodes in this community are weakly interconnected._
- **Should `GolfCourseCandidate` be split into smaller, more focused modules?**
  _Cohesion score 0.0750925436277102 - nodes in this community are weakly interconnected._
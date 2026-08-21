# Graph Report - whoop-18birdies  (2026-08-21)

## Corpus Check
- 175 files · ~253,284 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3859 nodes · 9089 edges · 183 communities (170 shown, 13 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 527 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7bc4d7f6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CodingKeys
- GolfRound
- Sendable
- String
- WatchSessionImporter
- GolfRoundModelTests
- AppModel
- SensorModeCoordinator.swift
- SwingDetectorTests
- LiveRoundView
- AdaptiveSensorPlan
- TrendsView.swift
- IMUMotionManager
- GolfCourseLocator
- TestSettingsThatCostRounds
- String
- swing_logger.py
- analyse_swing
- WhoopBLEManager
- String
- render
- client.ts
- MotionFixture
- View
- String
- correlate.ts
- SwiftUI
- rounds.test.ts
- cli.ts
- SettingsView
- UUID
- WhoopFraming
- SessionModel
- UInt8
- SessionModel
- LocationFix
- WhoopMotionImportService
- shot_model.py
- parse_hr_measurement
- gen_swing_vectors.py
- .run_check
- SwingDetectorTests
- CodingKeys
- WatchSessionReceiver.swift
- round_report.py
- detect_shots
- test_trends.py
- test_shot_detect.py
- facts.ts
- cluster_distances
- WhoopBLEManager
- AutomaticHoleTransitionDecision
- LocalizedError
- BridgePairingClient
- package.json
- CodingKeys
- WhoopHeartRateProvider
- TestLocationManager
- SwingPathClass
- WatchWristMount
- Foundation
- Whoop5DiscoveryScanner
- Data
- BridgeRoundPayload
- selftest.py
- consistency
- SwingDashboard
- GolfHoleTransitionGeometry
- RoundFileStore
- String
- WhoopMotionReviewView
- Stop
- compilerOptions
- watch/generate-project.py
- MotionManager
- WatchSessionReceiver
- .append
- BridgeHTTPResult
- BridgeRoundOutbox
- CodingKeys
- test_shot_model.py
- TestLayout
- WhoopBridgeClient
- .testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely
- HeartRateMonitor
- AutomaticHoleTransitionEngine.swift
- GolfHoleGreenTargets
- BridgeConfiguration
- PhoneMotionManager
- .analyse
- .cue
- .interval
- ReceivedWatchSession
- CodingKeys
- XCTest
- WorkoutManager
- MetricSource
- AutomaticHoleTransitionEvidence
- RoundRecorder
- WatchLiveFace
- .encode
- WatchRoundContext
- BridgePairingClientError
- State
- WhoopCommand
- TestFitting
- whoop-18birdies
- WhoopCommand
- IMUMotionManager
- SessionView
- WatchSessionTransfer
- TASKS — per-agent assignments (manager-owned)
- claudeTests
- .decode
- WhoopMotionImportError
- BallFlightView
- AdaptiveThreshold
- What a WHOOP will and won't give a third party
- LocationManager
- sidecar/generate-project.py
- WHOOP × 18Birdies
- stats.ts
- State
- WhoopBridgeError
- Sample
- SidecarSessionView
- watch-round-face
- .fallbackURL
- LocationManager
- Double
- Start here
- wearable-architecture — SensorModeCoordinator Watch-first
- String
- CourseLookupState
- .begin
- Running this from your iPhone
- trend_verdict
- Apple Watch swing tracker (Series 5 and up)
- WatchRoundFaceView
- WHOOP Golf Watch Companion — Orchestration STATUS
- PermissionState
- RoundLocationCorrelation
- State
- State
- GPSSourceCheck
- TestSharedSchema
- TestAngleUnwrapping
- ModePicker
- trail-right-motion
- WhoopMotionImportOutcome
- WhoopMotionReviewOutcome
- TestReportIntegration
- TestChipsDoNotContaminateTheDistanceTrend
- Mac + Xcode setup (Kit A watch + Kit C sidecar)
- store.ts
- WHOOP and Apple Watch as substitutes
- golf-improver-engine
- WhoopUUIDs
- WHOOP IMU Sidecar (Kit C)
- WhoopUUIDs
- IngestSettings
- IngestSettings
- HANDOFFS — blockers & file-ownership conflicts
- claudeUITestsLaunchTests
- SwingHoleAssignmentMethod
- SwingCapturePlan
- Part 5 — tracking the golf itself, on the phone
- tempo_verdict
- TestSlopeAgainstSessionIndex
- setup-mac-xcode.sh
- WhoopFramingTests
- verify_info_plist
- Agent: tailscale-ingest
- WhoopMotionReviewReason
- BridgeRoundOutboxError
- run-tests.sh
- WHOOP reverse-engineering repos (reference)
- sidecar/build.sh
- GenerateProjectTest
- LESSONS.md
- String

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 122 edges
2. `AppModel` - 69 edges
3. `GolfRound` - 68 edges
4. `GolfSwingMetrics` - 52 edges
5. `LocationFix` - 48 edges
6. `DataProvenance` - 47 edges
7. `WhoopMotionImportService` - 44 edges
8. `WhoopBLEManager` - 42 edges
9. `RoundLocationJournal` - 40 edges
10. `RoundFileStore` - 39 edges

## Surprising Connections (you probably didn't know these)
- `.body` --references--> `ShotRecord`  [INFERRED]
  whoop-18birdies/apple/WhoopGolf/Views/RoundView.swift → whoop-18birdies/apple/Shared/GolfModels.swift
- `.reviewedRound` --references--> `AppModel`  [INFERRED]
  whoop-18birdies/apple/WhoopGolf/Views/TrendsView.swift → whoop-18birdies/apple/WhoopGolf/App/AppModel.swift
- `.round` --references--> `AppModel`  [INFERRED]
  whoop-18birdies/apple/WhoopGolf/Views/TrendsView.swift → whoop-18birdies/apple/WhoopGolf/App/AppModel.swift
- `.swingAssignmentControls` --references--> `AppModel`  [INFERRED]
  whoop-18birdies/apple/WhoopGolf/Views/TrendsView.swift → whoop-18birdies/apple/WhoopGolf/App/AppModel.swift
- `.round` --references--> `AppModel`  [INFERRED]
  whoop-18birdies/apple/WhoopGolf/Views/TrendsView.swift → whoop-18birdies/apple/WhoopGolf/App/AppModel.swift

## Import Cycles
- None detected.

## Communities (183 total, 13 thin omitted)

### Community 0 - "CodingKeys"
Cohesion: 0.02
Nodes (93): CodingKeys, algorithm, angularAxisConcentration, apiVersion, backswingSeconds, baseUnixSeconds, batchID, bpm (+85 more)

### Community 1 - "GolfRound"
Cohesion: 0.05
Nodes (66): Set, holes, GolfHoleCount, eighteen, .id, nine, GolfRound, .currentPar (+58 more)

### Community 2 - "Sendable"
Cohesion: 0.07
Nodes (77): SwingShotIntervalDisposition, withholdConfirmedHoleTransition, withholdPendingHoleTransitionReview, withholdUnverifiedSpatialSource, WhoopMotionComponent, WhoopMotionContractError, .errorDescription, invalidRequest (+69 more)

### Community 3 - "String"
Cohesion: 0.11
Nodes (29): Bool, ClosedRange, Date, Decoder, Double, Int, Int64, Set (+21 more)

### Community 4 - "WatchSessionImporter"
Cohesion: 0.07
Nodes (41): PendingWatchSession, Date, FileManager, Int, String, URL, WatchImportRegistry, WatchImportRegistryEntry (+33 more)

### Community 5 - "GolfRoundModelTests"
Cohesion: 0.07
Nodes (29): HeartRateMeasurement, HeartRateMeasurementParser, Double, Int, APIProvenance, Component, .id, DayResponse (+21 more)

### Community 6 - "AppModel"
Cohesion: 0.05
Nodes (45): AnyCancellable, AppModel, .adaptiveSensorPlan, .recommendedRoundRecorder, BridgeSyncState, failed, idle, queued (+37 more)

### Community 7 - "SensorModeCoordinator.swift"
Cohesion: 0.05
Nodes (42): HybridSwingReconciler, HybridSwingReconciliationResult, .canonicalSwings, HybridSwingResolution, watchCanonicalAwaitingWhoop, watchCanonicalWithWhoopEnrichment, HybridSwingReviewItem, .candidateIDs (+34 more)

### Community 8 - "SwingDetectorTests"
Cohesion: 0.09
Nodes (19): AdaptiveThreshold, .isReady, MotionSample, Bool, Double, Int, String, TimeInterval (+11 more)

### Community 9 - "LiveRoundView"
Cohesion: 0.05
Nodes (48): CourseCandidateButton, .body, LiveRoundView, .body, .gpsDetail, .gpsValue, .heartRateDetail, .recordingSourceLabel (+40 more)

### Community 10 - "AdaptiveSensorPlan"
Cohesion: 0.09
Nodes (32): AdaptiveSensorPlan, AppleWatchSensorCapabilities, .canCaptureLive, .hasSwingSource, IPhoneLocationCapability, approximate, .isAvailable, precise (+24 more)

### Community 11 - "TrendsView.swift"
Cohesion: 0.07
Nodes (49): SwingHoleAssignment, CorrectionNeededBadge, .body, PostRoundCompactValue, .body, PostRoundDetailView, .body, .measurementBoundary (+41 more)

### Community 12 - "IMUMotionManager"
Cohesion: 0.07
Nodes (28): IMUMotionManager, .achievedRateHz, .bufferMax, Int, MainActor, MotionSample, SwingMetrics, TimeInterval (+20 more)

### Community 13 - "GolfCourseLocator"
Cohesion: 0.09
Nodes (26): AppleMapsGolfCourseSearchProvider, Configuration, GolfCourseLocator, GolfCourseSearchPlace, GolfCourseSearchProviding, GolfCourseSearchRequest, GolfCourseSuggestion, ambiguous (+18 more)

### Community 14 - "TestSettingsThatCostRounds"
Cohesion: 0.06
Nodes (19): Exception, env_without_team(), generate_into_copy(), parse_openstep(), ParseError, ProjectCase, Tests for the Xcode project generator. A malformed .xcodeproj is worse than no…, Run the generator against a throwaway copy of watch/ and return (result,… (+11 more)

### Community 15 - "String"
Cohesion: 0.08
Nodes (30): PostRoundComparisonRow, .body, .hero, .roundSummary, PostRoundFormat, .body, .holeHeader, PostRoundMetricCapsule (+22 more)

### Community 16 - "swing_logger.py"
Cohesion: 0.08
Nodes (42): format_report(), Convert detected shots into the shared session schema. One schema, one…, A human read-out of a pocket-tracked round., to_session(), autosave(), calibrate(), choose_mode(), _connect_whoop_hr() (+34 more)

### Community 17 - "analyse_swing"
Cohesion: 0.08
Nodes (21): analyse_swing(), attitude_sweep(), find_motion_start(), find_transition(), Peak-to-peak roll/pitch/yaw travel over a span, in degrees. A proxy for how far…, Derives mechanics from a motion window. `samples` is [(t_seconds,…, A swing's phases in Tour Tempo's 30fps frame units, e.g. '24/8'., First sample of the backswing, walking back from impact. Returns the point… (+13 more)

### Community 18 - "WhoopBLEManager"
Cohesion: 0.11
Nodes (18): Any, CBCentralManager, CBCharacteristic, CBPeripheral, CBService, Error, Int, MainActor (+10 more)

### Community 19 - "String"
Cohesion: 0.12
Nodes (20): BridgePairingCodingKey, BridgePairingCredentialStoring, BridgePairingOffer, BridgePairingSession, BridgePairingStrictDecoding, KeychainBridgePairingCredentialStore, PairingClaimBody, PairingPlaintext (+12 more)

### Community 20 - "render"
Cohesion: 0.11
Nodes (11): Tests for the round report and its WHOOP join. These are mostly robustness…, The watch flags when its position came from the paired iPhone. An Apple Watch…, The join must degrade one line at a time, never take the report down., render(), swing(), TestGpsWarningIsObeyed, TestGpsWarningNormalisation, TestLoadSession (+3 more)

### Community 21 - "client.ts"
Cohesion: 0.09
Nodes (27): DEFAULT_SCOPES, loadAppConfig(), OAuthAppConfig, paths, WHOOP, WHOOP_MAX_PAGE_SIZE, ClientOptions, idString() (+19 more)

### Community 22 - "MotionFixture"
Cohesion: 0.16
Nodes (15): events, MotionFixture, .decoder, .encoder, RecordingMotionCorrelator, RecoveringMotionCorrelator, Any, JSONDecoder (+7 more)

### Community 23 - "View"
Cohesion: 0.08
Nodes (35): EighteenBirdiesCompanionCard, .body, GolfBackground, .body, GolfCard, .body, SourceBadge, .body (+27 more)

### Community 24 - "String"
Cohesion: 0.10
Nodes (34): AnyKey, LocationRoundService, PendingWhoopMotionBatch, PendingWhoopMotionEventDetail, .id, PendingWhoopMotionReviewBatch, .id, .undecidedCount (+26 more)

### Community 25 - "correlate.ts"
Cohesion: 0.11
Nodes (38): cmdReadiness(), cmdReport(), fmt(), DayPhysiology, indexPhysiology(), linkRounds(), LinkSummary, localToday() (+30 more)

### Community 26 - "SwiftUI"
Cohesion: 0.06
Nodes (28): App, claudeApp, .body, Scene, ContentView, .body, NavigationViewWrapper, .body (+20 more)

### Community 27 - "rounds.test.ts"
Cohesion: 0.12
Nodes (32): RFC-4180, LinkedRound, AppleWorkout, attr(), DEFAULT_SOURCES, ExtractOptions, localDateOf(), parseAppleDate() (+24 more)

### Community 28 - "cli.ts"
Cohesion: 0.13
Nodes (33): cmdCoach(), cmdGolf(), cmdImportCsv(), cmdImportHealth(), cmdLogin(), cmdRounds(), cmdServe(), cmdStatus() (+25 more)

### Community 29 - "SettingsView"
Cohesion: 0.06
Nodes (30): Color, ConnectionPill, .body, MetricTile, .body, Bool, String, SettingsView (+22 more)

### Community 30 - "UUID"
Cohesion: 0.15
Nodes (13): LocationRoundService, CLAccuracyAuthorization, CLAuthorizationStatus, CLLocation, CLLocationManager, Error, Task, UserDefaults (+5 more)

### Community 31 - "WhoopFraming"
Cohesion: 0.11
Nodes (18): Bool, Int, Int16, UInt16, UInt32, WhoopFrame, WhoopFraming, WhoopGeneration (+10 more)

### Community 32 - "SessionModel"
Cohesion: 0.12
Nodes (21): GeoPoint, SessionLog, SessionModel, .ingestToken, .ingestURL, .longestYards, .measuredDistances, .outboxDirectory (+13 more)

### Community 33 - "UInt8"
Cohesion: 0.14
Nodes (18): Bool, Int, Int16, UInt16, UInt32, WhoopFrame, WhoopFraming, WhoopGeneration (+10 more)

### Community 34 - "SessionModel"
Cohesion: 0.12
Nodes (20): GeoPoint, SessionLog, SessionModel, .ingestToken, .ingestURL, .longestYards, .measuredDistances, .outboxDirectory (+12 more)

### Community 35 - "LocationFix"
Cohesion: 0.17
Nodes (14): LocationFix, .isUsableForShotDistance, Configuration, ReadResult, Record, RoundLocationJournal, Bool, Date (+6 more)

### Community 36 - "WhoopMotionImportService"
Cohesion: 0.16
Nodes (10): records, Bool, FileManager, GolfRound, JSONDecoder, TimeInterval, URL, registryUnsupported (+2 more)

### Community 37 - "shot_model.py"
Cohesion: 0.11
Nodes (15): _area(), carry_m(), _lift_coefficient(), metres_to_yards(), Shot distance, swing-to-distance fitting, and ball flight trajectories.…, Empirical Cl from the spin parameter S = omega * r / v. Cl = 0.32 * S**0.35…, Integrates a ball flight with quadratic drag and Magnus lift. Returns [(x, y),…, Finds the launch speed whose carry matches a measured distance. Bisection:… (+7 more)

### Community 38 - "parse_hr_measurement"
Cohesion: 0.11
Nodes (13): attach_hr_to_shots(), nearest_hr(), parse_hr_measurement(), Live heart rate from a WHOOP strap, over Bluetooth, into the swing logger.…, Stamp hr_bpm onto each shot from the nearest live reading. Mutates and returns…, Decodes a Heart Rate Measurement (0x2A37) notification payload. Layout per the…, rMSSD in milliseconds over a list of RR intervals in seconds. The standard…, Closest bpm in hr_log to at_t, or None if nothing is fresh enough. hr_log is a… (+5 more)

### Community 39 - "gen_swing_vectors.py"
Cohesion: 0.13
Nodes (26): analyse_cases(), at(), build(), build_swing(), consistency_cases(), encode(), frames_cases(), main() (+18 more)

### Community 40 - ".run_check"
Cohesion: 0.14
Nodes (8): Tests for the phone pre-flight check. selftest.py exists to catch a broken…, Install fake Pythonista modules with the behaviour a test wants., SelfTestCase, stub_devices(), TestGPSCheck, TestMotionCheck, TestRunner, TestUploadCheck

### Community 41 - "SwingDetectorTests"
Cohesion: 0.20
Nodes (8): Any, Double, Int, MotionSample, StaticString, String, UInt, SwingDetectorTests

### Community 42 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, capturedAt, courseName, currentHole, currentPar, displacementFromPreviousYards, distanceToNextYards, distanceUncertaintyYards (+19 more)

### Community 43 - "WatchSessionReceiver.swift"
Cohesion: 0.13
Nodes (22): Notification.Name, Bool, Double, Int, WatchSessionLocationPayload, WatchSessionMode, range, round (+14 more)

### Community 44 - "round_report.py"
Cohesion: 0.13
Nodes (25): is_session_log(), main(), One entry point for reading logged sessions off-device. python3 analyze.py…, True if the file looks like a swing log (has a swings list)., format_club_report(), Renders analyze_clubs() output as console lines., gps_warning_of(), load_session() (+17 more)

### Community 45 - "detect_shots"
Cohesion: 0.16
Nodes (9): detect_shots(), GPS track in, shots out. The one call the logger needs. Unknown keywords raise…, Round-level numbers from detected shots. None when there is nothing to say., summarise(), A whole round: stand, hit, walk the shot's distance, stand, hit..., round_track(), TestShotDistances, TestSummary (+1 more)

### Community 46 - "test_trends.py"
Cohesion: 0.13
Nodes (17): Tests for trends — direction of travel across multiple sessions., Build a session (list of swing dicts) from parallel metric lists., sess(), TestAnalyze, TestSessionValue, TestSlope, analyze_trends(), linear_slope() (+9 more)

### Community 47 - "test_shot_detect.py"
Cohesion: 0.16
Nodes (13): find_stops(), Find the places you stood still long enough to have hit a shot. `fixes` is a…, fix(), offset(), Tests for pocket-mode shot detection. The tracks here are synthetic but shaped…, The bug this replaced was severe and completely silent. Discarding an over-long…, Move a coordinate by a distance in metres. Good to well under a metre at these…, Fixes taken while standing still, with realistic GPS wander. (+5 more)

### Community 48 - "facts.ts"
Cohesion: 0.13
Nodes (21): COACH_MODEL, CoachOptions, CoachRead, buildFacts(), median(), MIN_CV_N, MIN_SPLIT_N, minutesBetween() (+13 more)

### Community 49 - "cluster_distances"
Cohesion: 0.14
Nodes (12): analyze_clubs(), club_gaps(), cluster_distances(), _mean(), Infer club groupings and gapping from measured shot distances. Given the GPS-…, Groups shot distances into club bands by 1-D gap clustering. Sorts the…, Yardage gaps between adjacent club bands, longest club downward. Returns a list…, Full club report from a set of measured carries. Returns {bands, gaps, flags}.… (+4 more)

### Community 50 - "WhoopBLEManager"
Cohesion: 0.12
Nodes (16): Any, CBCentralManager, CBCharacteristic, CBPeripheral, CBService, Error, Int, MainActor (+8 more)

### Community 51 - "AutomaticHoleTransitionDecision"
Cohesion: 0.27
Nodes (6): AutomaticHoleTransitionContext, AutomaticHoleTransitionDecision, Date, AutomaticHoleTransitionEngineTests, Date, Double

### Community 52 - "LocalizedError"
Cohesion: 0.08
Nodes (24): WatchRoundContextError, .errorDescription, invalidCourseName, invalidEnvelope, invalidStartedAt, malformed, unsupportedSchema, WatchSessionReceiveError (+16 more)

### Community 53 - "BridgePairingClient"
Cohesion: 0.17
Nodes (9): BridgePairingClient, Bool, JSONDecoder, JSONEncoder, T, URLRequest, URLSession, URLSessionBridgePairingTransport (+1 more)

### Community 54 - "package.json"
Cohesion: 0.09
Nodes (22): @anthropic-ai/sdk, bin, wb, dependencies, @anthropic-ai/sdk, zod, description, devDependencies (+14 more)

### Community 55 - "CodingKeys"
Cohesion: 0.09
Nodes (23): CodingKeys, altitude, autoThreshold, backswingSeconds, completedAt, downswingSeconds, heartRateBPM, horizontalAccuracy (+15 more)

### Community 56 - "WhoopHeartRateProvider"
Cohesion: 0.13
Nodes (16): Any, Bool, CBCentralManager, CBCharacteristic, CBPeripheral, CBService, Date, Error (+8 more)

### Community 57 - "TestLocationManager"
Cohesion: 0.14
Nodes (10): LocationRoundServiceAuthorizationTests, LocationTestContext, CLAccuracyAuthorization, CLAuthorizationStatus, LocationRoundService, Void, TestLocationManager, .accuracyAuthorization (+2 more)

### Community 58 - "SwingPathClass"
Cohesion: 0.13
Nodes (9): Double, SwingPathClass, inToOut, onPlane, outToIn, unknown, SwingPathGuidance, SwingPathGuidanceTests (+1 more)

### Community 59 - "WatchWristMount"
Cohesion: 0.13
Nodes (12): Double, UserDefaults, WatchWristMount, .coachingName, .detail, .displayName, .id, leadLeft (+4 more)

### Community 60 - "Foundation"
Cohesion: 0.14
Nodes (8): Combine, CoreBluetooth, CoreLocation, CoreMotion, Foundation, HealthKit, Security, WatchConnectivity

### Community 61 - "Whoop5DiscoveryScanner"
Cohesion: 0.16
Nodes (14): String, .nilIfEmpty, Any, CBCentralManager, CBPeripheral, Date, Int, NSNumber (+6 more)

### Community 62 - "Data"
Cohesion: 0.29
Nodes (5): Data, WhoopGeneration, WhoopCommands, WhoopGeneration, WhoopCommands

### Community 63 - "BridgeRoundPayload"
Cohesion: 0.15
Nodes (10): BridgeRoundPayload, .outboxID, BridgeRoundUploadResponse, Date, Decoder, GolfRound, Int, BridgeRoundPayloadTests (+2 more)

### Community 64 - "selftest.py"
Cohesion: 0.26
Nodes (18): _autolock(), check(), fail(), _gps(), main(), _modules(), _modules_import(), _motion() (+10 more)

### Community 65 - "consistency"
Cohesion: 0.15
Nodes (13): live_stats(), print_hr_block(), Heart-rate read-out for the session, if a WHOOP was streaming., consistency(), fatigue_split(), _mean(), Swing mechanics extracted from a captured motion window. The detector only…, Undo the +/-pi wrap in an angle sequence, in place of the raw values. Core… (+5 more)

### Community 66 - "SwingDashboard"
Cohesion: 0.14
Nodes (6): _label(), main(), Position everything against the real size. Called by Pythonista once the view…, Full-screen live readout. Detection runs on a background thread; the UI…, Create the subviews. Positioning happens in layout(), not here. A ui.View is…, SwingDashboard

### Community 67 - "GolfHoleTransitionGeometry"
Cohesion: 0.20
Nodes (10): AutomaticHoleTransitionEngine, Configuration, GolfHoleSpatialRegion, .isValid, GolfHoleTransitionGeometry, .isValid, Bool, Double (+2 more)

### Community 68 - "RoundFileStore"
Cohesion: 0.22
Nodes (9): RoundFileStore, Snapshot, GolfRound, Int, JSONDecoder, JSONEncoder, URL, RoundFileStoreTests (+1 more)

### Community 69 - "String"
Cohesion: 0.18
Nodes (8): Bool, ClosedRange, Double, String, WhoopMotionPullResult, available, notModified, pending

### Community 70 - "WhoopMotionReviewView"
Cohesion: 0.17
Nodes (13): CapabilityRow, .body, PromiseRow, .body, SettingsConnectionRow, .body, Bool, Set (+5 more)

### Community 71 - "Stop"
Cohesion: 0.12
Nodes (12): _iso_local(), Infer shot locations from a GPS track, with the phone in your pocket. WHY THIS…, A place you stood still long enough to have hit a shot., A fix is usable only if it carries a real position and a sane accuracy. iOS…, Mark each fix as stationary or not, by displacement over a time window. This is…, Turn consecutive stops into shots with measured distances. Every stop but the…, Local-time ISO stamp, matching what the swing logger writes. Local rather than…, shots_from_stops() (+4 more)

### Community 72 - "compilerOptions"
Cohesion: 0.11
Nodes (18): bun-types, ESNext, src/**/*.ts, test/**/*.ts, compilerOptions, allowImportingTsExtensions, lib, module (+10 more)

### Community 73 - "watch/generate-project.py"
Cohesion: 0.19
Nodes (14): app_settings(), build(), common_settings(), development_team(), main(), Pbx, The Apple Team ID to bake into the project, from $DEVELOPMENT_TEAM. Validated…, Cheap structural checks. Not a pbxproj parser — just enough to catch the… (+6 more)

### Community 74 - "MotionManager"
Cohesion: 0.13
Nodes (14): MotionManager, .achievedRateHz, .bufferMax, .isAvailable, .walkingFraction, Bool, Double, Int (+6 more)

### Community 75 - "WatchSessionReceiver"
Cohesion: 0.25
Nodes (5): Error, WCSession, WCSessionActivationState, WatchSessionReceiver, WCSessionFile

### Community 76 - ".append"
Cohesion: 0.31
Nodes (4): RoundLocationJournalTests, Date, Double, URL

### Community 77 - "BridgeHTTPResult"
Cohesion: 0.22
Nodes (7): BridgeHTTPResult, RecordingBridgeTransport, Int, URLRequest, MotionBridgeTransport, Int, URLRequest

### Community 78 - "BridgeRoundOutbox"
Cohesion: 0.32
Nodes (6): BridgeRoundOutbox, BridgeRoundOutboxEntry, Envelope, FlushResult, BridgeRoundOutboxTests, URL

### Community 79 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, course, endedAt, grossScore, holes, localDate, par, startedAt (+10 more)

### Community 80 - "test_shot_model.py"
Cohesion: 0.19
Nodes (8): haversine_m(), Great-circle distance in metres between two WGS84 points., Annotates each swing with the distance to the following swing. This is how…, shot_distances(), Tests for shot_model. Runs anywhere — no Pythonista needed., TestGeometry, TestLonGuard, TestShotDistances

### Community 81 - "TestLayout"
Cohesion: 0.17
Nodes (7): install_pythonista_stubs(), Tests for the Pythonista dashboard's layout and session finalisation. The…, Every control must be inside the view once it has a real size., The dashboard must compute distances, as the console logger does. Without this…, A `ui` module just real enough to lay a view out and inspect it., TestLayout, TestSessionFinalisation

### Community 82 - "WhoopBridgeClient"
Cohesion: 0.21
Nodes (7): BridgeHTTPTransport, BridgeRoundUploading, JSONDecoder, URLSession, URLSessionBridgeTransport, WhoopBridgeClient, http

### Community 83 - ".testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely"
Cohesion: 0.18
Nodes (7): BridgePairingClientTests, PairingCredentialRecorder, PairingRecordingTransport, Bool, Int, String, URLRequest

### Community 84 - "HeartRateMonitor"
Cohesion: 0.12
Nodes (5): HeartRateMonitor, Connects to a broadcasting WHOOP and keeps the latest reading available. Usage:…, Scan, connect and subscribe. True on success within the timeout., The latest heart rate, or None if there is no fresh reading. Staleness matters:…, rMSSD over the rolling RR window, or None without RR data. WHOOP's broadcast…

### Community 85 - "AutomaticHoleTransitionEngine.swift"
Cohesion: 0.14
Nodes (15): AutomaticHoleTransitionAction, advance, remain, review, useRecordedBoundary, AutomaticHoleTransitionConfidence, confirmed, high (+7 more)

### Community 86 - "GolfHoleGreenTargets"
Cohesion: 0.25
Nodes (10): GolfHoleGreenTargets, .isValid, GolfHoleYardageProviding, GreenYards, .hasAny, PhoneYardageBridge, Bool, Double (+2 more)

### Community 87 - "BridgeConfiguration"
Cohesion: 0.26
Nodes (5): BridgeConfiguration, JSONEncoder, URL, URLRequest, WhoopMotionBridgeClientTests

### Community 88 - "PhoneMotionManager"
Cohesion: 0.17
Nodes (12): PhoneMotionManager, .achievedRateHz, .bufferMax, .isAvailable, Bool, Int, MainActor, MotionSample (+4 more)

### Community 89 - ".analyse"
Cohesion: 0.26
Nodes (7): MotionSample, Int, String, TimeInterval, SwingAnalysis, SwingMetrics, TempoBench

### Community 90 - ".cue"
Cohesion: 0.23
Nodes (7): GolfImprover, Double, String, TempoBand, rushing, slow, .improverScreen

### Community 91 - ".interval"
Cohesion: 0.19
Nodes (6): ShotDistanceCalculator, Double, Bool, Double, TimeInterval, SwingShotIntervalCalculator

### Community 92 - "ReceivedWatchSession"
Cohesion: 0.26
Nodes (10): ReceivedWatchSession, FileManager, URL, takeOwnershipOfWatchSession(), invalidPayload, WatchSessionRecoveryFailure, .id, WatchSessionRecoverySnapshot (+2 more)

### Community 93 - "CodingKeys"
Cohesion: 0.13
Nodes (15): CodingKeys, baseURL, bearerToken, ciphertext, expiresAt, kind, macPublicKey, nonce (+7 more)

### Community 95 - "WorkoutManager"
Cohesion: 0.20
Nodes (9): HKLiveWorkoutBuilder, HKLiveWorkoutBuilderDelegate, HKSampleType, HKWorkoutSessionDelegate, CLLocation, Int, Set, String (+1 more)

### Community 96 - "MetricSource"
Cohesion: 0.15
Nodes (12): MetricSource, appleWatch, demo, derived, healthKit, iphoneGPS, manual, .symbol (+4 more)

### Community 97 - "AutomaticHoleTransitionEvidence"
Cohesion: 0.14
Nodes (14): AutomaticHoleTransitionEvidence, enteredHoleScore, explicitAppleWatchGPSLocation, explicitIPhoneGPSLocation, licensedCurrentGreenRegion, licensedNextTeeRegion, longInterSwingPause, meaningfulGPSDisplacement (+6 more)

### Community 98 - "RoundRecorder"
Cohesion: 0.15
Nodes (14): RoundRecorder, .adaptiveSensorMode, appleWatch, .displayName, hybrid, .id, iphone, whoop5 (+6 more)

### Community 99 - "WatchLiveFace"
Cohesion: 0.31
Nodes (7): Any, Bool, Int, String, WatchLiveFace, .hasHoleMap, WatchLiveFaceCodec

### Community 100 - ".encode"
Cohesion: 0.26
Nodes (3): Encoder, T, KeyedEncodingContainer

### Community 101 - "WatchRoundContext"
Cohesion: 0.25
Nodes (8): Envelope, State, active, cleared, Date, WatchRoundApplicationContextCodec, WatchRoundContext, unsupportedSchema

### Community 102 - "BridgePairingClientError"
Cohesion: 0.14
Nodes (14): BridgePairingClientError, authenticationFailed, conflict, .errorDescription, expired, invalidOffer, invalidResponse, notReady (+6 more)

### Community 103 - "State"
Cohesion: 0.14
Nodes (12): State, acquiring, denied, failed, idle, needsPermission, ready, reducedAccuracy (+4 more)

### Community 104 - "WhoopCommand"
Cohesion: 0.14
Nodes (13): WhoopCommand, exitHighFreqSync, getAdvertisingName, getBatteryLevel, getClock, getDataRange, getHelloHarvard, sendR10R11Realtime (+5 more)

### Community 105 - "TestFitting"
Cohesion: 0.20
Nodes (7): fit_swings(), linear_fit(), predict_distance(), Predicted carry in yards for a swing, or None without a usable fit., Least-squares slope/intercept plus r-squared. None if underdetermined., Fits peak swing magnitude to measured carry, over swings that have both., TestFitting

### Community 106 - "whoop-18birdies"
Cohesion: 0.14
Nodes (14): Claude skill, Commands, Development, Example report, Getting rounds in, Ingest server, Notes on the WHOOP API, Path 1 — the on-phone link (+6 more)

### Community 107 - "WhoopCommand"
Cohesion: 0.14
Nodes (13): WhoopCommand, exitHighFreqSync, getAdvertisingName, getBatteryLevel, getClock, getDataRange, getHelloHarvard, sendR10R11Realtime (+5 more)

### Community 108 - "IMUMotionManager"
Cohesion: 0.18
Nodes (10): IMUMotionManager, .achievedRateHz, .bufferMax, Int, MainActor, MotionSample, SwingMetrics, TimeInterval (+2 more)

### Community 109 - "SessionView"
Cohesion: 0.23
Nodes (9): SessionView, .body, .useGPS, Bool, Double, SessionModel, String, Void (+1 more)

### Community 110 - "WatchSessionTransfer"
Cohesion: 0.23
Nodes (9): Any, Double, Error, Int, String, WCSession, WCSessionActivationState, WatchSessionTransfer (+1 more)

### Community 111 - "TASKS — per-agent assignments (manager-owned)"
Cohesion: 0.15
Nodes (12): 10. tailscale-ingest, 11. error-fixer-learner, 1. watch-round-face, 2. trail-right-motion, 3. watch-connectivity, 4. phone-yardage-bridge, 5. watch-healthkit, 6. xcode-ship (+4 more)

### Community 112 - "claudeTests"
Cohesion: 0.15
Nodes (3): claudeTests, claudeUITests, measure

### Community 113 - ".decode"
Cohesion: 0.24
Nodes (5): Decoder, Bool, Int, String, WatchYardageBridgeTests

### Community 114 - "WhoopMotionImportError"
Cohesion: 0.15
Nodes (13): WhoopMotionImportError, .errorDescription, identityCollision, inboxCorrupt, inboxMissing, locationUnavailable, payloadTooLarge, registryCorrupt (+5 more)

### Community 115 - "BallFlightView"
Cohesion: 0.21
Nodes (6): BallFlightView, load_shots(), main(), Animated ball flight for a logged shot, drawn on the phone. Reads the swings…, Every logged swing that has a measured distance, longest first., World metres -> screen points, with y growing upward on screen.

### Community 116 - "AdaptiveThreshold"
Cohesion: 0.24
Nodes (4): AdaptiveThreshold, A swing threshold that calibrates itself from your own recent motion. A fixed…, True once there is enough history for the baseline to mean anything., TestAdaptivePerf

### Community 117 - "What a WHOOP will and won't give a third party"
Cohesion: 0.15
Nodes (13): GPS — still not on the strap, Integration options if you want WHOOP-as-swing-sensor, Net capability matrix, Official cloud API (what `wb` uses), The Bluetooth surface, Three different "ceilings", What a WHOOP will and won't give a third party, What is readable on each path (+5 more)

### Community 118 - "LocationManager"
Cohesion: 0.18
Nodes (7): NSObject, LocationManager, CLLocation, CLLocationManager, Error, GeoPoint, String

### Community 119 - "sidecar/generate-project.py"
Cohesion: 0.28
Nodes (8): app_settings(), build(), common_settings(), development_team(), main(), Pbx, test_settings(), uid()

### Community 120 - "WHOOP × 18Birdies"
Cohesion: 0.15
Nodes (12): Commands, Getting rounds in, If the user asks you to read their iPhone directly, Interpreting the report, One-time setup, Path 1 — the on-phone link (do this first), Path 2 — the toolkit, Readiness (+4 more)

### Community 121 - "stats.ts"
Cohesion: 0.40
Nodes (11): correlateAll(), betacf(), correlate(), correlationPValue(), incompleteBeta(), lngamma(), mean(), pearson() (+3 more)

### Community 122 - "State"
Cohesion: 0.17
Nodes (12): HealthAuthorizationError, .errorDescription, workoutSaveFailed, workoutWriteNotAuthorised, State, denied, failed, notRequested (+4 more)

### Community 123 - "WhoopBridgeError"
Cohesion: 0.17
Nodes (12): WhoopBridgeError, .errorDescription, invalidConfiguration, invalidResponse, invalidRoundPayload, motionRequestConflict, motionRequestNotFound, noData (+4 more)

### Community 124 - "Sample"
Cohesion: 0.33
Nodes (7): Sample, Double, Int, TimeInterval, UInt8, WhoopFrame, WhoopIMUDecoder

### Community 125 - "SidecarSessionView"
Cohesion: 0.29
Nodes (8): SidecarSessionView, .body, .tempoLine, .useGPS, Bool, SessionModel, String, Void

### Community 126 - "watch-round-face"
Cohesion: 0.18
Nodes (10): Done, Evidence (what UI shows), Files touched, Gaps, HANDOFFS, Related (read-only, not edited), SessionView (`WhoopGolfWatchApp/SessionView.swift`), SettingsView (`WhoopGolfWatchApp/SettingsView.swift`) (+2 more)

### Community 127 - ".fallbackURL"
Cohesion: 0.20
Nodes (4): EighteenBirdiesCompanionLink, Bool, URL, EighteenBirdiesCompanionLinkTests

### Community 128 - "LocationManager"
Cohesion: 0.22
Nodes (5): CLLocationManagerDelegate, LocationManager, CLLocation, CLLocationManager, Error

### Community 129 - "Double"
Cohesion: 0.38
Nodes (4): AdaptiveThreshold, .isReady, Bool, Double

### Community 130 - "Start here"
Cohesion: 0.18
Nodes (11): 1. WHOOP only — zero setup, do this first, 2. Pocket — yardages, nothing strapped on, 3. Arm — tempo and swing force, Getting the data to your Mac, If something does not work, If you keep things in iCloud, Kit B — no watch (WHOOP + phone), Putting the two halves together (+3 more)

### Community 131 - "wearable-architecture — SensorModeCoordinator Watch-first"
Cohesion: 0.20
Nodes (9): Auto plan — `plan(for: SensorCapabilitySnapshot)`, Done, Evidence summary, Evidence (tests already covering policy), Files touched, Gaps, Mode selection (D18 / D15), Watch-first details (aligned with D18) (+1 more)

### Community 132 - "String"
Cohesion: 0.51
Nodes (4): Any, String, WatchCoachingCue, WatchCoachingCueCodec

### Community 133 - "CourseLookupState"
Cohesion: 0.22
Nodes (9): CourseLookupState, ambiguous, confirmed, failed, idle, locating, noneNearby, searching (+1 more)

### Community 134 - ".begin"
Cohesion: 0.22
Nodes (6): HKWorkoutRouteBuilder, HKWorkoutSession, HKWorkoutSessionState, Bool, Date, Error

### Community 135 - "Running this from your iPhone"
Cohesion: 0.20
Nodes (10): A note on the Shortcuts action names, If you'd rather not run a server, Live WHOOP heart rate during a session (experimental), Part 1 — the native link (no code, do this first), Part 2 — start the ingest server, Part 3 — Shortcut A: push a round after you play, Part 4 — Shortcut B: readiness before you tee off, Reachability off your home network (+2 more)

### Community 136 - "trend_verdict"
Cohesion: 0.33
Nodes (3): TestTrendVerdict, Direction of travel for a metric across sessions. Returns {slope, direction,…, trend_verdict()

### Community 137 - "Apple Watch swing tracker (Series 5 and up)"
Cohesion: 0.20
Nodes (10): Apple Watch swing tracker (Series 5 and up), Build it (about 2 minutes, once), Getting the data off the watch, Honest limits, How the round reaches WHOOP, If your phone is wired and VPN'd to the Mac, The watch cannot reach your tailnet, Using it (+2 more)

### Community 138 - "WatchRoundFaceView"
Cohesion: 0.33
Nodes (8): Double, Int, String, WatchRoundFaceView, .body, .lastYardsLine, .pathScreen, .yardageScreen

### Community 139 - "WHOOP Golf Watch Companion — Orchestration STATUS"
Cohesion: 0.22
Nodes (8): Agent board, Canonical paths, Cycle log, Done criteria, Goal (software-complete), Hard constraints, Run recipe (draft — finalize at COMPLETE), WHOOP Golf Watch Companion — Orchestration STATUS

### Community 140 - "PermissionState"
Cohesion: 0.22
Nodes (9): PermissionState, always, denied, notRequested, requestingAlways, requestingWhenInUse, restricted, whenInUse (+1 more)

### Community 141 - "RoundLocationCorrelation"
Cohesion: 0.33
Nodes (5): RoundLocationCorrelation, Request, Date, Double, TimeInterval

### Community 142 - "State"
Cohesion: 0.22
Nodes (9): State, bluetoothOff, found, idle, noBandFound, scanning, unauthorised, unavailable (+1 more)

### Community 143 - "State"
Cohesion: 0.22
Nodes (9): State, bluetoothOff, connecting, failed, idle, scanning, stale, streaming (+1 more)

### Community 144 - "GPSSourceCheck"
Cohesion: 0.31
Nodes (7): CLLocationDistance, GPSSourceCheck, CLLocation, Date, Double, String, TimeInterval

### Community 147 - "ModePicker"
Cohesion: 0.28
Nodes (6): ModePicker, .body, Scene, String, WhoopGolfApp, .body

### Community 148 - "trail-right-motion"
Cohesion: 0.25
Nodes (7): API (for UI / tests), Done, Evidence, Files touched, Gaps, Purpose, trail-right-motion

### Community 149 - "WhoopMotionImportOutcome"
Cohesion: 0.25
Nodes (8): WhoopMotionImportOutcome, duplicate, imported, invalid, stagedCrossSourceConflict, stagedLocationUnavailable, stagedNeedsReview, stagedRoundUnavailable

### Community 150 - "WhoopMotionReviewOutcome"
Cohesion: 0.25
Nodes (8): WhoopMotionReviewOutcome, duplicate, invalid, recorded, resolved, stagedCrossSourceConflict, stagedLocationUnavailable, stagedRoundUnavailable

### Community 153 - "Mac + Xcode setup (Kit A watch + Kit C sidecar)"
Cohesion: 0.25
Nodes (6): Mac + Xcode setup (Kit A watch + Kit C sidecar), Troubleshooting, wb serve, What the script does, WHOOP sidecar (Kit C) before connecting, Xcode — both projects

### Community 154 - "store.ts"
Cohesion: 0.46
Nodes (7): exists(), loadWatchSession(), safeLabel(), saveRounds(), saveSnapshot(), saveWatchSession(), writeJson()

### Community 155 - "WHOOP and Apple Watch as substitutes"
Cohesion: 0.25
Nodes (8): Kit A — Apple Watch (preferred when you have it), Kit B — WHOOP + iPhone (when the watch stays home), Kit C — WHOOP IMU sidecar (implemented), Same day, either kit, The short version, Two kits that substitute (supported today), What you cannot get from any kit, WHOOP and Apple Watch as substitutes

### Community 156 - "golf-improver-engine"
Cohesion: 0.29
Nodes (6): Done, Evidence, Files touched, Gaps, golf-improver-engine, graphify

### Community 157 - "WhoopUUIDs"
Cohesion: 0.43
Nodes (5): Gen4, Gen5, CBUUID, WhoopGeneration, WhoopUUIDs

### Community 159 - "WHOOP IMU Sidecar (Kit C)"
Cohesion: 0.29
Nodes (7): Before you connect, Build (Mac + Xcode), Limitations, Modes, Protocol code, Session JSON, WHOOP IMU Sidecar (Kit C)

### Community 160 - "WhoopUUIDs"
Cohesion: 0.43
Nodes (5): Gen4, Gen5, CBUUID, WhoopGeneration, WhoopUUIDs

### Community 161 - "IngestSettings"
Cohesion: 0.29
Nodes (6): IngestSettings, .isConfigured, .token, .url, Bool, String

### Community 162 - "IngestSettings"
Cohesion: 0.29
Nodes (6): IngestSettings, .isConfigured, .token, .url, Bool, String

### Community 163 - "HANDOFFS — blockers & file-ownership conflicts"
Cohesion: 0.33
Nodes (5): Active blockers, Cleared (history), HANDOFFS — blockers & file-ownership conflicts, Ownership claims / releases, Protocol

### Community 164 - "claudeUITestsLaunchTests"
Cohesion: 0.33
Nodes (3): claudeUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool

### Community 165 - "SwingHoleAssignmentMethod"
Cohesion: 0.33
Nodes (6): SwingHoleAssignmentMethod, .displayName, manualCorrection, manualUnassignment, roundTimeline, unavailable

### Community 166 - "SwingCapturePlan"
Cohesion: 0.33
Nodes (6): SwingCapturePlan, appleWatchMotion, appleWatchMotionWithWhoopEnrichment, none, whoopAuthorizedLiveMotion, whoopHistoricalMotion

### Community 167 - "Part 5 — tracking the golf itself, on the phone"
Cohesion: 0.33
Nodes (6): Ball flight animation, Constraints that apply to all three, Part 5 — tracking the golf itself, on the phone, Pocket — yardages, nothing strapped on, Range / Round — tempo and swing force, Shot distance

### Community 170 - "setup-mac-xcode.sh"
Cohesion: 0.60
Nodes (5): grn(), hdr(), red(), setup-mac-xcode.sh script, ylw()

### Community 173 - "Agent: tailscale-ingest"
Cohesion: 0.40
Nodes (4): Agent purpose, Agent: tailscale-ingest, Phone → ingest checklist, Probe results (localhost only)

### Community 174 - "WhoopMotionReviewReason"
Cohesion: 0.40
Nodes (5): WhoopMotionReviewReason, coverageGapNearEvent, duplicateCandidate, lowDetectorConfidence, roundBoundary

### Community 175 - "BridgeRoundOutboxError"
Cohesion: 0.40
Nodes (5): BridgeRoundOutboxError, corrupt, .errorDescription, flushAlreadyRunning, unavailable

### Community 176 - "run-tests.sh"
Cohesion: 0.70
Nodes (4): fail(), pass(), say(), run-tests.sh script

### Community 177 - "WHOOP reverse-engineering repos (reference)"
Cohesion: 0.40
Nodes (5): Cloud / credential-replay (not recommended here), Start here by strap generation, Suggested integration into this project, What to copy for golf swing detection, WHOOP reverse-engineering repos (reference)

## Knowledge Gaps
- **917 isolated node(s):** `.isValid`, `.isComplete`, `remain`, `review`, `advance` (+912 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Foundation` to `GolfRound`, `Sendable`, `WatchSessionImporter`, `GolfRoundModelTests`, `SensorModeCoordinator.swift`, `SwingDetectorTests`, `IMUMotionManager`, `GolfCourseLocator`, `RoundLocationCorrelation`, `String`, `MotionFixture`, `String`, `SwiftUI`, `WhoopFraming`, `SessionModel`, `UInt8`, `IngestSettings`, `SessionModel`, `IngestSettings`, `WatchSessionReceiver.swift`, `SwingPathClass`, `WatchWristMount`, `Whoop5DiscoveryScanner`, `BridgeRoundPayload`, `WhoopMotionReviewView`, `WhoopBridgeClient`, `AutomaticHoleTransitionEngine.swift`, `GolfHoleGreenTargets`, `.analyse`, `.cue`, `.interval`, `XCTest`, `WatchLiveFace`, `WhoopCommand`, `WhoopCommand`, `IMUMotionManager`, `Sample`, `.fallbackURL`?**
  _High betweenness centrality (0.080) - this node is a cross-community bridge._
- **Why does `AppModel` connect `AppModel` to `WatchSessionImporter`, `GolfRoundModelTests`, `CourseLookupState`, `LiveRoundView`, `AdaptiveSensorPlan`, `TrendsView.swift`, `IMUMotionManager`, `GolfCourseLocator`, `WhoopBLEManager`, `MotionFixture`, `View`, `String`, `SwiftUI`, `SettingsView`, `WhoopMotionImportService`, `WhoopHeartRateProvider`, `WatchWristMount`, `Foundation`, `Whoop5DiscoveryScanner`, `RoundFileStore`, `WhoopMotionReviewView`, `WatchSessionReceiver`, `BridgeRoundOutbox`, `ReceivedWatchSession`, `RoundRecorder`?**
  _High betweenness centrality (0.058) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `WatchSessionImporter`, `GolfRoundModelTests`, `AppModel`, `IMUMotionManager`, `WhoopBLEManager`, `String`, `MotionFixture`, `WhoopFraming`, `SessionModel`, `UInt8`, `SessionModel`, `WhoopMotionImportService`, `WhoopBLEManager`, `BridgePairingClient`, `BridgeRoundPayload`, `String`, `BridgeHTTPResult`, `.testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely`, `BridgeConfiguration`, `ReceivedWatchSession`, `WatchSessionTransfer`, `.decode`, `Sample`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **What connects `.isValid`, `.isComplete`, `remain` to the rest of the system?**
  _917 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CodingKeys` be split into smaller, more focused modules?**
  _Cohesion score 0.021505376344086023 - nodes in this community are weakly interconnected._
- **Should `GolfRound` be split into smaller, more focused modules?**
  _Cohesion score 0.05388151174668029 - nodes in this community are weakly interconnected._
- **Should `Sendable` be split into smaller, more focused modules?**
  _Cohesion score 0.07120253164556962 - nodes in this community are weakly interconnected._
import CoreLocation
import Foundation
import XCTest
@testable import WhoopGolf

final class CoreModelTests: XCTestCase {
    func testParsesEightBitHeartRateAndRRIntervals() {
        let data = Data([0x10, 72, 0x00, 0x04, 0x00, 0x02])
        let reading = HeartRateMeasurementParser.parse(data)
        XCTAssertEqual(reading?.beatsPerMinute, 72)
        XCTAssertEqual(reading?.rrIntervalsSeconds, [1.0, 0.5])
    }

    func testParsesSixteenBitHeartRate() {
        let data = Data([0x01, 180, 0])
        XCTAssertEqual(HeartRateMeasurementParser.parse(data)?.beatsPerMinute, 180)
    }

    func testRejectsInvalidHeartRate() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0x00, 0x00])))
    }

    func testWhoop5ArmingTimeoutSurfacesDelayedImportNotLiveHang() {
        XCTAssertEqual(
            WhoopLiveIMUPolicy.timeoutMessage(
                generation: .whoop5,
                receivedFrames: 3,
                decodedSamples: 0
            ),
            WhoopLiveIMUPolicy.delayedImportHint
        )
        XCTAssertEqual(
            WhoopLiveIMUPolicy.historicalOffloadResult(sampleCount: 0),
            WhoopLiveIMUPolicy.delayedImportHint
        )
        XCTAssertTrue(
            WhoopLiveIMUPolicy.historicalOffloadResult(sampleCount: 100)
                .contains("Historical BLE delivered 100 samples")
        )
        XCTAssertEqual(
            WhoopLiveIMUPolicy.liveStatus(sampleCount: 240),
            "IMU live · 240 samples"
        )
        XCTAssertTrue(WhoopCommands.enableIMUStream(generation: .whoop5).isEmpty)
        XCTAssertEqual(WhoopLiveIMUPolicy.handshakeTimeoutSeconds, 6)
        let handshake = WhoopCommands.connectHandshake(generation: .whoop5)
        let parsed = handshake.compactMap {
            WhoopFraming.parse([UInt8]($0), generation: .whoop5)
        }
        XCTAssertTrue(parsed.contains { $0.cmd == WhoopCommand.getDataRange.rawValue })
        XCTAssertFalse(parsed.contains { $0.cmd == WhoopCommand.toggleIMU.rawValue })
        XCTAssertEqual(parsed.filter { $0.cmd == WhoopCommand.getHelloHarvard.rawValue }.count, 0)
    }

    func testWhoop5DecoderDropsCommandResponsesAndAcceptsHistoricalLayout() {
        XCTAssertTrue(
            WhoopIMUDecoder.samples(
                from: WhoopFrame(
                    generation: .whoop5,
                    type: WhoopPacketType.commandResponse.rawValue,
                    seq: 1,
                    cmd: WhoopCommand.toggleIMU.rawValue,
                    payload: [0x01]
                ),
                baseTime: 0
            ).isEmpty
        )

        var payload = [UInt8](repeating: 0, count: 20 + 600)
        payload[1] = 0x15
        payload[20] = 0x00
        payload[21] = 0x10
        let historical = WhoopIMUDecoder.samples(
            from: WhoopFrame(
                generation: .whoop5,
                type: WhoopPacketType.historicalIMUStream.rawValue,
                seq: 2,
                cmd: 0,
                payload: payload
            ),
            baseTime: 1
        )
        XCTAssertEqual(historical.count, 100)
        XCTAssertGreaterThan(historical[0].magnitudeG, 0)

        var untagged = [UInt8](repeating: 0, count: 20 + 600)
        untagged[20] = 0x00
        untagged[21] = 0x10
        let untaggedHistorical = WhoopIMUDecoder.samples(
            from: WhoopFrame(
                generation: .whoop5,
                type: WhoopPacketType.historicalIMUStream.rawValue,
                seq: 3,
                cmd: 0,
                payload: untagged
            ),
            baseTime: 1
        )
        XCTAssertEqual(untaggedHistorical.count, 100)
    }

    func testShotDisplacementAndUncertainty() throws {
        let first = fix(latitude: 40.0000, longitude: -75.0000, accuracy: 4)
        let second = fix(latitude: 40.0010, longitude: -75.0000, accuracy: 3)
        let yards = try XCTUnwrap(ShotDistanceCalculator.displacementYards(from: first, to: second))
        XCTAssertEqual(yards, 121.6, accuracy: 0.8)
        XCTAssertEqual(ShotDistanceCalculator.uncertaintyYards(first: first, second: second), 5.47, accuracy: 0.02)
    }

    func testPoorGPSDoesNotProducePreciseDistance() {
        let first = fix(latitude: 40, longitude: -75, accuracy: 30)
        let second = fix(latitude: 40.001, longitude: -75, accuracy: 3)
        XCTAssertNil(ShotDistanceCalculator.displacementYards(from: first, to: second))
    }

    func testReadinessSnapshotRejectsHostileOutOfRangeNumbers() {
        let response = DayResponse(
            apiVersion: 1,
            date: "2026-08-12",
            generatedAt: .now,
            freshness: .init(lastCompleteSyncAt: .now, stale: false, staleAfterSeconds: 21_600),
            physiology: .init(
                status: "scored",
                recoveryPercent: Double.greatestFiniteMagnitude,
                hrvRmssdMs: 75,
                restingHeartRateBpm: 50,
                spo2Percent: 98,
                skinTemperatureCelsius: 33,
                sleepHours: -1,
                sleepPerformancePercent: 90,
                sleepEfficiencyPercent: 90,
                dayStrain: 10_000,
                priorDayStrain: 8,
                provenance: apiProvenance(kind: "providerData")
            ),
            golfReadiness: .init(
                available: true,
                score: Double.greatestFiniteMagnitude,
                verdict: String(repeating: "x", count: 100),
                personalised: false,
                components: [],
                advice: ["unsafe\u{0000}text"],
                reason: nil,
                provenance: apiProvenance(kind: "derivedAnalysis")
            )
        )

        let snapshot = ReadinessSnapshot.from(response)

        XCTAssertNil(snapshot.score)
        XCTAssertNil(snapshot.recoveryPercent)
        XCTAssertNil(snapshot.sleepHours)
        XCTAssertNil(snapshot.dayStrain)
        XCTAssertEqual(snapshot.verdict.count, 64)
        XCTAssertEqual(
            snapshot.advice,
            "Not enough cached WHOOP inputs to calculate golf readiness."
        )
    }

    private func apiProvenance(kind: String) -> DayResponse.APIProvenance {
        DayResponse.APIProvenance(
            kind: kind,
            provider: kind == "providerData" ? "WHOOP" : nil,
            source: kind == "providerData" ? "localSqliteCache" : nil,
            producer: kind == "derivedAnalysis" ? "whoop-18birdies" : nil,
            model: kind == "derivedAnalysis" ? "golf-readiness-v1" : nil,
            isWhoopMetric: kind == "derivedAnalysis" ? false : nil,
            note: nil
        )
    }
}

@MainActor
final class LocationRoundServiceAuthorizationTests: XCTestCase {
    func testFirstPermissionStepRequestsOnlyWhenInUse() {
        let manager = TestLocationManager(status: .notDetermined)
        let context = makeService(manager: manager)
        defer { context.cleanup() }

        context.service.requestWhenInUsePermission()

        XCTAssertEqual(context.service.permissionState, .requestingWhenInUse)
        XCTAssertEqual(manager.whenInUseRequestCount, 1)
        XCTAssertEqual(manager.alwaysRequestCount, 0)
        XCTAssertEqual(manager.startUpdateCount, 0)
        XCTAssertEqual(manager.oneShotRequestCount, 0)
    }

    func testAlwaysActionStillRequestsWhenInUseFirstWhenUndetermined() {
        let manager = TestLocationManager(status: .notDetermined)
        let context = makeService(manager: manager)
        defer { context.cleanup() }

        context.service.requestAlwaysPermission()

        XCTAssertEqual(manager.whenInUseRequestCount, 1)
        XCTAssertEqual(manager.alwaysRequestCount, 0)
        XCTAssertEqual(context.service.permissionState, .requestingWhenInUse)
    }

    func testAlwaysRequiresSeparateActionAndThenUsesSettingsRepair() {
        let manager = TestLocationManager(status: .authorizedWhenInUse)
        let context = makeService(manager: manager)
        defer { context.cleanup() }

        context.service.requestWhenInUsePermission()
        XCTAssertEqual(manager.alwaysRequestCount, 0)
        XCTAssertEqual(context.service.permissionState, .whenInUse)

        context.service.requestAlwaysPermission()
        XCTAssertEqual(manager.alwaysRequestCount, 1)
        XCTAssertEqual(context.service.permissionState, .requestingAlways)

        context.service.requestAlwaysPermission()
        XCTAssertEqual(manager.alwaysRequestCount, 1)
        XCTAssertEqual(context.service.permissionState, .whenInUseNeedsSettings)
    }

    func testPermissionCallbackNeverChainsIntoAlwaysRequest() {
        let manager = TestLocationManager(status: .notDetermined)
        let context = makeService(manager: manager)
        defer { context.cleanup() }
        context.service.requestWhenInUsePermission()

        manager.testAuthorizationStatus = .authorizedWhenInUse
        context.service.locationManagerDidChangeAuthorization(manager)

        XCTAssertEqual(context.service.permissionState, .whenInUse)
        XCTAssertEqual(manager.alwaysRequestCount, 0)
        XCTAssertEqual(manager.startUpdateCount, 0)
        XCTAssertEqual(manager.oneShotRequestCount, 0)
    }

    func testContinuousUpdatesRequirePersistedActiveRound() async {
        let manager = TestLocationManager(status: .authorizedAlways)
        let context = makeService(manager: manager)
        defer { context.cleanup() }

        context.service.refreshPermissionState()
        XCTAssertEqual(context.service.permissionState, .always)
        XCTAssertEqual(manager.startUpdateCount, 0)

        context.service.startRoundTracking()
        XCTAssertEqual(manager.startUpdateCount, 0)
        XCTAssertNil(context.service.activeRoundID)

        let roundID = UUID()
        context.service.startRoundTracking(roundID: roundID)
        XCTAssertEqual(manager.startUpdateCount, 1)
        XCTAssertEqual(context.service.activeRoundID, roundID)

        context.service.stopRoundTracking(roundID: roundID)
        XCTAssertEqual(manager.stopUpdateCount, 1)
        XCTAssertNil(context.service.activeRoundID)
        _ = try? await context.service.estimatedLocation(roundID: roundID, at: .now)
    }

    func testAuthorizedAccessOutsideRoundUsesOneShotNotContinuousTracking() {
        let manager = TestLocationManager(status: .authorizedAlways)
        let context = makeService(manager: manager)
        defer { context.cleanup() }

        context.service.requestPermission()

        XCTAssertEqual(manager.oneShotRequestCount, 1)
        XCTAssertEqual(manager.startUpdateCount, 0)
        XCTAssertNil(context.service.activeRoundID)
    }

    private func makeService(manager: TestLocationManager) -> LocationTestContext {
        let identifier = "LocationRoundServiceAuthorizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(identifier, isDirectory: true)
        let service = LocationRoundService(
            journal: RoundLocationJournal(directory: directory),
            managerFactory: { manager },
            defaults: defaults
        )
        return LocationTestContext(
            service: service,
            cleanup: {
                defaults.removePersistentDomain(forName: identifier)
                try? FileManager.default.removeItem(at: directory)
            }
        )
    }
}

@MainActor
private struct LocationTestContext {
    let service: LocationRoundService
    let cleanup: () -> Void
}

@MainActor
private final class TestLocationManager: CLLocationManager {
    var testAuthorizationStatus: CLAuthorizationStatus
    var testAccuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    private(set) var whenInUseRequestCount = 0
    private(set) var alwaysRequestCount = 0
    private(set) var oneShotRequestCount = 0
    private(set) var startUpdateCount = 0
    private(set) var stopUpdateCount = 0

    init(status: CLAuthorizationStatus) {
        testAuthorizationStatus = status
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { testAuthorizationStatus }
    override var accuracyAuthorization: CLAccuracyAuthorization { testAccuracyAuthorization }

    override func requestWhenInUseAuthorization() {
        whenInUseRequestCount += 1
    }

    override func requestAlwaysAuthorization() {
        alwaysRequestCount += 1
    }

    override func requestLocation() {
        oneShotRequestCount += 1
    }

    override func startUpdatingLocation() {
        startUpdateCount += 1
    }

    override func stopUpdatingLocation() {
        stopUpdateCount += 1
    }
}

final class GolfRoundModelTests: XCTestCase {
    func testFreshRoundHasNoFabricatedScore() {
        let round = GolfRound(courseName: "No Score", holeCount: .nine)

        XCTAssertEqual(round.lifecycle, .draft)
        XCTAssertNil(round.currentStrokes)
        XCTAssertEqual(round.scoredHoleCount, 0)
        XCTAssertEqual(round.parredHoleCount, 0)
        XCTAssertNil(round.enteredStrokes)
        XCTAssertNil(round.grossScore)
        XCTAssertNil(round.totalPar)
        XCTAssertNil(round.runningScoreToPar)
        XCTAssertNil(round.scoreToPar)
        XCTAssertFalse(round.isScoreComplete)
    }

    func testNineHoleScorecardComputesGrossParAndScoreToPar() {
        let holes = (1...9).map { number in
            HoleResult(number: number, par: 4, strokes: number == 1 ? 5 : 4)
        }
        let round = GolfRound(
            courseName: "Nine Hole Test",
            holeCount: .nine,
            holes: holes
        )

        XCTAssertEqual(round.grossScore, 37)
        XCTAssertEqual(round.totalPar, 36)
        XCTAssertEqual(round.scoreToPar, 1)
        XCTAssertEqual(round.runningScoreToPar, 1)
        XCTAssertEqual(round.scoredHoleCount, 9)
        XCTAssertTrue(round.isScoreComplete)
    }

    func testPartialScorecardHasRunningButNoOfficialScore() {
        var round = GolfRound(courseName: "Partial", holeCount: .nine)
        XCTAssertTrue(round.adjustCurrentPar(by: 1))
        XCTAssertTrue(round.adjustCurrentStrokes(by: 1))
        for _ in 0..<4 {
            XCTAssertTrue(round.adjustCurrentStrokes(by: 1))
        }

        XCTAssertEqual(round.currentStrokes, 5)
        XCTAssertEqual(round.enteredStrokes, 5)
        XCTAssertEqual(round.runningScoreToPar, 1)
        XCTAssertNil(round.grossScore)
        XCTAssertNil(round.scoreToPar)
    }

    func testAllStrokesWithoutParsHasGrossButNoOfficialScoreToPar() {
        let holes = (1...9).map { HoleResult(number: $0, par: nil, strokes: 5) }
        let round = GolfRound(
            courseName: "Unknown Pars",
            holeCount: .nine,
            holes: holes
        )

        XCTAssertTrue(round.hasCompleteStrokes)
        XCTAssertFalse(round.hasCompletePars)
        XCTAssertEqual(round.grossScore, 45)
        XCTAssertNil(round.totalPar)
        XCTAssertNil(round.scoreToPar)
        XCTAssertFalse(round.isScoreComplete)
    }

    func testFinishChangesExplicitLifecycle() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var round = GolfRound(courseName: "Lifecycle")

        round.markFinished(at: end)

        XCTAssertTrue(round.isFinished)
        XCTAssertEqual(round.lifecycle, .finished)
        XCTAssertEqual(round.endedAt, end)
    }

    func testRoundKeepsRecorderAndStartTimeZoneForStableLocalDate() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-08-13T02:30:00Z"))
        let round = GolfRound(
            courseName: "Travel Round",
            startedAt: start,
            holeCount: .nine,
            recordingDevice: .appleWatch,
            timeZoneIdentifier: "America/New_York"
        )

        XCTAssertEqual(round.recordingDevice, .appleWatch)
        XCTAssertEqual(round.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(round.localDate, "2026-08-12")
    }

    func testHybridRecorderRoundTripsWithoutLosingSensorOwnership() throws {
        let round = GolfRound(
            courseName: "Hybrid Round",
            recordingDevice: .hybrid
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(GolfRound.self, from: encoder.encode(round))

        XCTAssertEqual(decoded.recordingDevice, .hybrid)
        XCTAssertEqual(decoded.recordingDevice.adaptiveSensorMode, .hybrid)
        XCTAssertEqual(decoded.recordingDevice.displayName, "Hybrid · Apple Watch + WHOOP 5")
    }

    func testFreshAndMigratedRoundsStartHoleTimelineAtRoundStart() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = GolfRound(courseName: "Timeline", startedAt: started, holeCount: .nine)

        XCTAssertEqual(
            fresh.holeTransitions,
            [HoleTransition(sequence: 1, hole: 1, transitionedAt: started)]
        )

        let fixture = LegacyRoundFixture(
            id: UUID(),
            courseName: "Legacy Timeline",
            startedAt: started,
            endedAt: started.addingTimeInterval(3_600),
            currentHole: 5,
            currentPar: 4,
            scoreToPar: 0,
            shots: [],
            swings: [],
            notes: ""
        )
        let migrated = try decodeLegacy(fixture)

        XCTAssertEqual(migrated.schemaVersion, 4)
        XCTAssertEqual(
            migrated.holeTransitions,
            [HoleTransition(sequence: 1, hole: 1, transitionedAt: started)]
        )
    }

    func testHoleTimelineUsesLatestTransitionIncludingBoundaryAndDoubleBack() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let swingOne = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(9))
        let swingBoundary = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(10))
        let swingDoubleBack = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(20))
        var round = GolfRound(
            courseName: "Timeline",
            startedAt: started,
            holeCount: .nine,
            swings: [swingOne, swingBoundary, swingDoubleBack]
        )

        XCTAssertTrue(round.moveHole(by: 1, at: started.addingTimeInterval(10)))
        XCTAssertTrue(round.moveHole(by: 1, at: started.addingTimeInterval(15)))
        XCTAssertTrue(round.moveHole(by: -1, at: started.addingTimeInterval(20)))

        XCTAssertEqual(round.holeAssignment(for: swingOne.id)?.hole, 1)
        XCTAssertEqual(round.holeAssignment(for: swingBoundary.id)?.hole, 2)
        XCTAssertEqual(round.holeAssignment(for: swingDoubleBack.id)?.hole, 2)
        XCTAssertEqual(round.holeTransitions.map(\.hole), [1, 2, 3, 2])
    }

    func testTimelineHonorsRoundStartAndEndBoundaries() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(60)
        let before = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(-0.001))
        let atStart = testSwing(id: UUID(), capturedAt: started)
        let atEnd = testSwing(id: UUID(), capturedAt: ended)
        let after = testSwing(id: UUID(), capturedAt: ended.addingTimeInterval(0.001))
        let round = GolfRound(
            courseName: "Boundaries",
            startedAt: started,
            endedAt: ended,
            lifecycle: .finished,
            holeCount: .nine,
            swings: [before, atStart, atEnd, after]
        )

        XCTAssertEqual(round.holeAssignment(for: before.id)?.method, .unavailable)
        XCTAssertEqual(round.holeAssignment(for: atStart.id)?.hole, 1)
        XCTAssertEqual(round.holeAssignment(for: atEnd.id)?.hole, 1)
        XCTAssertEqual(round.holeAssignment(for: after.id)?.method, .unavailable)
    }

    func testManualCorrectionPrecedesTimelineAndSupportsExplicitUnassignment() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let swing = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(30))
        var round = GolfRound(
            courseName: "Correction",
            startedAt: started,
            holeCount: .nine,
            swings: [swing]
        )

        XCTAssertTrue(round.moveHole(by: 1, at: started.addingTimeInterval(10)))
        XCTAssertEqual(round.holeAssignment(for: swing.id)?.hole, 2)
        XCTAssertEqual(round.holeAssignment(for: swing.id)?.method, .roundTimeline)

        XCTAssertTrue(round.setSwingHoleCorrection(
            swingID: swing.id,
            hole: 6,
            at: started.addingTimeInterval(40)
        ))
        XCTAssertEqual(round.holeAssignment(for: swing.id)?.hole, 6)
        XCTAssertEqual(round.holeAssignment(for: swing.id)?.method, .manualCorrection)

        XCTAssertTrue(round.setSwingHoleCorrection(
            swingID: swing.id,
            hole: nil,
            at: started.addingTimeInterval(50)
        ))
        XCTAssertNil(round.holeAssignment(for: swing.id)?.hole)
        XCTAssertEqual(round.holeAssignment(for: swing.id)?.method, .manualUnassignment)
        XCTAssertEqual(round.swingHoleCorrections.count, 2)
    }

    func testAssignmentRejectsInvalidSwingHoleAndNonMonotonicTransition() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let swing = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(30))
        var round = GolfRound(
            courseName: "Validation",
            startedAt: started,
            holeCount: .nine,
            swings: [swing]
        )

        XCTAssertFalse(round.setSwingHoleCorrection(swingID: UUID(), hole: 1))
        XCTAssertFalse(round.setSwingHoleCorrection(swingID: swing.id, hole: 10))
        XCTAssertFalse(round.moveHole(by: 1, at: started.addingTimeInterval(-1)))
        XCTAssertTrue(round.moveHole(by: 1, at: started.addingTimeInterval(20)))
        XCTAssertFalse(round.moveHole(by: 1, at: started.addingTimeInterval(19)))
        XCTAssertNil(round.holeAssignment(for: UUID()))
    }

    func testTimelineAndCorrectionPersistThroughModelEncoding() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let swing = testSwing(id: UUID(), capturedAt: started.addingTimeInterval(30))
        var round = GolfRound(
            courseName: "Persistence",
            startedAt: started,
            holeCount: .nine,
            swings: [swing]
        )
        XCTAssertTrue(round.moveHole(by: 1, at: started.addingTimeInterval(20)))
        XCTAssertTrue(round.setSwingHoleCorrection(
            swingID: swing.id,
            hole: 4,
            at: started.addingTimeInterval(40)
        ))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GolfRound.self, from: encoder.encode(round))

        XCTAssertEqual(decoded.holeTransitions, round.holeTransitions)
        XCTAssertEqual(decoded.swingHoleCorrections, round.swingHoleCorrections)
        XCTAssertEqual(decoded.holeAssignment(for: swing.id)?.hole, 4)
    }

    private func testSwing(id: UUID, capturedAt: Date) -> GolfSwingMetrics {
        GolfSwingMetrics(
            id: id,
            capturedAt: capturedAt,
            peakG: 4.2,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: capturedAt,
                receivedAt: capturedAt,
                quality: .estimated
            )
        )
    }

    func testV1RoundMigratesWithoutTreatingDefaultZeroAsScore() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(14_400)
        let fixture = LegacyRoundFixture(
            id: UUID(),
            courseName: "Legacy Course",
            startedAt: started,
            endedAt: ended,
            currentHole: 7,
            currentPar: 5,
            scoreToPar: 0,
            shots: [],
            swings: [],
            notes: "v1"
        )

        let round = try decodeLegacy(fixture)

        XCTAssertEqual(round.schemaVersion, GolfRound.currentSchemaVersion)
        XCTAssertEqual(round.lifecycle, .finished)
        XCTAssertEqual(round.holeCount, .eighteen)
        XCTAssertEqual(round.recordingDevice, .iphone)
        XCTAssertEqual(round.currentHole, 7)
        XCTAssertNil(round.currentPar)
        XCTAssertEqual(round.legacyScoreToPar, 0)
        XCTAssertNil(round.scoreToPar)
        XCTAssertFalse(round.isScoreComplete)
    }

    func testV1ShotSegmentMovesToOriginatingShotAndDropsCrossHoleDistance() throws {
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let location = fix(latitude: 40, longitude: -75, accuracy: 4, capturedAt: captured)
        let fixture = LegacyRoundFixture(
            id: UUID(),
            courseName: "Legacy Shots",
            startedAt: captured,
            endedAt: nil,
            currentHole: 2,
            currentPar: 4,
            scoreToPar: 3,
            shots: [
                LegacyShotFixture(
                    id: UUID(),
                    sequence: 1,
                    hole: 1,
                    capturedAt: captured,
                    location: location,
                    displacementFromPreviousYards: nil,
                    uncertaintyYards: nil
                ),
                LegacyShotFixture(
                    id: UUID(),
                    sequence: 2,
                    hole: 1,
                    capturedAt: captured.addingTimeInterval(60),
                    location: location,
                    displacementFromPreviousYards: 121,
                    uncertaintyYards: 6
                ),
                LegacyShotFixture(
                    id: UUID(),
                    sequence: 3,
                    hole: 2,
                    capturedAt: captured.addingTimeInterval(120),
                    location: location,
                    displacementFromPreviousYards: 400,
                    uncertaintyYards: 8
                ),
            ],
            swings: [],
            notes: ""
        )

        let round = try decodeLegacy(fixture)

        XCTAssertEqual(round.lifecycle, .draft)
        XCTAssertEqual(round.shots[0].distanceToNextYards, 121)
        XCTAssertEqual(round.shots[0].distanceUncertaintyYards, 6)
        XCTAssertNil(round.shots[1].distanceToNextYards)
        XCTAssertNil(round.shots[2].distanceToNextYards)
    }

    private func decodeLegacy(_ fixture: LegacyRoundFixture) throws -> GolfRound {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GolfRound.self, from: encoder.encode(fixture))
    }
}

final class RoundFileStoreTests: XCTestCase {
    func testDraftIsResumableButExcludedFromHistoryUntilFinished() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundFileStore(directory: directory)

        var round = GolfRound(courseName: "Test Course", holeCount: .nine)
        try await store.save(round)

        var snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.activeDraft?.id, round.id)
        XCTAssertEqual(snapshot.additionalDraftCount, 0)
        XCTAssertTrue(snapshot.finishedRounds.isEmpty)
        let draftOnlyHistory = try await store.finishedRounds()
        XCTAssertTrue(draftOnlyHistory.isEmpty)

        XCTAssertTrue(round.adjustCurrentStrokes(by: 1))
        try await store.save(round)
        let updatedDraft = try await store.snapshot().activeDraft
        XCTAssertEqual(updatedDraft?.currentStrokes, 1)

        round.markFinished(at: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.save(round)
        snapshot = try await store.snapshot()
        XCTAssertNil(snapshot.activeDraft)
        XCTAssertEqual(snapshot.finishedRounds.map(\.id), [round.id])
        let finishedHistory = try await store.finishedRounds()
        XCTAssertEqual(finishedHistory.map(\.id), [round.id])
    }

    func testMostRecentDraftIsRestoredAndOlderDraftsStayOutOfHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundFileStore(directory: directory)
        let older = GolfRound(
            courseName: "Older",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = GolfRound(
            courseName: "Newer",
            startedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        try await store.save(older)
        try await store.save(newer)

        let snapshot = try await store.snapshot()

        XCTAssertEqual(snapshot.activeDraft?.id, newer.id)
        XCTAssertEqual(snapshot.additionalDraftCount, 1)
        XCTAssertTrue(snapshot.finishedRounds.isEmpty)
        let history = try await store.finishedRounds()
        XCTAssertTrue(history.isEmpty)
    }

    func testCorruptRoundIsQuarantinedWithoutErasingValidRound() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundFileStore(directory: directory)
        var valid = GolfRound(courseName: "Valid")
        valid.markFinished()
        try await store.save(valid)

        let roundsDirectory = directory.appendingPathComponent("Rounds", isDirectory: true)
        try Data("not-json".utf8).write(
            to: roundsDirectory.appendingPathComponent("broken.json"),
            options: .atomic
        )

        let loaded = try await store.rounds()
        XCTAssertEqual(loaded.map(\.courseName), ["Valid"])
        let quarantine = directory.appendingPathComponent("Quarantine", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: quarantine.path).count, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WhoopGolfTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct LegacyRoundFixture: Encodable {
    let id: UUID
    let courseName: String
    let startedAt: Date
    let endedAt: Date?
    let currentHole: Int
    let currentPar: Int
    let scoreToPar: Int
    let shots: [LegacyShotFixture]
    let swings: [GolfSwingMetrics]
    let notes: String
}

private struct LegacyShotFixture: Encodable {
    let id: UUID
    let sequence: Int
    let hole: Int
    let capturedAt: Date
    let location: LocationFix
    let displacementFromPreviousYards: Double?
    let uncertaintyYards: Double?
}

private func fix(
    latitude: Double,
    longitude: Double,
    accuracy: Double,
    capturedAt: Date = .now
) -> LocationFix {
    LocationFix(
        latitude: latitude,
        longitude: longitude,
        altitudeMeters: nil,
        horizontalAccuracyMeters: accuracy,
        capturedAt: capturedAt,
        provenance: DataProvenance(
            source: .iphoneGPS,
            observedAt: capturedAt,
            quality: .verified
        )
    )
}

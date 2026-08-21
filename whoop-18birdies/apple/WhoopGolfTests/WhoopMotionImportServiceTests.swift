import CryptoKit
import Foundation
import XCTest
@testable import WhoopGolf

final class WhoopMotionTransferModelTests: XCTestCase {
    func testEnvelopeRecomputesEventIdentityAndRejectsUnknownFields() throws {
        let fixture = try MotionFixture()
        let data = try fixture.encodedEnvelope()
        let decoded = try fixture.decoder.decode(WhoopMotionEnvelope.self, from: data)

        XCTAssertEqual(decoded.roundID, fixture.roundID)
        XCTAssertEqual(decoded.events.first?.eventID, fixture.acceptedEvent.eventID)
        XCTAssertEqual(decoded.events.first?.swingUUID.version, 8)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["rawFrames"] = [["x": 1, "y": 2, "z": 3]]
        let unsafe = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try fixture.decoder.decode(WhoopMotionEnvelope.self, from: unsafe))
    }

    func testEnvelopeRejectsIdentityTimestampEnumAndDuplicateViolations() throws {
        let fixture = try MotionFixture()
        let valid = try fixture.encodedEnvelope()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var events = try XCTUnwrap(root["events"] as? [[String: Any]])

        events[0]["eventID"] = String(repeating: "0", count: 64)
        root["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        )

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        events = try XCTUnwrap(root["events"] as? [[String: Any]])
        events[0]["observedAt"] = "2026-08-12T12:00:00.999Z"
        root["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        )

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        events = try XCTUnwrap(root["events"] as? [[String: Any]])
        var classification = try XCTUnwrap(events[0]["classification"] as? [String: Any])
        classification["decision"] = "definitelySwing"
        events[0]["classification"] = classification
        root["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        )

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        events = try XCTUnwrap(root["events"] as? [[String: Any]])
        events.append(events[0])
        root["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        )
    }

    func testMotionRequestUsesExactSchemaAndBoundsRoundDuration() throws {
        let roundID = UUID()
        let start = Date(timeIntervalSince1970: 1_786_536_000)
        let request = try WhoopMotionRequest(
            roundID: roundID,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            requestedAt: start.addingTimeInterval(61)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), Set([
            "apiVersion", "schemaVersion", "roundID", "startedAt", "endedAt", "requestedAt"
        ]))
        XCTAssertThrowsError(
            try WhoopMotionRequest(
                roundID: roundID,
                startedAt: start,
                endedAt: start.addingTimeInterval(59),
                requestedAt: start
            )
        )
    }

    func testSchemaV1ForbidsWristAnalysisKeyIncludingExplicitNull() throws {
        let fixture = try MotionFixture()
        let v1Data = try fixture.encodedEnvelope()
        var v1 = try XCTUnwrap(JSONSerialization.jsonObject(with: v1Data) as? [String: Any])
        var events = try XCTUnwrap(v1["events"] as? [[String: Any]])

        events[0]["wristAnalysis"] = NSNull()
        v1["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: v1)
            )
        )

        let v2 = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.encodedV2Envelope()) as? [String: Any]
        )
        let v2Events = try XCTUnwrap(v2["events"] as? [[String: Any]])
        events[0]["wristAnalysis"] = try XCTUnwrap(v2Events[0]["wristAnalysis"])
        v1["events"] = events
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: v1)
            )
        )
    }

    func testSchemaV2RequiresAnalysisAndRoundTripsItsTrace() throws {
        let fixture = try MotionFixture()
        let v1Data = try fixture.encodedEnvelope()
        var missing = try XCTUnwrap(JSONSerialization.jsonObject(with: v1Data) as? [String: Any])
        missing["schemaVersion"] = 2
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: missing)
            )
        )

        var explicitNull = missing
        var nullEvents = try XCTUnwrap(explicitNull["events"] as? [[String: Any]])
        nullEvents[0]["wristAnalysis"] = NSNull()
        explicitNull["events"] = nullEvents
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: explicitNull)
            )
        )

        let validData = try fixture.encodedV2Envelope()
        let decoded = try fixture.decoder.decode(WhoopMotionEnvelope.self, from: validData)
        let trace = try XCTUnwrap(decoded.events.first?.wristAnalysis?.orientationTrace)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(trace.points.map(\.offsetMilliseconds), [-1_000, 0])
        XCTAssertEqual(trace.points.map(\.phase), [.takeaway, .impact])
        XCTAssertEqual(
            try XCTUnwrap(trace.points.last?.orientation.w),
            0.92387953,
            accuracy: 0.000_000_01
        )
        XCTAssertEqual(
            trace.quaternionSemantics,
            "rotatesCurrentWhoopSensorFrameIntoAddressWhoopSensorFrame"
        )

        let roundTripped = try fixture.decoder.decode(
            WhoopMotionEnvelope.self,
            from: fixture.encoder.encode(decoded)
        )
        XCTAssertEqual(roundTripped, decoded)
    }

    func testSchemaV2RejectsInvalidQuaternionAxisAndTraceSemantics() throws {
        let fixture = try MotionFixture()
        let validData = try fixture.encodedV2Envelope()

        var invalidQuaternion = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        try mutateFirstWristAnalysis(in: &invalidQuaternion) { analysis in
            var trace = try XCTUnwrap(analysis["orientationTrace"] as? [String: Any])
            var points = try XCTUnwrap(trace["points"] as? [[String: Any]])
            var orientation = try XCTUnwrap(points[1]["orientation"] as? [String: Any])
            orientation["w"] = 0.1
            points[1]["orientation"] = orientation
            trace["points"] = points
            analysis["orientationTrace"] = trace
        }
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: invalidQuaternion)
            )
        )

        var invalidAxis = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        try mutateFirstWristAnalysis(in: &invalidAxis) { analysis in
            var features = try XCTUnwrap(analysis["features"] as? [String: Any])
            features["dominantAngularAxisSensor"] = ["x": 1.0009, "y": 0, "z": 0]
            analysis["features"] = features
        }
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: invalidAxis)
            )
        )

        var invalidSemantics = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        try mutateFirstWristAnalysis(in: &invalidSemantics) { analysis in
            var trace = try XCTUnwrap(analysis["orientationTrace"] as? [String: Any])
            trace["quaternionSemantics"] = "absoluteWorldOrientation"
            analysis["orientationTrace"] = trace
        }
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: invalidSemantics)
            )
        )

        var invalidTimeline = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        try mutateFirstWristAnalysis(in: &invalidTimeline) { analysis in
            var trace = try XCTUnwrap(analysis["orientationTrace"] as? [String: Any])
            var points = try XCTUnwrap(trace["points"] as? [[String: Any]])
            points[1]["offsetMilliseconds"] = -1_000
            trace["points"] = points
            analysis["orientationTrace"] = trace
        }
        XCTAssertThrowsError(
            try fixture.decoder.decode(
                WhoopMotionEnvelope.self,
                from: JSONSerialization.data(withJSONObject: invalidTimeline)
            )
        )
    }

    private func mutateFirstWristAnalysis(
        in root: inout [String: Any],
        _ mutate: (inout [String: Any]) throws -> Void
    ) throws {
        var events = try XCTUnwrap(root["events"] as? [[String: Any]])
        var analysis = try XCTUnwrap(events[0]["wristAnalysis"] as? [String: Any])
        try mutate(&analysis)
        events[0]["wristAnalysis"] = analysis
        root["events"] = events
    }
}

final class WhoopMotionImportServiceTests: XCTestCase {
    func testSchemaV2WristAnalysisSurvivesProtectedImport() async throws {
        let fixture = try MotionFixture()
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Wrist Trace Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let payload = try fixture.encodedV2Envelope()
        let expected = try fixture.decoder
            .decode(WhoopMotionEnvelope.self, from: payload)
            .events.first?.wristAnalysis

        let outcome = await importer.importBatch(payload)
        XCTAssertEqual(
            outcome,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 1,
                needsReviewCount: 0
            )
        )
        let savedRounds = try await roundStore.rounds()
        let saved = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(saved.swings.first?.wristAnalysis, expected)
        XCTAssertEqual(
            saved.swings.first?.wristAnalysis?.orientationTrace?.points.last?.phase,
            .impact
        )
    }

    func testAcceptedEventsImportWithLocalGPSAndLeaveLastIntervalPending() async throws {
        let fixture = try MotionFixture(includeSecondAcceptedEvent: true, includeNeedsReviewEvent: true)
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Protected Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let correlator = RecordingMotionCorrelator()
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: correlator,
            storageDirectory: directories.imports,
            now: { Date(timeIntervalSince1970: 1_786_550_000) }
        )

        let outcome = await importer.importBatch(try fixture.encodedEnvelope())
        XCTAssertEqual(
            outcome,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 2,
                needsReviewCount: 1
            )
        )
        let savedRounds = try await roundStore.rounds()
        let saved = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(saved.swings.count, 2)
        XCTAssertTrue(saved.swings.allSatisfy { $0.provenance.source == .whoopMotion })
        XCTAssertTrue(saved.swings.allSatisfy { $0.provenance.quality == .estimated })
        XCTAssertEqual(saved.swings.first?.detectionConfidence, 0.94)
        XCTAssertEqual(saved.swings.first?.locationCorrelationMethod, .interpolatedTimelineFix)
        XCTAssertNotNil(saved.swings.first?.shotInterval)
        XCTAssertNil(saved.swings.last?.shotInterval)
        let calls = await correlator.requests()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.maximumTimeGap == 10 })
        XCTAssertTrue(calls.allSatisfy { $0.maximumHorizontalAccuracy == 25 })

        let pending = try await importer.pendingBatches()
        XCTAssertEqual(pending.map(\.reason), ["needsReviewAfterAcceptedImport"])
        XCTAssertEqual(pending.first?.needsReviewCount, 1)
    }

    func testCrossSourceBatchStaysStagedWhenEventsCannotBeUniquelyReconciled() async throws {
        let fixture = try MotionFixture()
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Protected Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine,
            recordingDevice: .hybrid,
            swings: [
                GolfSwingMetrics(
                    capturedAt: fixture.roundStartedAt.addingTimeInterval(120),
                    peakG: 8,
                    provenance: DataProvenance(
                        source: .appleWatch,
                        observedAt: fixture.roundStartedAt.addingTimeInterval(120),
                        quality: .verified
                    )
                )
            ]
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let data = try fixture.encodedEnvelope()

        let stagedOutcome = await importer.importBatch(data)
        XCTAssertEqual(
            stagedOutcome,
            .stagedCrossSourceConflict(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let stagedRounds = try await roundStore.rounds()
        XCTAssertEqual(stagedRounds.first?.swings.count, 1)

        let mergedOutcome = await importer.importBatch(data, allowingCrossSourceMerge: true)
        XCTAssertEqual(
            mergedOutcome,
            .stagedCrossSourceConflict(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let mergedRounds = try await roundStore.rounds()
        XCTAssertEqual(mergedRounds.first?.swings.count, 1)
    }

    func testHybridUniqueTimestampMatchEnrichesWatchShotWithoutDoubleCounting() async throws {
        let fixture = try MotionFixture()
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        let watchID = UUID()
        let watchTime = fixture.acceptedEvent.observedAt.addingTimeInterval(0.4)
        let watchLocation = SwingLocationObservation(
            latitude: 33.75,
            longitude: -84.39,
            altitudeMeters: 250,
            horizontalAccuracyMeters: 4,
            capturedAt: watchTime,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: watchTime,
                quality: .verified
            )
        )
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Hybrid Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine,
            recordingDevice: .hybrid,
            swings: [
                GolfSwingMetrics(
                    id: watchID,
                    capturedAt: watchTime,
                    peakG: 7.8,
                    provenance: DataProvenance(
                        source: .appleWatch,
                        observedAt: watchTime,
                        quality: .verified
                    ),
                    location: watchLocation,
                    locationCorrelationMethod: .sensorSynchronized
                )
            ]
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )

        let outcome = await importer.importBatch(
            try fixture.encodedEnvelope(),
            allowingCrossSourceMerge: true
        )

        XCTAssertEqual(
            outcome,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 1,
                needsReviewCount: 0
            )
        )
        let savedRounds = try await roundStore.rounds()
        let saved = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(saved.swings.count, 1)
        XCTAssertEqual(saved.swings.first?.id, watchID)
        XCTAssertEqual(saved.swings.first?.provenance.source, .derived)
        XCTAssertTrue(saved.swings.first?.provenance.inputSources.contains(.appleWatch) == true)
        XCTAssertTrue(saved.swings.first?.provenance.inputSources.contains(.whoopMotion) == true)
        XCTAssertEqual(saved.swings.first?.location?.provenance.source, .appleWatch)
    }

    func testRegistryLossRetryCannotDuplicateDeterministicSwing() async throws {
        let fixture = try MotionFixture()
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Protected Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let data = try fixture.encodedEnvelope()
        _ = await importer.importBatch(data)

        try FileManager.default.removeItem(
            at: directories.imports.appendingPathComponent("registry.json")
        )
        _ = await importer.importBatch(data)
        let savedRounds = try await roundStore.rounds()
        let saved = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(saved.swings.count, 1)
        XCTAssertEqual(saved.swings.first?.id, fixture.acceptedEvent.swingUUID)

        let duplicateOutcome = await importer.importBatch(data)
        XCTAssertEqual(
            duplicateOutcome,
            .duplicate(batchID: fixture.batchID, roundID: fixture.roundID)
        )
    }

    func testFractionalRoundTimestampsSurviveProtectedStoreNormalization() async throws {
        let fixture = try MotionFixture(roundBoundaryFraction: 0.789)
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Fractional Boundary Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )

        let fractionalOutcome = await importer.importBatch(try fixture.encodedEnvelope())
        XCTAssertEqual(
            fractionalOutcome,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 1,
                needsReviewCount: 0
            )
        )
    }

    func testMissingGPSStagesThenDeterministicallyRetriesAfterTimelineFlush() async throws {
        let fixture = try MotionFixture()
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Delayed GPS Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let correlator = RecoveringMotionCorrelator()
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: correlator,
            storageDirectory: directories.imports
        )
        let payload = try fixture.encodedEnvelope()

        let staged = await importer.importBatch(payload)
        XCTAssertEqual(
            staged,
            .stagedLocationUnavailable(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let beforeFlush = try await roundStore.rounds()
        XCTAssertTrue(try XCTUnwrap(beforeFlush.first).swings.isEmpty)
        XCTAssertFalse(AppModel.isTerminalMotionImportOutcome(staged))

        await correlator.makeTimelineAvailable()
        let imported = await importer.importBatch(payload)
        XCTAssertEqual(
            imported,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 1,
                needsReviewCount: 0
            )
        )
        XCTAssertTrue(AppModel.isTerminalMotionImportOutcome(imported))
        let afterFlush = try await roundStore.rounds()
        let saved = try XCTUnwrap(afterFlush.first)
        XCTAssertEqual(saved.swings.count, 1)
        XCTAssertNotNil(saved.swings.first?.location)
    }

    @MainActor
    func testLocationServiceDrainsQueuedJournalWritesBeforeCorrelation() async throws {
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let journal = RoundLocationJournal(directory: directories.root.appendingPathComponent("GPS"))
        let service = LocationRoundService(journal: journal)
        let roundID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_786_536_600)
        let fix = LocationFix(
            latitude: 33.75,
            longitude: -84.39,
            altitudeMeters: 250,
            horizontalAccuracyMeters: 5,
            capturedAt: timestamp,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: timestamp,
                quality: .verified
            )
        )

        service.enqueueJournalStart(roundID: roundID)
        service.enqueueJournalAppend(fix, roundID: roundID)
        let result = try await service.estimatedLocation(
            roundID: roundID,
            at: timestamp,
            maximumTimeGap: 10,
            maximumHorizontalAccuracy: 25
        )

        let estimatedFix = try XCTUnwrap(result?.estimatedFix)
        XCTAssertEqual(estimatedFix.latitude, fix.latitude)
        XCTAssertEqual(estimatedFix.longitude, fix.longitude)
        XCTAssertEqual(estimatedFix.altitudeMeters, fix.altitudeMeters)
        XCTAssertEqual(estimatedFix.horizontalAccuracyMeters, fix.horizontalAccuracyMeters)
        XCTAssertEqual(estimatedFix.capturedAt, fix.capturedAt)
        XCTAssertEqual(estimatedFix.provenance.source, .iphoneGPS)
        XCTAssertEqual(estimatedFix.provenance.quality, .verified)
        XCTAssertEqual(estimatedFix.provenance.observedAt, fix.provenance.observedAt)
        XCTAssertEqual(result?.method, .nearestTimelineFix)
    }

    private func temporaryDirectories() -> (root: URL, rounds: URL, imports: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhoopMotionImportTests-\(UUID().uuidString)", isDirectory: true)
        return (
            root,
            root.appendingPathComponent("Rounds", isDirectory: true),
            root.appendingPathComponent("Imports", isDirectory: true)
        )
    }
}

extension WhoopMotionImportServiceTests {
    func testReviewDetailsUseImmutableInboxAndPartialDecisionSurvivesRestart() async throws {
        let fixture = try MotionFixture(
            includeNeedsReviewEvent: true,
            includeSecondNeedsReviewEvent: true
        )
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Review Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let payload = try fixture.encodedEnvelope()
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports,
            now: { Date(timeIntervalSince1970: 1_786_552_000) }
        )

        let importOutcome = await importer.importBatch(payload)
        XCTAssertEqual(
            importOutcome,
            .imported(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                swingCount: 1,
                needsReviewCount: 2
            )
        )
        let initial = try await importer.pendingReviewBatches()
        let initialBatch = try XCTUnwrap(initial.first)
        XCTAssertEqual(initialBatch.batchID, fixture.batchID)
        XCTAssertEqual(initialBatch.roundID, fixture.roundID)
        XCTAssertEqual(initialBatch.reason, .needsReview)
        XCTAssertEqual(initialBatch.detectorAcceptedCount, 1)
        XCTAssertEqual(initialBatch.events.count, 2)
        XCTAssertEqual(initialBatch.undecidedCount, 2)
        XCTAssertTrue(initialBatch.events.allSatisfy {
            $0.event.classification.decision == .needsReview && $0.userDecision == nil
        })

        let firstEventID = try XCTUnwrap(initialBatch.events.first?.event.eventID)
        let partial = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: firstEventID,
            decision: .accept
        )
        XCTAssertEqual(
            partial,
            .recorded(
                batchID: fixture.batchID,
                eventID: firstEventID,
                remainingDecisionCount: 1
            )
        )
        let inboxURL = directories.imports
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(fixture.batchID)
            .appendingPathExtension("json")
        XCTAssertEqual(try Data(contentsOf: inboxURL), payload)
        let partiallySavedRounds = try await roundStore.rounds()
        let partiallySavedRound = try XCTUnwrap(partiallySavedRounds.first)
        XCTAssertEqual(partiallySavedRound.swings.count, 1, "review candidates must not auto-accept")

        let reopened = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let persisted = try await reopened.pendingReviewBatches()
        let persistedBatch = try XCTUnwrap(persisted.first)
        XCTAssertEqual(persistedBatch.undecidedCount, 1)
        XCTAssertEqual(
            persistedBatch.events.first(where: { $0.event.eventID == firstEventID })?.userDecision,
            .accept
        )
    }

    func testFullReviewAcceptsAndRejectsThenResolvesIdempotently() async throws {
        let fixture = try MotionFixture(
            includeNeedsReviewEvent: true,
            includeSecondNeedsReviewEvent: true
        )
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Resolution Test Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let correlator = RecordingMotionCorrelator()
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: correlator,
            storageDirectory: directories.imports,
            now: { Date(timeIntervalSince1970: 1_786_552_100) }
        )
        _ = await importer.importBatch(try fixture.encodedEnvelope())
        let reviewEvents = fixture.events.filter {
            $0.classification.decision == .needsReview
        }
        XCTAssertEqual(reviewEvents.count, 2)
        let acceptedEvent = reviewEvents[0]
        let rejectedEvent = reviewEvents[1]

        _ = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: acceptedEvent.eventID,
            decision: .accept
        )
        let resolved = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: rejectedEvent.eventID,
            decision: .reject
        )
        XCTAssertEqual(
            resolved,
            .resolved(
                batchID: fixture.batchID,
                roundID: fixture.roundID,
                acceptedReviewCount: 1,
                rejectedReviewCount: 1
            )
        )
        let savedRounds = try await roundStore.rounds()
        let saved = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(saved.swings.map(\.id), [fixture.acceptedEvent.swingUUID, acceptedEvent.swingUUID])
        XCTAssertNotNil(saved.swings.first?.shotInterval)
        XCTAssertNil(saved.swings.last?.shotInterval)
        let correlationRequests = await correlator.requests()
        XCTAssertEqual(correlationRequests.count, 2)
        let pendingReview = try await importer.pendingReviewBatches()
        let pendingLegacy = try await importer.pendingBatches()
        XCTAssertTrue(pendingReview.isEmpty)
        XCTAssertTrue(pendingLegacy.isEmpty)

        let duplicate = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: rejectedEvent.eventID,
            decision: .reject
        )
        XCTAssertEqual(
            duplicate,
            .duplicate(batchID: fixture.batchID, eventID: rejectedEvent.eventID)
        )
        let roundsAfterDuplicate = try await roundStore.rounds()
        XCTAssertEqual(roundsAfterDuplicate.first?.swings.count, 2)

        let collision = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: rejectedEvent.eventID,
            decision: .accept
        )
        guard case .invalid(let batchID, let eventID, let reason) = collision else {
            return XCTFail("expected a conflicting immutable decision to be invalid")
        }
        XCTAssertEqual(batchID, fixture.batchID)
        XCTAssertEqual(eventID, rejectedEvent.eventID)
        XCTAssertTrue(reason.contains("different user decision"))

        let ledgerURL = directories.imports
            .appendingPathComponent("Reviews", isDirectory: true)
            .appendingPathComponent(fixture.batchID)
            .appendingPathExtension("json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any]
        )
        let records = try XCTUnwrap(object["records"] as? [String: Any])
        XCTAssertEqual(Set(records.keys), Set(reviewEvents.map(\.eventID)))
        XCTAssertEqual(try Data(contentsOf: directories.imports
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(fixture.batchID)
            .appendingPathExtension("json")), try fixture.encodedEnvelope())
    }

    func testManualSourceCannotBeSilentlyRewrittenAsHybridAfterReview() async throws {
        let fixture = try MotionFixture(includeNeedsReviewEvent: true)
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Cross Source Review Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine,
            swings: [
                GolfSwingMetrics(
                    capturedAt: fixture.roundStartedAt.addingTimeInterval(120),
                    peakG: 7,
                    provenance: DataProvenance(
                        source: .manual,
                        observedAt: fixture.roundStartedAt.addingTimeInterval(120),
                        quality: .verified
                    )
                )
            ]
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let importOutcome = await importer.importBatch(try fixture.encodedEnvelope())
        XCTAssertEqual(
            importOutcome,
            .stagedCrossSourceConflict(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let reviewEvent = try XCTUnwrap(
            fixture.events.first { $0.classification.decision == .needsReview }
        )
        let guarded = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: reviewEvent.eventID,
            decision: .accept
        )
        XCTAssertEqual(
            guarded,
            .stagedCrossSourceConflict(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let guardedRounds = try await roundStore.rounds()
        XCTAssertEqual(guardedRounds.first?.swings.count, 1)

        let merged = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: reviewEvent.eventID,
            decision: .accept,
            allowingCrossSourceMerge: true
        )
        XCTAssertEqual(
            merged,
            .stagedCrossSourceConflict(batchID: fixture.batchID, roundID: fixture.roundID)
        )
        let mergedRounds = try await roundStore.rounds()
        XCTAssertEqual(mergedRounds.first?.swings.count, 1)
    }

    func testReviewRejectsUnknownIdentityAndCorruptProtectedFiles() async throws {
        let fixture = try MotionFixture(
            includeNeedsReviewEvent: true,
            includeSecondNeedsReviewEvent: true
        )
        let directories = temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let roundStore = RoundFileStore(directory: directories.rounds)
        var round = GolfRound(
            id: fixture.roundID,
            courseName: "Strict Review Course",
            startedAt: fixture.roundStartedAt,
            holeCount: .nine
        )
        round.markFinished(at: fixture.roundEndedAt)
        try await roundStore.save(round)
        let importer = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: RecordingMotionCorrelator(),
            storageDirectory: directories.imports
        )
        let payload = try fixture.encodedEnvelope()
        _ = await importer.importBatch(payload)
        let reviewEvent = try XCTUnwrap(
            fixture.events.first { $0.classification.decision == .needsReview }
        )

        guard case .invalid(_, _, let unknownBatchReason) = await importer.recordReviewDecision(
            batchID: String(repeating: "0", count: 64),
            eventID: reviewEvent.eventID,
            decision: .accept
        ) else { return XCTFail("expected unknown batch rejection") }
        XCTAssertTrue(unknownBatchReason.contains("not registered"))

        guard case .invalid(_, _, let unknownEventReason) = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: String(repeating: "f", count: 64),
            decision: .accept
        ) else { return XCTFail("expected unknown event rejection") }
        XCTAssertTrue(unknownEventReason.contains("not a reviewable candidate"))

        let inboxURL = directories.imports
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(fixture.batchID)
            .appendingPathExtension("json")
        try Data("{}".utf8).write(to: inboxURL, options: .atomic)
        do {
            _ = try await importer.pendingReviewBatches()
            XCTFail("expected inbox digest mismatch rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("does not match"))
        }
        try payload.write(to: inboxURL, options: .atomic)

        _ = await importer.recordReviewDecision(
            batchID: fixture.batchID,
            eventID: reviewEvent.eventID,
            decision: .accept
        )
        let ledgerURL = directories.imports
            .appendingPathComponent("Reviews", isDirectory: true)
            .appendingPathComponent(fixture.batchID)
            .appendingPathExtension("json")
        var ledger = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any]
        )
        ledger["unknownField"] = true
        try JSONSerialization.data(withJSONObject: ledger).write(to: ledgerURL, options: .atomic)
        do {
            _ = try await importer.pendingReviewBatches()
            XCTFail("expected strict review-ledger decoding rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("decision record is invalid"))
        }
    }
}

final class WhoopMotionBridgeClientTests: XCTestCase {
    func testRequestUsesExactBodyBearerAndFractionalTimestamps() throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test/private",
            bearerToken: "device-secret"
        )
        let start = Date(timeIntervalSince1970: 1_786_536_000.789)
        let payload = try WhoopMotionRequest(
            roundID: UUID(uuidString: "4f62e2f0-31ea-4c5e-8ce4-55d5c4410c71")!,
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600.321),
            requestedAt: start.addingTimeInterval(3_601)
        )
        let request = try WhoopBridgeClient.whoopMotionRequest(
            configuration: configuration,
            payload: payload
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://bridge.example.test/private/v1/whoop-motion/requests"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-secret")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "apiVersion", "schemaVersion", "roundID", "startedAt", "endedAt", "requestedAt"
        ]))
        XCTAssertTrue((object["startedAt"] as? String)?.contains(".789") == true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("device-secret"))
    }

    func testPullSupportsPendingStrongETagAndConditionalNotModified() async throws {
        let fixture = try MotionFixture()
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let pendingData = try JSONSerialization.data(withJSONObject: [
            "status": "pending",
            "roundID": fixture.roundID.uuidString.lowercased(),
        ])
        let pendingTransport = MotionBridgeTransport(
            result: BridgeHTTPResult(data: pendingData, statusCode: 202)
        )
        let pendingClient = WhoopBridgeClient(
            configuration: configuration,
            transport: pendingTransport
        )
        let pendingResult = try await pendingClient.pullWhoopMotion(roundID: fixture.roundID)
        XCTAssertEqual(pendingResult, .pending)

        let data = try fixture.encodedEnvelope()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let etag = "\"\(digest)\""
        let availableTransport = MotionBridgeTransport(
            result: BridgeHTTPResult(data: data, statusCode: 200, headers: ["ETag": etag])
        )
        let availableClient = WhoopBridgeClient(
            configuration: configuration,
            transport: availableTransport
        )
        guard case .available(let envelope, let exactPayload, let responseETag) = try await availableClient
            .pullWhoopMotion(roundID: fixture.roundID) else {
            return XCTFail("Expected available motion batch")
        }
        XCTAssertEqual(envelope.batchID, fixture.batchID)
        XCTAssertEqual(exactPayload, data)
        XCTAssertEqual(responseETag, etag)

        let notModifiedTransport = MotionBridgeTransport(
            result: BridgeHTTPResult(data: Data(), statusCode: 304)
        )
        let notModifiedClient = WhoopBridgeClient(
            configuration: configuration,
            transport: notModifiedTransport
        )
        let notModifiedResult = try await notModifiedClient.pullWhoopMotion(
            roundID: fixture.roundID,
            ifNoneMatch: etag
        )
        XCTAssertEqual(
            notModifiedResult,
            .notModified(etag: etag)
        )
        let conditional = await notModifiedTransport.lastRequest()
        XCTAssertEqual(conditional?.value(forHTTPHeaderField: "If-None-Match"), etag)
    }

    func testMalformedCachedETagFallsBackToUnconditionalPullAndValidReplacement() throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let malformed = "legacy-etag"
        XCTAssertFalse(WhoopBridgeClient.isValidStrongMotionETag(malformed))

        let request = try WhoopBridgeClient.whoopMotionPullRequest(
            configuration: configuration,
            roundID: UUID(),
            ifNoneMatch: WhoopBridgeClient.isValidStrongMotionETag(malformed) ? malformed : nil
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))

        let replacement = "\"\(String(repeating: "a", count: 64))\""
        XCTAssertTrue(WhoopBridgeClient.isValidStrongMotionETag(replacement))
        let conditional = try WhoopBridgeClient.whoopMotionPullRequest(
            configuration: configuration,
            roundID: UUID(),
            ifNoneMatch: replacement
        )
        XCTAssertEqual(conditional.value(forHTTPHeaderField: "If-None-Match"), replacement)
    }

    func testDayResponseAcceptsPartialAbsoluteSkinTemperatureAndRejectsProvenanceDrift() async throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let valid = dayResponseData()
        let transport = MotionBridgeTransport(
            result: BridgeHTTPResult(data: valid, statusCode: 200)
        )
        let client = WhoopBridgeClient(
            configuration: configuration,
            transport: transport,
            now: { ISO8601DateFormatter().date(from: "2026-08-12T16:00:00Z")! }
        )
        let response = try await client.day("2026-08-12")
        XCTAssertEqual(response.physiology.status, "partial")
        XCTAssertEqual(response.physiology.skinTemperatureCelsius, 33.1)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var readiness = try XCTUnwrap(object["golfReadiness"] as? [String: Any])
        var provenance = try XCTUnwrap(readiness["provenance"] as? [String: Any])
        provenance["isWhoopMetric"] = true
        readiness["provenance"] = provenance
        object["golfReadiness"] = readiness
        let invalidTransport = MotionBridgeTransport(
            result: BridgeHTTPResult(
                data: try JSONSerialization.data(withJSONObject: object),
                statusCode: 200
            )
        )
        let invalidClient = WhoopBridgeClient(
            configuration: configuration,
            transport: invalidTransport,
            now: { ISO8601DateFormatter().date(from: "2026-08-12T16:00:00Z")! }
        )
        do {
            _ = try await invalidClient.day("2026-08-12")
            XCTFail("Expected provenance drift to be rejected")
        } catch {
            XCTAssertEqual(error as? WhoopBridgeError, .invalidResponse)
        }
    }

    private func dayResponseData() -> Data {
        Data(
            #"{"apiVersion":1,"date":"2026-08-12","generatedAt":"2026-08-12T15:59:00Z","freshness":{"lastCompleteSyncAt":"2026-08-12T15:45:00Z","stale":false,"staleAfterSeconds":21600},"physiology":{"status":"partial","recoveryPercent":82,"hrvRmssdMs":71,"restingHeartRateBpm":51,"spo2Percent":97.1,"skinTemperatureCelsius":33.1,"sleepHours":7.9,"sleepPerformancePercent":89,"sleepEfficiencyPercent":91,"dayStrain":8.2,"priorDayStrain":11.4,"provenance":{"kind":"providerData","provider":"WHOOP","source":"localSqliteCache"}},"golfReadiness":{"available":true,"score":86,"verdict":"ready","personalised":false,"components":[{"label":"Recovery","value":82,"weight":0.5,"detail":"Cached provider input"}],"advice":["Normal warm-up."],"provenance":{"kind":"derivedAnalysis","producer":"whoop-18birdies","model":"golf-readiness-v1","isWhoopMetric":false,"note":"In-house estimate; not a WHOOP metric."}}}"#.utf8
        )
    }
}

private actor MotionBridgeTransport: BridgeHTTPTransport {
    private let result: BridgeHTTPResult
    private var request: URLRequest?

    init(result: BridgeHTTPResult) { self.result = result }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult {
        self.request = request
        return result
    }

    func lastRequest() -> URLRequest? { request }
}

private actor RecordingMotionCorrelator: WhoopMotionLocationCorrelating {
    struct Request: Sendable {
        let maximumTimeGap: TimeInterval
        let maximumHorizontalAccuracy: Double
    }

    private var recorded: [Request] = []

    func estimatedLocation(
        roundID: UUID,
        at swingTimestamp: Date,
        maximumTimeGap: TimeInterval,
        maximumHorizontalAccuracy: Double
    ) async throws -> RoundLocationCorrelation? {
        recorded.append(
            Request(
                maximumTimeGap: maximumTimeGap,
                maximumHorizontalAccuracy: maximumHorizontalAccuracy
            )
        )
        let fix = LocationFix(
            latitude: 33.75 + (swingTimestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 10) / 100_000),
            longitude: -84.39,
            altitudeMeters: 250,
            horizontalAccuracyMeters: 5,
            capturedAt: swingTimestamp,
            provenance: DataProvenance(
                source: .derived,
                observedAt: swingTimestamp,
                quality: .estimated,
                algorithmVersion: "test-gps-correlation-v1",
                inputSources: [.iphoneGPS]
            )
        )
        return RoundLocationCorrelation(
            estimatedFix: fix,
            method: .interpolatedTimelineFix,
            maximumSourceTimeGapSeconds: 2
        )
    }

    func requests() -> [Request] { recorded }
}

private actor RecoveringMotionCorrelator: WhoopMotionLocationCorrelating {
    private var available = false

    func makeTimelineAvailable() { available = true }

    func estimatedLocation(
        roundID: UUID,
        at swingTimestamp: Date,
        maximumTimeGap: TimeInterval,
        maximumHorizontalAccuracy: Double
    ) async throws -> RoundLocationCorrelation? {
        guard available else { return nil }
        let fix = LocationFix(
            latitude: 33.75,
            longitude: -84.39,
            altitudeMeters: 250,
            horizontalAccuracyMeters: 5,
            capturedAt: swingTimestamp,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: swingTimestamp,
                quality: .verified
            )
        )
        return RoundLocationCorrelation(
            estimatedFix: fix,
            method: .nearestTimelineFix,
            maximumSourceTimeGapSeconds: 0
        )
    }
}

private struct MotionFixture {
    let roundID = UUID(uuidString: "4f62e2f0-31ea-4c5e-8ce4-55d5c4410c71")!
    let roundStartedAt: Date
    let roundEndedAt: Date
    let batchID = String(repeating: "b", count: 64)
    let source: WhoopMotionSource
    let acceptedEvent: WhoopMotionEvent
    let events: [WhoopMotionEvent]

    init(
        includeSecondAcceptedEvent: Bool = false,
        includeNeedsReviewEvent: Bool = false,
        includeSecondNeedsReviewEvent: Bool = false,
        roundBoundaryFraction: TimeInterval = 0
    ) throws {
        self.roundStartedAt = Date(timeIntervalSince1970: 1_786_536_000 + roundBoundaryFraction)
        self.roundEndedAt = Date(timeIntervalSince1970: 1_786_550_400 + roundBoundaryFraction)
        let decoderComponent = try WhoopMotionComponent(name: "whoop5-imu-facts", version: "1.2.3")
        let detectorComponent = try WhoopMotionComponent(name: "whoop-golf-swing", version: "2.0.1")
        self.source = try WhoopMotionSource(
            deviceFamily: "whoop5",
            captureMode: "historicalOffload",
            sampleRateHz: 100,
            offloadCompletedAt: Date(timeIntervalSince1970: 1_786_551_000),
            firmwareVersion: "50.1.2",
            decoder: decoderComponent,
            detector: detectorComponent
        )
        self.acceptedEvent = try Self.makeEvent(
            roundID: roundID,
            baseUnixSeconds: 1_786_536_600,
            sampleIndex: 12,
            frameSHA: String(repeating: "a", count: 64),
            detectorVersion: detectorComponent.version,
            decision: .accepted,
            confidence: 0.94
        )
        var built = [acceptedEvent]
        if includeSecondAcceptedEvent {
            built.append(
                try Self.makeEvent(
                    roundID: roundID,
                    baseUnixSeconds: 1_786_536_900,
                    sampleIndex: 45,
                    frameSHA: String(repeating: "c", count: 64),
                    detectorVersion: detectorComponent.version,
                    decision: .accepted,
                    confidence: 0.91
                )
            )
        }
        if includeNeedsReviewEvent {
            built.append(
                try Self.makeEvent(
                    roundID: roundID,
                    baseUnixSeconds: 1_786_537_200,
                    sampleIndex: 25,
                    frameSHA: String(repeating: "d", count: 64),
                    detectorVersion: detectorComponent.version,
                    decision: .needsReview,
                    confidence: 0.51,
                    reasons: [.lowDetectorConfidence]
                )
            )
        }
        if includeSecondNeedsReviewEvent {
            built.append(
                try Self.makeEvent(
                    roundID: roundID,
                    baseUnixSeconds: 1_786_537_500,
                    sampleIndex: 37,
                    frameSHA: String(repeating: "e", count: 64),
                    detectorVersion: detectorComponent.version,
                    decision: .needsReview,
                    confidence: 0.47,
                    reasons: [.coverageGapNearEvent]
                )
            )
        }
        self.events = built
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? standard.date(from: value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "bad date")
                )
            }
            return date
        }
        return decoder
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    func encodedEnvelope() throws -> Data {
        try encodedEnvelope(schemaVersion: 1, events: events)
    }

    func encodedV2Envelope() throws -> Data {
        let v2Events = try events.map { event in
            try WhoopMotionEvent(
                eventID: event.eventID,
                observedAt: event.observedAt,
                frameRef: event.frameRef,
                classification: event.classification,
                metrics: event.metrics,
                wristAnalysis: wristAnalysis(for: event)
            )
        }
        return try encodedEnvelope(schemaVersion: 2, events: v2Events)
    }

    private func encodedEnvelope(
        schemaVersion: Int,
        events: [WhoopMotionEvent]
    ) throws -> Data {
        let coverage = try WhoopMotionCoverage(
            roundStartedAt: roundStartedAt,
            roundEndedAt: roundEndedAt,
            firstFrameAt: roundStartedAt,
            lastFrameAt: roundEndedAt,
            decodedFrameCount: 50_000,
            uniqueSecondCount: 500,
            offloadTerminal: .historyComplete,
            frameCoverage: .continuous,
            complete: true,
            gaps: []
        )
        let envelope = try WhoopMotionEnvelope(
            schemaVersion: schemaVersion,
            batchID: batchID,
            roundID: roundID,
            generatedAt: Date(timeIntervalSince1970: 1_786_551_100),
            source: source,
            coverage: coverage,
            events: events
        )
        return try encoder.encode(envelope)
    }

    private func wristAnalysis(for event: WhoopMotionEvent) throws -> WhoopMotionWristAnalysis {
        let trace = try WhoopWristOrientationTrace(
            points: [
                WhoopWristTracePoint(
                    offsetMilliseconds: -1_000,
                    phase: .takeaway,
                    orientation: WhoopMotionUnitQuaternion(w: 1, x: 0, y: 0, z: 0)
                ),
                WhoopWristTracePoint(
                    offsetMilliseconds: 0,
                    phase: .impact,
                    orientation: WhoopMotionUnitQuaternion(
                        w: 0.92387953,
                        x: 0,
                        y: 0,
                        z: 0.38268343
                    )
                ),
            ]
        )
        return try WhoopMotionWristAnalysis(
            algorithm: WhoopMotionComponent(name: "whoop-wrist-motion", version: "0.2.0"),
            measurementScope: WhoopWristMeasurementScope(),
            sampling: WhoopWristSampling(
                sampleCount: 180,
                estimatedSampleRateHz: 100,
                timingResolutionMilliseconds: 10,
                gapCount: 0
            ),
            quality: WhoopWristQuality(status: .usable, reasons: []),
            calibration: WhoopWristCalibration(
                label: .personalBaseline,
                quietSampleCount: 20,
                gyroscopeBiasDegreesPerSecond: WhoopMotionVector3(x: 2, y: -1, z: 3)
            ),
            phases: WhoopWristPhases(
                transitionMethod: .gyroReversal,
                backswingSeconds: event.metrics.backswingSeconds,
                downswingSeconds: event.metrics.downswingSeconds,
                tempoRatio: event.metrics.tempoRatio
            ),
            features: WhoopWristFeatures(
                peakSpecificForceG: event.metrics.peakG,
                peakAddressRelativeAccelerationG: 6,
                peakAngularSpeedDegreesPerSecond: 900,
                totalAngularTravelToImpactDegrees: 280,
                dominantAngularAxisSensor: WhoopMotionVector3(
                    x: 0,
                    y: 0,
                    z: 1,
                    allowedRange: -1...1
                ),
                angularAxisConcentration: 0.98
            ),
            orientationTrace: trace,
            uncertainty: WhoopWristUncertainty(
                phaseBoundaryPlusMinusMilliseconds: 20,
                orientationAtImpactPlusMinusDegrees: 5
            )
        )
    }

    private static func makeEvent(
        roundID: UUID,
        baseUnixSeconds: Int64,
        sampleIndex: Int,
        frameSHA: String,
        detectorVersion: String,
        decision: WhoopMotionDecision,
        confidence: Double,
        reasons: [WhoopMotionReviewReason] = []
    ) throws -> WhoopMotionEvent {
        let observedAt = Date(
            timeIntervalSince1970: TimeInterval(baseUnixSeconds) + (Double(sampleIndex) / 100)
        )
        let epochMilliseconds = baseUnixSeconds * 1_000 + Int64(sampleIndex * 10)
        let preimage = [
            "whoop5-swing-v1",
            roundID.uuidString.lowercased(),
            String(epochMilliseconds),
            frameSHA,
            String(sampleIndex),
            detectorVersion,
        ].joined(separator: "\u{001F}")
        let eventID = SHA256.hash(data: Data(preimage.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try WhoopMotionEvent(
            eventID: eventID,
            observedAt: observedAt,
            frameRef: WhoopMotionFrameReference(
                baseUnixSeconds: baseUnixSeconds,
                sampleIndex: sampleIndex,
                sha256: frameSHA
            ),
            classification: WhoopMotionClassification(
                label: "golfSwingCandidate",
                decision: decision,
                confidence: confidence,
                reasons: reasons
            ),
            metrics: WhoopMotionMetrics(
                peakG: 10.4,
                backswingSeconds: 0.75,
                downswingSeconds: 0.25,
                tempoRatio: 3,
                heartRate: WhoopMotionHeartRate(
                    bpm: 112,
                    observedAt: observedAt,
                    source: .whoopBroadcast,
                    quality: .verified
                )
            )
        )
    }
}

private extension UUID {
    var version: Int {
        let value = uuid
        return Int((value.6 & 0xf0) >> 4)
    }
}

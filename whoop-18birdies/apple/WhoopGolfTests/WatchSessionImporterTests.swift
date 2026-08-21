import Foundation
import XCTest
@testable import WhoopGolf

final class WatchSessionImporterTests: XCTestCase {
    func testLinkedRoundImportsTypedSwingsAndPersistsDuplicateRegistry() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let roundID = UUID()
        let roundStore = RoundFileStore(directory: fixture.roundStore)
        try await roundStore.save(GolfRound(id: roundID, courseName: "Exact Match"))
        let received = try writePayload(
            sessionID: "round-20260812T120000Z-a1b2c3d4",
            mode: .round,
            roundID: roundID,
            to: fixture.rawSessions
        )
        let importer = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )

        let first = await importer.importSession(received)
        XCTAssertEqual(
            first,
            .imported(sessionID: received.id, roundID: roundID, swingCount: 2)
        )

        let loadedRounds = try await roundStore.rounds()
        let loadedRound = try XCTUnwrap(loadedRounds.first)
        XCTAssertEqual(loadedRound.swings.count, 2)
        XCTAssertEqual(
            loadedRound.swings.map(\.id),
            [
                WatchSwingIdentity(sessionID: received.id, index: 1).uuid,
                WatchSwingIdentity(sessionID: received.id, index: 2).uuid,
            ]
        )
        XCTAssertEqual(loadedRound.swings.map(\.provenance.source), [.appleWatch, .appleWatch])
        XCTAssertEqual(loadedRound.swings.first?.peakG, 9.4)
        XCTAssertEqual(loadedRound.swings.first?.tempoRatio, 3.0)
        XCTAssertEqual(loadedRound.swings.first?.location?.latitude, 40.0)
        XCTAssertEqual(loadedRound.swings.first?.location?.horizontalAccuracyMeters, 4.0)
        XCTAssertEqual(loadedRound.swings.first?.location?.provenance.source, .appleWatch)
        XCTAssertEqual(
            loadedRound.swings.first?.locationCorrelationMethod,
            .sensorSynchronized
        )

        let interval = try XCTUnwrap(loadedRound.swings.first?.shotInterval)
        XCTAssertEqual(interval.finalizedBySwingID, loadedRound.swings[1].id)
        XCTAssertEqual(interval.elapsedSeconds, 360)
        XCTAssertEqual(interval.straightLineDisplacementYards ?? 0, 121.6, accuracy: 0.8)
        XCTAssertEqual(interval.distanceUncertaintyYards ?? 0, 5.47, accuracy: 0.02)
        XCTAssertEqual(interval.distanceStatus, .measured)
        XCTAssertEqual(interval.quality, .estimated)
        XCTAssertEqual(interval.algorithmVersion, SwingShotIntervalCalculator.algorithmVersion)
        XCTAssertNil(loadedRound.swings.last?.shotInterval)

        let relaunchedImporter = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )
        let duplicate = await relaunchedImporter.importSession(received)
        XCTAssertEqual(duplicate, .duplicate(sessionID: received.id))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.imports.appendingPathComponent("registry.json").path
            )
        )
        let roundsAfterDuplicate = try await roundStore.rounds()
        XCTAssertEqual(roundsAfterDuplicate.first?.swings.count, 2)
    }

    func testLegacyRoundWithOnlyOneCandidateStillRequiresExplicitUserLink() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let roundID = UUID()
        let roundStore = RoundFileStore(directory: fixture.roundStore)
        try await roundStore.save(GolfRound(id: roundID, courseName: "Only Round"))
        let received = try writePayload(
            sessionID: "round-legacy-without-link",
            mode: .round,
            roundID: nil,
            schemaVersion: nil,
            to: fixture.rawSessions
        )
        let importer = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )

        let pendingOutcome = await importer.importSession(received)
        XCTAssertEqual(pendingOutcome, .pendingUserLink(sessionID: received.id))
        let roundsBeforeLink = try await roundStore.rounds()
        XCTAssertEqual(roundsBeforeLink.first?.swings.count, 0)
        let pending = try await importer.pendingSessions()
        XCTAssertEqual(pending.map(\.sessionID), [received.id])
        XCTAssertNil(pending.first?.requestedRoundID)

        let relaunchedImporter = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )
        let linked = await relaunchedImporter.linkPendingSession(
            sessionID: received.id,
            to: roundID
        )
        XCTAssertEqual(
            linked,
            .imported(sessionID: received.id, roundID: roundID, swingCount: 2)
        )
        let roundsAfterLink = try await roundStore.rounds()
        XCTAssertEqual(roundsAfterLink.first?.swings.count, 2)
        let duplicate = await relaunchedImporter.linkPendingSession(
            sessionID: received.id,
            to: roundID
        )
        XCTAssertEqual(duplicate, .duplicate(sessionID: received.id))
    }

    func testRangeSessionIsStoredSeparatelyAndNeverMutatesRounds() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let roundStore = RoundFileStore(directory: fixture.roundStore)
        try await roundStore.save(GolfRound(courseName: "Unrelated Round"))
        let received = try writePayload(
            sessionID: "range-20260812T130000Z-e5f6a7b8",
            mode: .range,
            roundID: nil,
            to: fixture.rawSessions
        )
        let importer = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )

        let stored = await importer.importSession(received)
        XCTAssertEqual(stored, .rangeStored(sessionID: received.id, swingCount: 2))
        let rangeCopy = fixture.imports
            .appendingPathComponent("RangeSessions", isDirectory: true)
            .appendingPathComponent(received.id)
            .appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rangeCopy.path))
        let roundsAfterRange = try await roundStore.rounds()
        XCTAssertEqual(roundsAfterRange.first?.swings.count, 0)
        let duplicate = await importer.importSession(received)
        XCTAssertEqual(duplicate, .duplicate(sessionID: received.id))
    }

    func testUnsupportedSchemaHasExplicitInvalidOutcome() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let roundStore = RoundFileStore(directory: fixture.roundStore)
        let received = try writePayload(
            sessionID: "round-future-schema",
            mode: .round,
            roundID: UUID(),
            schemaVersion: 2,
            to: fixture.rawSessions
        )
        let importer = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )

        guard case .invalid(let sessionID, let reason) = await importer.importSession(received) else {
            return XCTFail("unsupported schema should be invalid")
        }
        XCTAssertEqual(sessionID, received.id)
        XCTAssertTrue(reason.contains("schema 2"))
    }

    func testSwingIdentityUsesSessionAndIndexDeterministically() {
        let first = WatchSwingIdentity(sessionID: "round-a", index: 1)
        XCTAssertEqual(first.uuid, WatchSwingIdentity(sessionID: "round-a", index: 1).uuid)
        XCTAssertNotEqual(first.uuid, WatchSwingIdentity(sessionID: "round-a", index: 2).uuid)
        XCTAssertNotEqual(first.uuid, WatchSwingIdentity(sessionID: "round-b", index: 1).uuid)
    }

    func testDistanceQualityGatesMissingStaleAndLowAccuracyLocations() throws {
        let start = Date(timeIntervalSince1970: 1_755_000_000)
        let end = start.addingTimeInterval(90)
        let validDestination = makeSwing(
            at: end,
            location: swingLocation(at: end, accuracy: 3)
        )

        let missing = SwingShotIntervalCalculator.interval(
            from: makeSwing(at: start, location: nil),
            finalizedBy: validDestination
        )
        XCTAssertEqual(missing.distanceStatus, .missingLocation)
        XCTAssertNil(missing.straightLineDisplacementYards)

        let missingAccuracy = SwingShotIntervalCalculator.interval(
            from: makeSwing(
                at: start,
                location: swingLocation(at: start, accuracy: nil)
            ),
            finalizedBy: validDestination
        )
        XCTAssertEqual(missingAccuracy.distanceStatus, .missingHorizontalAccuracy)
        XCTAssertNil(missingAccuracy.distanceUncertaintyYards)

        let stale = SwingShotIntervalCalculator.interval(
            from: makeSwing(
                at: start,
                location: swingLocation(at: start.addingTimeInterval(-11), accuracy: 4)
            ),
            finalizedBy: validDestination
        )
        XCTAssertEqual(stale.distanceStatus, .staleLocation)
        XCTAssertEqual(stale.quality, .stale)

        let lowAccuracy = SwingShotIntervalCalculator.interval(
            from: makeSwing(
                at: start,
                location: swingLocation(at: start, accuracy: 25.01)
            ),
            finalizedBy: validDestination
        )
        XCTAssertEqual(lowAccuracy.distanceStatus, .lowHorizontalAccuracy)
        XCTAssertEqual(lowAccuracy.quality, .unavailable)
        XCTAssertNil(lowAccuracy.straightLineDisplacementYards)
    }

    func testImporterOrdersSwingsByTimestampBeforeFinalizingIntervals() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let roundID = UUID()
        let roundStore = RoundFileStore(directory: fixture.roundStore)
        try await roundStore.save(GolfRound(id: roundID, courseName: "Time Order"))
        let received = try writePayload(
            sessionID: "round-time-order",
            mode: .round,
            roundID: roundID,
            swings: [
                swingPayload(
                    index: 1,
                    timestamp: "2026-08-12T12:11:00.000Z",
                    latitude: 40.001,
                    accuracy: 3
                ),
                swingPayload(
                    index: 2,
                    timestamp: "2026-08-12T12:10:00.000Z",
                    latitude: 40.0,
                    accuracy: 4
                ),
            ],
            to: fixture.rawSessions
        )
        let importer = WatchSessionImporter(
            roundStore: roundStore,
            storageDirectory: fixture.imports,
            rawSessionsDirectory: fixture.rawSessions
        )

        _ = await importer.importSession(received)

        let savedRounds = try await roundStore.rounds()
        let round = try XCTUnwrap(savedRounds.first)
        XCTAssertEqual(
            round.swings.map(\.id),
            [
                WatchSwingIdentity(sessionID: received.id, index: 2).uuid,
                WatchSwingIdentity(sessionID: received.id, index: 1).uuid,
            ]
        )
        XCTAssertEqual(round.swings[0].shotInterval?.elapsedSeconds, 60)
        XCTAssertEqual(round.swings[0].shotInterval?.finalizedBySwingID, round.swings[1].id)
        XCTAssertNil(round.swings[1].shotInterval)
    }

    func testLegacySwingWithoutLocationOrIntervalStillDecodes() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_755_000_000)
        let legacy = LegacyGolfSwingMetrics(
            id: UUID(),
            capturedAt: capturedAt,
            peakG: 8.7,
            backswingSeconds: 0.8,
            downswingSeconds: 0.27,
            tempoRatio: 2.96,
            heartRateBPM: 105,
            provenance: DataProvenance(
                source: .manual,
                observedAt: capturedAt,
                quality: .verified
            )
        )

        let decoded = try JSONDecoder().decode(
            GolfSwingMetrics.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertNil(decoded.location)
        XCTAssertNil(decoded.locationCorrelationMethod)
        XCTAssertNil(decoded.shotInterval)
    }

    private struct Fixture {
        let root: URL
        let roundStore: URL
        let rawSessions: URL
        let imports: URL
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchSessionImporterTests-\(UUID().uuidString)", isDirectory: true)
        let rawSessions = root.appendingPathComponent("WatchSessions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rawSessions,
            withIntermediateDirectories: true
        )
        return Fixture(
            root: root,
            roundStore: root.appendingPathComponent("RoundStore", isDirectory: true),
            rawSessions: rawSessions,
            imports: root.appendingPathComponent("WatchImports", isDirectory: true)
        )
    }

    private func writePayload(
        sessionID: String,
        mode: WatchSessionMode,
        roundID: UUID?,
        schemaVersion: Int? = 1,
        swings: [[String: Any]]? = nil,
        to directory: URL
    ) throws -> ReceivedWatchSession {
        var payload: [String: Any] = [
            "session_id": sessionID,
            "mode": mode.rawValue,
            "started_at": "2026-08-12T12:00:00.000Z",
            "completed_at": "2026-08-12T15:30:00.000Z",
            "auto_threshold": true,
            "sample_rate_hz": 100,
            "swings": swings ?? [
                swingPayload(
                    index: 1,
                    timestamp: "2026-08-12T12:10:00.000Z",
                    latitude: 40.0,
                    accuracy: 4,
                    peakG: 9.4,
                    backswing: 0.78,
                    downswing: 0.26,
                    heartRate: 108
                ),
                swingPayload(
                    index: 2,
                    timestamp: "2026-08-12T12:16:00.000Z",
                    latitude: 40.001,
                    accuracy: 3,
                    peakG: 10.1,
                    backswing: 0.75,
                    downswing: 0.25,
                    heartRate: 111
                ),
            ],
        ]
        if let schemaVersion { payload["schema_version"] = schemaVersion }
        if let roundID { payload["round_id"] = roundID.uuidString }

        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let fileURL = directory
            .appendingPathComponent(sessionID)
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        return ReceivedWatchSession(
            id: sessionID,
            schemaVersion: schemaVersion ?? 1,
            mode: mode,
            roundID: roundID,
            fileURL: fileURL,
            receivedAt: Date(timeIntervalSince1970: 1_755_000_000)
        )
    }

    private func swingPayload(
        index: Int,
        timestamp: String,
        latitude: Double?,
        accuracy: Double?,
        peakG: Double = 9,
        backswing: Double = 0.78,
        downswing: Double = 0.26,
        heartRate: Int = 108
    ) -> [String: Any] {
        var value: [String: Any] = [
            "index": index,
            "timestamp": timestamp,
            "peak_g": peakG,
            "backswing_s": backswing,
            "downswing_s": downswing,
            "tempo_ratio": backswing / downswing,
            "tempo_frames": "24/8",
            "hr_bpm": heartRate,
        ]
        if let latitude {
            var location: [String: Any] = [
                "latitude": latitude,
                "longitude": -75.0,
                "altitude": 60.0,
            ]
            if let accuracy {
                location["horizontal_accuracy"] = accuracy
            }
            value["location"] = location
        }
        return value
    }

    private func makeSwing(
        id: UUID = UUID(),
        at date: Date,
        location: SwingLocationObservation?
    ) -> GolfSwingMetrics {
        GolfSwingMetrics(
            id: id,
            capturedAt: date,
            peakG: 8,
            provenance: DataProvenance(
                source: .manual,
                observedAt: date,
                quality: .verified
            ),
            location: location
        )
    }

    private func swingLocation(
        at date: Date,
        accuracy: Double?
    ) -> SwingLocationObservation {
        SwingLocationObservation(
            latitude: 40,
            longitude: -75,
            altitudeMeters: 60,
            horizontalAccuracyMeters: accuracy,
            capturedAt: date,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: date,
                quality: accuracy == nil ? .unavailable : .verified
            )
        )
    }
}

private struct LegacyGolfSwingMetrics: Encodable {
    let id: UUID
    let capturedAt: Date
    let peakG: Double
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?
    let heartRateBPM: Int?
    let provenance: DataProvenance
}

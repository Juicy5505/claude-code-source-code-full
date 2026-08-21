import XCTest
@testable import WhoopGolf

final class RoundLocationJournalTests: XCTestCase {
    func testFirstAppendSurvivesStopAndProcessStyleReopen() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roundID = UUID()
        let first = makeFix(
            latitude: 33.749,
            longitude: -84.388,
            accuracy: 4,
            at: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let second = makeFix(
            latitude: 33.7495,
            longitude: -84.3875,
            accuracy: 5,
            at: Date(timeIntervalSince1970: 1_780_000_010)
        )

        let writer = RoundLocationJournal(directory: directory)
        try await writer.start(roundID: roundID)
        try await writer.append(first, roundID: roundID)
        try await writer.append(second, roundID: roundID)
        try await writer.stop(roundID: roundID)

        let reopened = RoundLocationJournal(directory: directory)
        let loaded = try await reopened.load(roundID: roundID)

        XCTAssertEqual(loaded, [first, second])
        XCTAssertEqual(loaded.first?.provenance.observedAt, first.capturedAt)
        XCTAssertEqual(loaded.first?.provenance.source, .iphoneGPS)
    }

    func testCorruptAndPartiallyWrittenRecordsDoNotEraseValidTimeline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roundID = UUID()
        let valid = makeFix(
            latitude: 40.7128,
            longitude: -74.006,
            accuracy: 6,
            at: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let journal = RoundLocationJournal(directory: directory)
        try await journal.start(roundID: roundID)
        try await journal.append(valid, roundID: roundID)
        try await journal.stop(roundID: roundID)

        let file = journalFile(directory: directory, roundID: roundID)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{partial-record".utf8))
        try handle.close()

        let reopened = RoundLocationJournal(directory: directory)
        let recovered = try await reopened.load(roundID: roundID)
        XCTAssertEqual(recovered, [valid])
        let repaired = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(repaired.contains("partial-record"))
    }

    func testRetentionBoundsEntryCountDurationAndFileSize() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roundID = UUID()
        let journal = RoundLocationJournal(
            directory: directory,
            configuration: .init(
                maximumEntries: 3,
                maximumTimelineDuration: 90,
                maximumFileSizeBytes: 1_024
            )
        )
        try await journal.start(roundID: roundID)

        let base = Date(timeIntervalSince1970: 1_780_000_000)
        for offset in stride(from: 0, through: 180, by: 30) {
            try await journal.append(
                makeFix(
                    latitude: 33.75 + (Double(offset) / 100_000),
                    longitude: -84.39,
                    accuracy: 4,
                    at: base.addingTimeInterval(Double(offset))
                ),
                roundID: roundID
            )
        }

        let retained = try await journal.load(roundID: roundID)
        XCTAssertLessThanOrEqual(retained.count, 3)
        XCTAssertEqual(retained.last?.capturedAt, base.addingTimeInterval(180))
        if let first = retained.first, let last = retained.last {
            XCTAssertLessThanOrEqual(last.capturedAt.timeIntervalSince(first.capturedAt), 90)
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: journalFile(directory: directory, roundID: roundID).path
        )
        let size = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertLessThanOrEqual(size.intValue, 1_024)
    }

    func testCorrelationInterpolatesOrUsesNearestWithTimeAndAccuracyGates() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roundID = UUID()
        let journal = RoundLocationJournal(directory: directory)
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        try await journal.start(roundID: roundID)
        try await journal.append(
            makeFix(latitude: 10, longitude: 20, accuracy: 4, at: base),
            roundID: roundID
        )
        try await journal.append(
            makeFix(latitude: 80, longitude: 80, accuracy: 80, at: base.addingTimeInterval(5)),
            roundID: roundID
        )
        try await journal.append(
            makeFix(latitude: 10.001, longitude: 20.002, accuracy: 6, at: base.addingTimeInterval(10)),
            roundID: roundID
        )

        let interpolated = try await journal.correlate(
            roundID: roundID,
            at: base.addingTimeInterval(4),
            maximumTimeGap: 10,
            maximumHorizontalAccuracy: 25
        )
        XCTAssertEqual(interpolated?.method, .interpolatedTimelineFix)
        XCTAssertEqual(interpolated?.estimatedFix.latitude ?? 0, 10.0004, accuracy: 0.000_000_1)
        XCTAssertEqual(interpolated?.estimatedFix.longitude ?? 0, 20.0008, accuracy: 0.000_000_1)
        XCTAssertEqual(interpolated?.estimatedFix.capturedAt, base.addingTimeInterval(4))
        XCTAssertEqual(interpolated?.estimatedFix.provenance.source, .derived)
        XCTAssertEqual(interpolated?.estimatedFix.provenance.inputSources, [.iphoneGPS])

        let nearest = try await journal.correlate(
            roundID: roundID,
            at: base.addingTimeInterval(12),
            maximumTimeGap: 3,
            maximumHorizontalAccuracy: 25
        )
        XCTAssertEqual(nearest?.method, .nearestTimelineFix)
        XCTAssertEqual(nearest?.estimatedFix.capturedAt, base.addingTimeInterval(10))
        XCTAssertEqual(nearest?.maximumSourceTimeGapSeconds, 2)

        let outsideWindow = try await journal.correlate(
            roundID: roundID,
            at: base.addingTimeInterval(30),
            maximumTimeGap: 3,
            maximumHorizontalAccuracy: 25
        )
        XCTAssertNil(outsideWindow)

        let accuracyRejected = try await journal.correlate(
            roundID: roundID,
            at: base.addingTimeInterval(5),
            maximumTimeGap: 0,
            maximumHorizontalAccuracy: 25
        )
        XCTAssertNil(accuracyRejected)
    }

    func testInvalidFixIsRejectedWithoutChangingJournal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roundID = UUID()
        let journal = RoundLocationJournal(directory: directory)
        try await journal.start(roundID: roundID)
        let invalid = makeFix(
            latitude: 91,
            longitude: 0,
            accuracy: 4,
            at: Date(timeIntervalSince1970: 1_780_000_000)
        )

        do {
            try await journal.append(invalid, roundID: roundID)
            XCTFail("Expected invalid coordinate to be rejected")
        } catch let error as RoundLocationJournal.JournalError {
            guard case .invalidFix = error else {
                return XCTFail("Unexpected journal error: \(error)")
            }
        }
        let loaded = try await journal.load(roundID: roundID)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testExpiredInactiveJournalIsPurgedWhileActiveJournalIsPreserved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expiredRoundID = UUID()
        let activeRoundID = UUID()
        let journal = RoundLocationJournal(
            directory: directory,
            configuration: .init(maximumJournalAge: 24 * 60 * 60)
        )
        let now = Date()

        try await journal.start(roundID: expiredRoundID)
        try await journal.append(
            makeFix(latitude: 33.75, longitude: -84.39, accuracy: 5, at: now),
            roundID: expiredRoundID
        )
        try await journal.stop(roundID: expiredRoundID)
        try await journal.start(roundID: activeRoundID)
        let oldModificationDate = now.addingTimeInterval(-2 * 24 * 60 * 60)
        for roundID in [expiredRoundID, activeRoundID] {
            try FileManager.default.setAttributes(
                [.modificationDate: oldModificationDate],
                ofItemAtPath: journalFile(directory: directory, roundID: roundID).path
            )
        }
        let removed = try await journal.purgeExpired(
            referenceDate: now,
            preserving: activeRoundID
        )

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journalFile(directory: directory, roundID: expiredRoundID).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: journalFile(directory: directory, roundID: activeRoundID).path
            )
        )
    }

    private func makeFix(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        at timestamp: Date
    ) -> LocationFix {
        LocationFix(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: 250,
            horizontalAccuracyMeters: accuracy,
            capturedAt: timestamp,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: timestamp,
                receivedAt: timestamp,
                quality: accuracy <= 25 ? .verified : .estimated
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RoundLocationJournalTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func journalFile(directory: URL, roundID: UUID) -> URL {
        directory
            .appendingPathComponent(roundID.uuidString.lowercased())
            .appendingPathExtension("ndjson")
    }
}

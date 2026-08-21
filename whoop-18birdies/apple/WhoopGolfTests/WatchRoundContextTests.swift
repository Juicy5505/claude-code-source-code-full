import Foundation
import XCTest
@testable import WhoopGolf

final class WatchRoundContextTests: XCTestCase {
    func testApplicationContextRoundTripsExactIdentityAndExplicitClear() throws {
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_786_550_400)
        let expected = WatchRoundContext(
            roundID: id,
            courseName: "Bethpage Black",
            startedAt: startedAt
        )

        let encoded = try WatchRoundApplicationContextCodec.encode(expected)
        let decoded = try XCTUnwrap(WatchRoundApplicationContextCodec.decode(encoded))
        XCTAssertEqual(decoded, expected)

        let cleared = try WatchRoundApplicationContextCodec.encode(nil)
        XCTAssertNil(try WatchRoundApplicationContextCodec.decode(cleared))
        XCTAssertNil(try WatchRoundApplicationContextCodec.decode([:]))
    }

    func testApplicationContextRejectsInvalidRoundInsteadOfPublishingIt() {
        let invalid = WatchRoundContext(
            roundID: UUID(),
            courseName: "   ",
            startedAt: Date(timeIntervalSince1970: 1_786_550_400)
        )

        XCTAssertThrowsError(try WatchRoundApplicationContextCodec.encode(invalid)) { error in
            XCTAssertEqual(error as? WatchRoundContextError, .invalidCourseName)
        }
    }

    func testRecoveryScannerReturnsEveryValidSessionAndReportsCorruption() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let roundID = UUID()
        try validSessionData(sessionID: "round-one", roundID: roundID)
            .write(to: root.appendingPathComponent("round-one.json"), options: .atomic)
        try validSessionData(sessionID: "range-two", mode: "range", roundID: nil)
            .write(to: root.appendingPathComponent("range-two.json"), options: .atomic)
        try Data("not-json".utf8)
            .write(to: root.appendingPathComponent("broken.json"), options: .atomic)
        // Non-JSON files are outside the raw-session corpus and are ignored.
        try Data("ignored".utf8)
            .write(to: root.appendingPathComponent("README.txt"), options: .atomic)

        let snapshot = WatchSessionRecoveryScanner.scan(directory: root)

        // Recovery intentionally returns capture order (modification time), not
        // filename order. This assertion cares that every durable session is
        // recovered, independent of filesystem timestamp resolution.
        XCTAssertEqual(snapshot.sessions.map(\.id).sorted(), ["range-two", "round-one"])
        XCTAssertEqual(snapshot.sessions.first(where: { $0.id == "round-one" })?.roundID, roundID)
        XCTAssertEqual(snapshot.failures.count, 1)
        XCTAssertEqual(snapshot.failures.first?.fileURL.lastPathComponent, "broken.json")
    }

    func testRecoveryScannerRejectsFilenameIdentityMismatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try validSessionData(sessionID: "payload-id", roundID: UUID())
            .write(to: root.appendingPathComponent("different-id.json"), options: .atomic)

        let snapshot = WatchSessionRecoveryScanner.scan(directory: root)
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertEqual(snapshot.failures.count, 1)
        XCTAssertTrue(snapshot.failures[0].reason.contains("metadata"))
    }

    private func validSessionData(
        sessionID: String,
        mode: String = "round",
        roundID: UUID?
    ) throws -> Data {
        var payload: [String: Any] = [
            "schema_version": 1,
            "session_id": sessionID,
            "mode": mode,
            "started_at": "2026-08-12T12:00:00.000Z",
            "completed_at": "2026-08-12T12:01:00.000Z",
            "auto_threshold": true,
            "sample_rate_hz": 100,
            "swings": [],
        ]
        if let roundID {
            payload["round_id"] = roundID.uuidString
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

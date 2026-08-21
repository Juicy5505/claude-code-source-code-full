import Foundation
import XCTest
@testable import WhoopGolf

/// Yardage bridge + Watch session JSON decode (phone ↔ Watch contract).
final class WatchYardageBridgeTests: XCTestCase {
    func testLiveFaceCodecRoundTripsYardageWithoutInventingPins() throws {
        let face = WatchLiveFace(
            holeNumber: 12,
            lastShotYards: 208,
            wristMount: .trailRight,
            courseName: "Practice Nine"
        )
        XCTAssertFalse(face.hasHoleMap)

        let encoded = try WatchLiveFaceCodec.encode(face)
        XCTAssertEqual(encoded.keys.count, 1)
        XCTAssertEqual(
            encoded.keys.first,
            WatchLiveFaceCodec.applicationContextKey
        )

        let decoded = try XCTUnwrap(WatchLiveFaceCodec.decode(encoded))
        XCTAssertEqual(decoded, face)
        XCTAssertNil(decoded.frontYards)
        XCTAssertNil(decoded.middleYards)
        XCTAssertNil(decoded.backYards)
        XCTAssertEqual(decoded.wristMount, .trailRight)
    }

    func testLiveFaceCodecMergePreservesRoundIdentityEnvelope() throws {
        let roundID = UUID()
        let existing: [String: Any] = [
            "round_id": roundID.uuidString,
            "course_name": "Keep Me",
        ]
        let face = WatchLiveFace(
            holeNumber: 4,
            lastShotYards: 97,
            wristMount: .leadLeft
        )

        let merged = try WatchLiveFaceCodec.merge(face, into: existing)
        XCTAssertEqual(merged["round_id"] as? String, roundID.uuidString)
        XCTAssertEqual(merged["course_name"] as? String, "Keep Me")
        XCTAssertNotNil(merged[WatchLiveFaceCodec.applicationContextKey] as? Data)

        let decoded = try XCTUnwrap(WatchLiveFaceCodec.decode(merged))
        XCTAssertEqual(decoded.holeNumber, 4)
        XCTAssertEqual(decoded.lastShotYards, 97)
        XCTAssertEqual(decoded.wristMount, .leadLeft)
        XCTAssertFalse(decoded.hasHoleMap)
    }

    func testLiveFaceCodecReturnsNilForMissingOrWrongTypePayload() throws {
        XCTAssertNil(try WatchLiveFaceCodec.decode([:]))
        XCTAssertNil(
            try WatchLiveFaceCodec.decode([
                WatchLiveFaceCodec.applicationContextKey: "not-data",
            ])
        )
    }

    func testSessionPayloadDecoderAcceptsSchemaV1RoundWithLinkedSwings() throws {
        let roundID = UUID()
        let data = try sessionJSON(
            schemaVersion: 1,
            sessionID: "round-20260821T010000Z-abcd1234",
            mode: "round",
            roundID: roundID,
            includeSwing: true
        )

        let payload = try WatchSessionPayloadDecoder.decode(data)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.sessionID, "round-20260821T010000Z-abcd1234")
        XCTAssertEqual(payload.mode, .round)
        XCTAssertEqual(payload.roundID, roundID)
        XCTAssertEqual(payload.swings.count, 1)
        XCTAssertEqual(payload.swings[0].index, 1)
        XCTAssertEqual(payload.swings[0].peakG, 9.4, accuracy: 0.001)
        let latitude = try XCTUnwrap(payload.swings[0].location?.latitude)
        XCTAssertEqual(latitude, 40.0, accuracy: 0.0001)
    }

    func testSessionPayloadDecoderDefaultsMissingSchemaToV1() throws {
        let data = try sessionJSON(
            schemaVersion: nil,
            sessionID: "round-legacy-no-schema",
            mode: "round",
            roundID: nil,
            includeSwing: false
        )
        let payload = try WatchSessionPayloadDecoder.decode(data)
        XCTAssertEqual(payload.schemaVersion, WatchSessionPayloadDecoder.currentSchemaVersion)
        XCTAssertNil(payload.roundID)
    }

    func testSessionPayloadDecoderRejectsUnsupportedSchemaAndRangeRoundLink() throws {
        let future = try sessionJSON(
            schemaVersion: 2,
            sessionID: "round-future",
            mode: "round",
            roundID: UUID(),
            includeSwing: false
        )
        XCTAssertThrowsError(try WatchSessionPayloadDecoder.decode(future)) { error in
            guard case .unsupportedSchema(let version) = error as? WatchSessionPayloadError else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(version, 2)
        }

        let rangeLinked = try sessionJSON(
            schemaVersion: 1,
            sessionID: "range-linked",
            mode: "range",
            roundID: UUID(),
            includeSwing: false
        )
        XCTAssertThrowsError(try WatchSessionPayloadDecoder.decode(rangeLinked)) { error in
            guard case .rangeHasRoundLink = error as? WatchSessionPayloadError else {
                return XCTFail("expected rangeHasRoundLink, got \(error)")
            }
        }
    }

    func testSessionPayloadDecoderRejectsUnsafeSessionIdentity() throws {
        let unsafe = try sessionJSON(
            schemaVersion: 1,
            sessionID: "round/../escape",
            mode: "round",
            roundID: nil,
            includeSwing: false
        )
        XCTAssertThrowsError(try WatchSessionPayloadDecoder.decode(unsafe)) { error in
            guard case .invalidSessionID = error as? WatchSessionPayloadError else {
                return XCTFail("expected invalidSessionID, got \(error)")
            }
        }
        XCTAssertFalse(WatchSessionPayloadDecoder.isSafeSessionID(""))
        XCTAssertFalse(WatchSessionPayloadDecoder.isSafeSessionID(String(repeating: "a", count: 181)))
        XCTAssertTrue(WatchSessionPayloadDecoder.isSafeSessionID("round-20260821T010000Z-ok"))
    }

    private func sessionJSON(
        schemaVersion: Int?,
        sessionID: String,
        mode: String,
        roundID: UUID?,
        includeSwing: Bool
    ) throws -> Data {
        var payload: [String: Any] = [
            "session_id": sessionID,
            "mode": mode,
            "started_at": "2026-08-21T01:00:00.000Z",
            "completed_at": "2026-08-21T01:30:00.000Z",
            "auto_threshold": true,
            "sample_rate_hz": 100,
            "swings": [] as [Any],
        ]
        if let schemaVersion {
            payload["schema_version"] = schemaVersion
        }
        if let roundID {
            payload["round_id"] = roundID.uuidString
        }
        if includeSwing {
            payload["swings"] = [
                [
                    "index": 1,
                    "timestamp": "2026-08-21T01:10:00.000Z",
                    "peak_g": 9.4,
                    "backswing_s": 0.78,
                    "downswing_s": 0.26,
                    "tempo_ratio": 3.0,
                    "tempo_frames": "24/8",
                    "hr_bpm": 108,
                    "location": [
                        "latitude": 40.0,
                        "longitude": -75.0,
                        "altitude": 60.0,
                        "horizontal_accuracy": 4.0,
                    ],
                ] as [String: Any],
            ]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

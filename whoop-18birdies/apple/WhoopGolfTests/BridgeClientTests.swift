import Foundation
import XCTest
@testable import WhoopGolf

final class BridgeRoundPayloadTests: XCTestCase {
    func testRoundRequestUsesBearerHeaderAndCanonicalBodyOnly() throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test/private",
            bearerToken: "device-secret"
        )
        let payload = try fixturePayload()

        let request = try WhoopBridgeClient.roundRequest(
            configuration: configuration,
            payload: payload
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://bridge.example.test/private/v1/rounds")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), Set([
            "date", "course", "holes", "par", "score", "startedAt", "endedAt"
        ]))
        XCTAssertEqual(object["date"] as? String, "2026-08-12")
        XCTAssertEqual(object["course"] as? String, "Torrey Pines South")
        XCTAssertEqual(object["holes"] as? Int, 18)
        XCTAssertEqual(object["par"] as? Int, 72)
        XCTAssertEqual(object["score"] as? Int, 84)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("device-secret"))
    }

    func testPayloadRequiresRealDateScoreParAndChronology() throws {
        let start = Date(timeIntervalSince1970: 1_786_533_000)
        XCTAssertThrowsError(
            try BridgeRoundPayload(
                localDate: "2026-02-30",
                course: "Course",
                holes: 18,
                par: 72,
                grossScore: 84,
                startedAt: start,
                endedAt: start.addingTimeInterval(60)
            )
        ) { XCTAssertEqual($0 as? WhoopBridgeError, .invalidRoundPayload) }

        let invalidEncodedPayload = Data(
            #"{"date":"2026-08-12","course":"Course","holes":18,"par":0,"score":84,"startedAt":"2026-08-12T12:00:00Z"}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(BridgeRoundPayload.self, from: invalidEncodedPayload)) {
            XCTAssertEqual($0 as? WhoopBridgeError, .invalidRoundPayload)
        }
        XCTAssertThrowsError(
            try BridgeRoundPayload(
                localDate: "2026-08-12",
                course: "Course",
                holes: 18,
                par: 0,
                grossScore: 84,
                startedAt: start,
                endedAt: start.addingTimeInterval(60)
            )
        ) { XCTAssertEqual($0 as? WhoopBridgeError, .invalidRoundPayload) }
        XCTAssertThrowsError(
            try BridgeRoundPayload(
                localDate: "2026-08-12",
                course: "Course",
                holes: 18,
                par: 72,
                grossScore: 84,
                startedAt: start,
                endedAt: start.addingTimeInterval(-1)
            )
        ) { XCTAssertEqual($0 as? WhoopBridgeError, .invalidRoundPayload) }
    }

    func testRoundPayloadRequiresFinishedCompleteScorecardAndUsesStartTimeZone() throws {
        let start = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T02:30:00Z")
        )
        var incomplete = GolfRound(
            courseName: "Travel Course",
            startedAt: start,
            holeCount: .nine,
            timeZoneIdentifier: "America/New_York"
        )
        incomplete.markFinished(at: start.addingTimeInterval(10_800))
        XCTAssertThrowsError(try BridgeRoundPayload(round: incomplete)) {
            XCTAssertEqual($0 as? WhoopBridgeError, .invalidRoundPayload)
        }

        let completeHoles = (1...9).map { HoleResult(number: $0, par: 4, strokes: 5) }
        var complete = GolfRound(
            courseName: "Travel Course",
            startedAt: start,
            holeCount: .nine,
            timeZoneIdentifier: "America/New_York",
            holes: completeHoles
        )
        complete.markFinished(at: start.addingTimeInterval(10_800))

        let payload = try BridgeRoundPayload(round: complete)
        XCTAssertEqual(payload.localDate, "2026-08-12")
        XCTAssertEqual(payload.holes, 9)
        XCTAssertEqual(payload.par, 36)
        XCTAssertEqual(payload.grossScore, 45)
    }

    func testClientDecodesAcknowledgementAndMapsStableErrors() async throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let ok = RecordingBridgeTransport(
            result: BridgeHTTPResult(
                data: Data(
                    #"{"apiVersion":1,"accepted":1,"stored":4,"dates":["2026-08-12"]}"#.utf8
                ),
                statusCode: 200
            )
        )
        let client = WhoopBridgeClient(configuration: configuration, transport: ok)
        let response = try await client.uploadRound(fixturePayload())
        XCTAssertEqual(response.accepted, 1)
        XCTAssertEqual(response.stored, 4)
        let maximumResponseLimit = await ok.maximumResponseLimit()
        XCTAssertEqual(maximumResponseLimit, 1_048_576)

        let unauthorized = RecordingBridgeTransport(
            result: BridgeHTTPResult(data: Data(), statusCode: 401)
        )
        let unauthorizedClient = WhoopBridgeClient(
            configuration: configuration,
            transport: unauthorized
        )
        do {
            _ = try await unauthorizedClient.uploadRound(fixturePayload())
            XCTFail("Expected an authentication error")
        } catch {
            XCTAssertEqual(error as? WhoopBridgeError, .unauthorised)
        }
    }

    func testClientRejectsMismatchedAcknowledgement() async throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let transport = RecordingBridgeTransport(
            result: BridgeHTTPResult(
                data: Data(
                    #"{"apiVersion":1,"accepted":1,"stored":1,"dates":["2026-08-11"]}"#.utf8
                ),
                statusCode: 200
            )
        )
        let client = WhoopBridgeClient(configuration: configuration, transport: transport)
        do {
            _ = try await client.uploadRound(fixturePayload())
            XCTFail("Expected invalidResponse")
        } catch {
            XCTAssertEqual(error as? WhoopBridgeError, .invalidResponse)
        }
    }

    func testClientRejectsOversizedInjectedResponse() async throws {
        let configuration = try BridgeConfiguration(
            baseURLString: "https://bridge.example.test",
            bearerToken: "device-secret"
        )
        let transport = RecordingBridgeTransport(
            result: BridgeHTTPResult(data: Data(count: 1_048_577), statusCode: 200)
        )
        let client = WhoopBridgeClient(configuration: configuration, transport: transport)
        do {
            _ = try await client.uploadRound(fixturePayload())
            XCTFail("Expected responseTooLarge")
        } catch {
            XCTAssertEqual(error as? WhoopBridgeError, .responseTooLarge)
        }
    }

    private func fixturePayload() throws -> BridgeRoundPayload {
        try BridgeRoundPayload(
            localDate: "2026-08-12",
            course: "Torrey Pines South",
            holes: 18,
            par: 72,
            grossScore: 84,
            startedAt: Date(timeIntervalSince1970: 1_786_533_000),
            endedAt: Date(timeIntervalSince1970: 1_786_548_300)
        )
    }
}

final class BridgeRoundOutboxTests: XCTestCase {
    func testEnqueueIsIdempotentAndPersistsAcrossInstances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = try fixturePayload()
        let first = BridgeRoundOutbox(
            directory: directory,
            now: { Date(timeIntervalSince1970: 1_786_548_300) }
        )

        let firstID = try await first.enqueue(payload)
        let secondID = try await first.enqueue(payload)
        let firstPending = try await first.pending()
        XCTAssertEqual(firstID, secondID)
        XCTAssertEqual(firstPending.count, 1)

        let reopened = BridgeRoundOutbox(directory: directory)
        let persisted = try await reopened.pending()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted[0].id, payload.outboxID)
        XCTAssertEqual(persisted[0].payload, payload)
    }

    func testFlushAcknowledgesOnlyAfterSuccessfulUpload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = BridgeRoundOutbox(directory: directory)
        let payload = try fixturePayload()
        try await outbox.enqueue(payload)

        let uploader = RecordingRoundUploader()
        let result = try await outbox.flush(using: uploader)
        let pending = try await outbox.pending()
        let uploaded = await uploader.payloads()
        XCTAssertEqual(result, BridgeRoundOutbox.FlushResult(delivered: 1, remaining: 0))
        XCTAssertEqual(pending, [])
        XCTAssertEqual(uploaded, [payload])
    }

    func testFailedFlushRetainsEntryForLaterRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = BridgeRoundOutbox(directory: directory)
        let payload = try fixturePayload()
        let id = try await outbox.enqueue(payload)

        do {
            _ = try await outbox.flush(using: FailingRoundUploader())
            XCTFail("Expected upload failure")
        } catch {
            XCTAssertEqual(error as? WhoopBridgeError, .serverUnavailable)
        }
        let pendingAfterFailure = try await outbox.pending()
        XCTAssertEqual(pendingAfterFailure.map(\.id), [id])

        let reopened = BridgeRoundOutbox(directory: directory)
        let result = try await reopened.flush(using: RecordingRoundUploader())
        XCTAssertEqual(result, BridgeRoundOutbox.FlushResult(delivered: 1, remaining: 0))
    }

    func testCorruptFileIsNotDiscardedOrReplaced() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("round-upload-outbox.json")
        let original = Data("not-json".utf8)
        try original.write(to: file)
        let outbox = BridgeRoundOutbox(directory: directory)

        do {
            _ = try await outbox.pending()
            XCTFail("Expected corrupt queue error")
        } catch {
            XCTAssertEqual(error as? BridgeRoundOutboxError, .corrupt)
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WhoopGolf-BridgeTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func fixturePayload() throws -> BridgeRoundPayload {
        try BridgeRoundPayload(
            localDate: "2026-08-12",
            course: "Torrey Pines South",
            holes: 18,
            par: 72,
            grossScore: 84,
            startedAt: Date(timeIntervalSince1970: 1_786_533_000),
            endedAt: Date(timeIntervalSince1970: 1_786_548_300)
        )
    }
}

private actor RecordingBridgeTransport: BridgeHTTPTransport {
    private let result: BridgeHTTPResult
    private var limit: Int?

    init(result: BridgeHTTPResult) {
        self.result = result
    }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult {
        limit = maximumResponseBytes
        return result
    }

    func maximumResponseLimit() -> Int? { limit }
}

private actor RecordingRoundUploader: BridgeRoundUploading {
    private var uploaded: [BridgeRoundPayload] = []

    func uploadRound(_ payload: BridgeRoundPayload) async throws -> BridgeRoundUploadResponse {
        uploaded.append(payload)
        return BridgeRoundUploadResponse(
            apiVersion: 1,
            accepted: 1,
            stored: uploaded.count,
            dates: [payload.localDate]
        )
    }

    func payloads() -> [BridgeRoundPayload] { uploaded }
}

private struct FailingRoundUploader: BridgeRoundUploading {
    func uploadRound(_ payload: BridgeRoundPayload) async throws -> BridgeRoundUploadResponse {
        throw WhoopBridgeError.serverUnavailable
    }
}

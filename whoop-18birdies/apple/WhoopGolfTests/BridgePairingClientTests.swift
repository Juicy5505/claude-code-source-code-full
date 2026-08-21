import CryptoKit
import Foundation
import XCTest
@testable import WhoopGolf

final class BridgePairingClientTests: XCTestCase {
    private let baseURL = "https://private-mac.private-tailnet.ts.net"
    private let now = Date(timeIntervalSince1970: 1_786_579_200)

    func testOfferIsStrictPrivateHTTPSAndNeverCarriesBearer() throws {
        let mac = Curve25519.KeyAgreement.PrivateKey()
        let offer = try BridgePairingOffer(
            baseURL: baseURL,
            sessionID: String(repeating: "a", count: 32),
            expiresAt: now.addingTimeInterval(120),
            macPublicKey: mac.publicKey.rawRepresentation
        )
        let data = try offer.encodedData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "protocol", "kind", "baseURL", "sessionID", "expiresAt", "macPublicKey"
        ]))
        XCTAssertNil(object["bearerToken"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("device-secret"))

        XCTAssertThrowsError(
            try BridgePairingOffer(
                baseURL: "https://example.com",
                sessionID: String(repeating: "a", count: 32),
                expiresAt: now.addingTimeInterval(120),
                macPublicKey: mac.publicKey.rawRepresentation
            )
        )
        var unknown = object
        unknown["token"] = "device-secret"
        XCTAssertThrowsError(
            try BridgePairingClient.pairingDecoder().decode(
                BridgePairingOffer.self,
                from: JSONSerialization.data(withJSONObject: unknown)
            )
        )
    }

    func testPairingRequestsKeepBootstrapAndProofOutOfURL() async throws {
        let fixture = try pairingFixture()
        let currentTime = now
        let response = try statusResponseData(
            session: fixture.session,
            status: "claimed"
        )
        let transport = PairingRecordingTransport(
            results: [BridgeHTTPResult(data: response, statusCode: 200)]
        )
        let privateKey = fixture.session.privateKey
        let client = BridgePairingClient(
            transport: transport,
            now: { currentTime },
            keyFactory: { privateKey }
        )
        _ = try await client.claim(offerData: fixture.offerData)
        let recordedRequests = await transport.requests()
        let request = try XCTUnwrap(recordedRequests.first)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/pair/v1/claim")
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["protocol", "sessionID", "phonePublicKey"]))
    }

    func testAuthenticatedEnvelopeOpensAndPersistsOnlyAfterStorageSucceeds() throws {
        let fixture = try pairingFixture()
        let sealed = try BridgePairingClient.sealForTesting(
            baseURL: baseURL,
            bearerToken: "device-secret",
            session: fixture.session,
            nonceData: Data(repeating: 7, count: 12)
        )
        let configuration = try BridgePairingClient.open(
            sealed: sealed,
            session: fixture.session
        )
        XCTAssertEqual(configuration.baseURL.absoluteString, baseURL)
        XCTAssertEqual(configuration.bearerToken, "device-secret")

        var forgedTag = try XCTUnwrap(Data(base64URLEncoded: sealed.tag))
        forgedTag[forgedTag.startIndex] ^= 0x01
        var forged = sealed
        forged = PairingSealedResponse(
            protocolVersion: forged.protocolVersion,
            sessionID: forged.sessionID,
            status: forged.status,
            nonce: forged.nonce,
            ciphertext: forged.ciphertext,
            tag: forgedTag.base64URLEncodedString()
        )
        XCTAssertThrowsError(try BridgePairingClient.open(sealed: forged, session: fixture.session)) {
            XCTAssertEqual($0 as? BridgePairingClientError, .authenticationFailed)
        }
    }

    func testCompleteStoresBeforeAcknowledgingAndRetriesSealedFetchSafely() async throws {
        let fixture = try pairingFixture()
        let currentTime = now
        let sealed = try BridgePairingClient.sealForTesting(
            baseURL: baseURL,
            bearerToken: "device-secret",
            session: fixture.session,
            nonceData: Data(repeating: 9, count: 12)
        )
        let sealedData = try JSONSerialization.data(withJSONObject: [
            "protocol": sealed.protocolVersion,
            "sessionID": sealed.sessionID,
            "status": sealed.status,
            "nonce": sealed.nonce,
            "ciphertext": sealed.ciphertext,
            "tag": sealed.tag,
        ])
        let transport = PairingRecordingTransport(results: [
            BridgeHTTPResult(data: sealedData, statusCode: 200),
            BridgeHTTPResult(data: Data(), statusCode: 204),
        ])
        let store = PairingCredentialRecorder()
        let client = BridgePairingClient(transport: transport, now: { currentTime })
        let configuration = try await client.complete(fixture.session, credentialStore: store)
        XCTAssertEqual(configuration.bearerToken, "device-secret")
        XCTAssertEqual(store.storedConfiguration()?.baseURL.absoluteString, baseURL)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.lastPathComponent), ["fetch", "ack"])
        XCTAssertTrue(requests.allSatisfy { $0.url?.query == nil })

        let failedStore = PairingCredentialRecorder(shouldFail: true)
        let noAckTransport = PairingRecordingTransport(results: [
            BridgeHTTPResult(data: sealedData, statusCode: 200),
        ])
        let noAckClient = BridgePairingClient(transport: noAckTransport, now: { currentTime })
        await XCTAssertThrowsErrorAsync(
            try await noAckClient.complete(fixture.session, credentialStore: failedStore),
            expected: .storageFailed
        )
        let noAckRequests = await noAckTransport.requests()
        XCTAssertEqual(noAckRequests.map(\.url?.lastPathComponent), ["fetch"])
    }

    private func pairingFixture() throws -> (
        offer: BridgePairingOffer,
        offerData: Data,
        session: BridgePairingSession
    ) {
        let mac = Curve25519.KeyAgreement.PrivateKey()
        let offer = try BridgePairingOffer(
            baseURL: baseURL,
            sessionID: String(repeating: "b", count: 32),
            expiresAt: now.addingTimeInterval(120),
            macPublicKey: mac.publicKey.rawRepresentation
        )
        let phone = Curve25519.KeyAgreement.PrivateKey()
        let sas = try BridgePairingClient.shortAuthenticationString(
            offer: offer,
            privateKey: phone
        )
        return (
            offer,
            try offer.encodedData(),
            BridgePairingSession(
                offer: offer,
                privateKey: phone,
                shortAuthenticationString: sas
            )
        )
    }

    private func statusResponseData(
        session: BridgePairingSession,
        status: String
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocol": 1,
            "sessionID": session.offer.sessionID,
            "expiresAt": BridgePairingClient.pairingDateFormatter().string(
                from: session.offer.expiresAt
            ),
            "shortAuthenticationString": session.shortAuthenticationString,
            "status": status,
        ])
    }
}

private actor PairingRecordingTransport: BridgeHTTPTransport {
    private var results: [BridgeHTTPResult]
    private var recorded: [URLRequest] = []

    init(results: [BridgeHTTPResult]) { self.results = results }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult {
        recorded.append(request)
        guard !results.isEmpty else { throw BridgePairingClientError.serverUnavailable }
        return results.removeFirst()
    }

    func requests() -> [URLRequest] { recorded }
}

private final class PairingCredentialRecorder: BridgePairingCredentialStoring, @unchecked Sendable {
    private let shouldFail: Bool
    private let lock = NSLock()
    private var configuration: BridgeConfiguration?

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func store(_ configuration: BridgeConfiguration) throws {
        if shouldFail { throw BridgePairingClientError.storageFailed }
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }

    func storedConfiguration() -> BridgeConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: BridgePairingClientError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? BridgePairingClientError, expected, file: file, line: line)
    }
}

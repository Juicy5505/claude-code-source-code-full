import CryptoKit
import Foundation

enum BridgePairingClientError: LocalizedError, Equatable, Sendable {
    case invalidOffer
    case expired
    case conflict
    case notReady
    case authenticationFailed
    case invalidResponse
    case serverUnavailable
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .invalidOffer: "The private bridge pairing code is invalid."
        case .expired: "The two-minute pairing session expired. Create a new one on the Mac."
        case .conflict: "This pairing session was already claimed by another device."
        case .notReady: "Compare the six-digit code and approve it on the Mac first."
        case .authenticationFailed: "The pairing codes or encrypted response did not authenticate."
        case .invalidResponse: "The private bridge returned an invalid pairing response."
        case .serverUnavailable: "The private Mac bridge is unavailable."
        case .storageFailed: "The paired bridge credential could not be saved securely."
        }
    }
}

private struct BridgePairingCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private enum BridgePairingStrictDecoding {
    static func requireExactKeys(
        _ decoder: Decoder,
        _ expected: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: BridgePairingCodingKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == expected else {
            throw BridgePairingClientError.invalidResponse
        }
    }
}

struct BridgePairingOffer: Codable, Equatable, Sendable {
    static let protocolVersion = 1
    static let kind = "whoopGolfBridgePairing"

    let baseURL: String
    let sessionID: String
    let expiresAt: Date
    let macPublicKey: Data

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol"
        case kind
        case baseURL
        case sessionID
        case expiresAt
        case macPublicKey
    }

    init(baseURL: String, sessionID: String, expiresAt: Date, macPublicKey: Data) throws {
        guard let canonical = Self.canonicalPrivateBaseURL(baseURL),
              canonical == baseURL,
              Self.isLowercaseSessionID(sessionID),
              expiresAt.timeIntervalSince1970.isFinite,
              macPublicKey.count == 32 else {
            throw BridgePairingClientError.invalidOffer
        }
        self.baseURL = baseURL
        self.sessionID = sessionID
        self.expiresAt = expiresAt
        self.macPublicKey = macPublicKey
    }

    init(from decoder: Decoder) throws {
        try BridgePairingStrictDecoding.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .protocolVersion) == Self.protocolVersion,
              try values.decode(String.self, forKey: .kind) == Self.kind,
              let publicKey = Data(
                  base64URLEncoded: try values.decode(String.self, forKey: .macPublicKey)
              )
        else { throw BridgePairingClientError.invalidOffer }
        try self.init(
            baseURL: values.decode(String.self, forKey: .baseURL),
            sessionID: values.decode(String.self, forKey: .sessionID),
            expiresAt: values.decode(Date.self, forKey: .expiresAt),
            macPublicKey: publicKey
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.protocolVersion, forKey: .protocolVersion)
        try values.encode(Self.kind, forKey: .kind)
        try values.encode(baseURL, forKey: .baseURL)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(expiresAt, forKey: .expiresAt)
        try values.encode(macPublicKey.base64URLEncodedString(), forKey: .macPublicKey)
    }

    func encodedData() throws -> Data {
        try BridgePairingClient.pairingEncoder().encode(self)
    }

    static func canonicalPrivateBaseURL(_ value: String) -> String? {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let rawHost = components.host,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return nil }
        let host = rawHost.lowercased()
        guard host.hasSuffix(".ts.net"), host.split(separator: ".").count >= 4 else { return nil }
        components.scheme = "https"
        components.host = host
        while components.path.count > 1, components.path.last == "/" {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        guard let normalized = components.url?.absoluteString else { return nil }
        return normalized
    }

    private static func isLowercaseSessionID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
    }
}

final class BridgePairingSession: @unchecked Sendable {
    let offer: BridgePairingOffer
    let phonePublicKey: Data
    let shortAuthenticationString: String
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    init(
        offer: BridgePairingOffer,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        shortAuthenticationString: String
    ) {
        self.offer = offer
        self.privateKey = privateKey
        self.phonePublicKey = privateKey.publicKey.rawRepresentation
        self.shortAuthenticationString = shortAuthenticationString
    }
}

protocol BridgePairingCredentialStoring: Sendable {
    func store(_ configuration: BridgeConfiguration) throws
}

struct KeychainBridgePairingCredentialStore: BridgePairingCredentialStoring, @unchecked Sendable {
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func store(_ configuration: BridgeConfiguration) throws {
        try keychain.setPairedBridgeConfiguration(configuration)
    }
}

actor BridgePairingClient {
    private let transport: any BridgeHTTPTransport
    private let now: @Sendable () -> Date
    private let keyFactory: @Sendable () -> Curve25519.KeyAgreement.PrivateKey
    private let maximumBytes = 4_096

    init(
        transport: any BridgeHTTPTransport = URLSessionBridgePairingTransport(),
        now: @escaping @Sendable () -> Date = { .now },
        keyFactory: @escaping @Sendable () -> Curve25519.KeyAgreement.PrivateKey = {
            Curve25519.KeyAgreement.PrivateKey()
        }
    ) {
        self.transport = transport
        self.now = now
        self.keyFactory = keyFactory
    }

    func claim(offerData: Data) async throws -> BridgePairingSession {
        guard offerData.count <= maximumBytes else { throw BridgePairingClientError.invalidOffer }
        let offer: BridgePairingOffer
        do { offer = try Self.pairingDecoder().decode(BridgePairingOffer.self, from: offerData) }
        catch { throw BridgePairingClientError.invalidOffer }
        let current = now()
        guard current.timeIntervalSince1970.isFinite,
              offer.expiresAt > current.addingTimeInterval(-30),
              offer.expiresAt <= current.addingTimeInterval(5 * 60) else {
            throw BridgePairingClientError.expired
        }

        let privateKey = keyFactory()
        let body = PairingClaimBody(
            protocolVersion: 1,
            sessionID: offer.sessionID,
            phonePublicKey: privateKey.publicKey.rawRepresentation.base64URLEncodedString()
        )
        let result = try await send(Self.request(offer: offer, path: "claim", body: body))
        let response: PairingStatusResponse = try decodeResponse(result, expectedStatus: 200)
        try validate(response: response, offer: offer)
        let localSAS = try Self.shortAuthenticationString(offer: offer, privateKey: privateKey)
        guard Self.constantTimeEqual(localSAS, response.shortAuthenticationString) else {
            throw BridgePairingClientError.authenticationFailed
        }
        return BridgePairingSession(
            offer: offer,
            privateKey: privateKey,
            shortAuthenticationString: localSAS
        )
    }

    /// Invoke only after the golfer explicitly confirms that the Mac and phone
    /// display the same short authentication string.
    func confirm(_ session: BridgePairingSession) async throws {
        let body = try proofBody(session: session, purpose: "phone-confirm")
        let result = try await send(Self.request(offer: session.offer, path: "confirm", body: body))
        let response: PairingStatusResponse = try decodeResponse(result, expectedStatus: 200)
        try validate(response: response, offer: session.offer)
        guard response.shortAuthenticationString == session.shortAuthenticationString,
              response.status == "phoneConfirmed" || response.status == "approved" else {
            throw BridgePairingClientError.authenticationFailed
        }
    }

    /// Retrieves and stores the credential only after both confirmations. The
    /// acknowledgement is sent after secure local storage succeeds.
    @discardableResult
    func complete(
        _ session: BridgePairingSession,
        credentialStore: any BridgePairingCredentialStoring
    ) async throws -> BridgeConfiguration {
        let fetch = try proofBody(session: session, purpose: "phone-fetch")
        let fetchResult = try await send(Self.request(offer: session.offer, path: "fetch", body: fetch))
        let sealed: PairingSealedResponse = try decodeResponse(fetchResult, expectedStatus: 200)
        guard sealed.protocolVersion == 1,
              sealed.sessionID == session.offer.sessionID,
              sealed.status == "sealed" else { throw BridgePairingClientError.invalidResponse }
        let configuration = try Self.open(sealed: sealed, session: session)
        do { try credentialStore.store(configuration) }
        catch { throw BridgePairingClientError.storageFailed }

        let acknowledgement = try proofBody(session: session, purpose: "phone-ack")
        let ackResult = try await send(
            Self.request(offer: session.offer, path: "ack", body: acknowledgement)
        )
        guard ackResult.statusCode == 204, ackResult.data.isEmpty else {
            throw Self.error(for: ackResult.statusCode)
        }
        return configuration
    }

    private func proofBody(
        session: BridgePairingSession,
        purpose: String
    ) throws -> PairingProofBody {
        PairingProofBody(
            protocolVersion: 1,
            sessionID: session.offer.sessionID,
            phonePublicKey: session.phonePublicKey.base64URLEncodedString(),
            proof: try Self.proof(offer: session.offer, privateKey: session.privateKey, purpose: purpose)
        )
    }

    private func send(_ request: URLRequest) async throws -> BridgeHTTPResult {
        do {
            let result = try await transport.send(request, maximumResponseBytes: maximumBytes)
            guard result.data.count <= maximumBytes else { throw BridgePairingClientError.invalidResponse }
            return result
        } catch let error as BridgePairingClientError {
            throw error
        } catch {
            throw BridgePairingClientError.serverUnavailable
        }
    }

    private func decodeResponse<T: Decodable>(
        _ result: BridgeHTTPResult,
        expectedStatus: Int
    ) throws -> T {
        guard result.statusCode == expectedStatus else { throw Self.error(for: result.statusCode) }
        do { return try Self.pairingDecoder().decode(T.self, from: result.data) }
        catch { throw BridgePairingClientError.invalidResponse }
    }

    private func validate(response: PairingStatusResponse, offer: BridgePairingOffer) throws {
        guard response.protocolVersion == 1,
              response.sessionID == offer.sessionID,
              response.expiresAt == offer.expiresAt,
              response.shortAuthenticationString.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil,
              ["claimed", "phoneConfirmed", "approved"].contains(response.status) else {
            throw BridgePairingClientError.invalidResponse
        }
    }

    static func request<T: Encodable>(
        offer: BridgePairingOffer,
        path: String,
        body: T
    ) throws -> URLRequest {
        guard ["claim", "confirm", "fetch", "ack"].contains(path),
              let base = URL(string: offer.baseURL) else { throw BridgePairingClientError.invalidOffer }
        let url = base
            .appendingPathComponent("pair")
            .appendingPathComponent("v1")
            .appendingPathComponent(path)
        guard url.query == nil, url.fragment == nil else { throw BridgePairingClientError.invalidOffer }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let body = try pairingEncoder().encode(body)
        guard body.count <= 4_096 else { throw BridgePairingClientError.invalidOffer }
        request.httpBody = body
        return request
    }

    static func shortAuthenticationString(
        offer: BridgePairingOffer,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> String {
        let key = try derivedKey(offer: offer, privateKey: privateKey, purpose: "sas")
        let digest = Data(HMAC<SHA256>.authenticationCode(for: transcript(offer, privateKey), using: key))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }

    static func proof(
        offer: BridgePairingOffer,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        purpose: String
    ) throws -> String {
        let key = try derivedKey(
            offer: offer,
            privateKey: privateKey,
            purpose: "proof:\(purpose)"
        )
        var message = transcript(offer, privateKey)
        message.append(0x1f)
        message.append(contentsOf: Data(purpose.utf8))
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
            .base64URLEncodedString()
    }

    static func open(
        sealed: PairingSealedResponse,
        session: BridgePairingSession
    ) throws -> BridgeConfiguration {
        guard let nonceData = Data(base64URLEncoded: sealed.nonce), nonceData.count == 12,
              let ciphertext = Data(base64URLEncoded: sealed.ciphertext), !ciphertext.isEmpty,
              let tag = Data(base64URLEncoded: sealed.tag), tag.count == 16 else {
            throw BridgePairingClientError.invalidResponse
        }
        do {
            let key = try derivedKey(
                offer: session.offer,
                privateKey: session.privateKey,
                purpose: "seal"
            )
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext = try AES.GCM.open(
                box,
                using: key,
                authenticating: Data("whoop-golf-bridge-pairing-v1".utf8)
            )
            let payload = try pairingDecoder().decode(PairingPlaintext.self, from: plaintext)
            guard payload.protocolVersion == 1, payload.baseURL == session.offer.baseURL else {
                throw BridgePairingClientError.authenticationFailed
            }
            return try BridgeConfiguration(
                baseURLString: payload.baseURL,
                bearerToken: payload.bearerToken
            )
        } catch let error as BridgePairingClientError {
            throw error
        } catch {
            throw BridgePairingClientError.authenticationFailed
        }
    }

    static func sealForTesting(
        baseURL: String,
        bearerToken: String,
        session: BridgePairingSession,
        nonceData: Data
    ) throws -> PairingSealedResponse {
        guard nonceData.count == 12 else { throw BridgePairingClientError.invalidResponse }
        let key = try derivedKey(
            offer: session.offer,
            privateKey: session.privateKey,
            purpose: "seal"
        )
        let plaintext = try pairingEncoder().encode(
            PairingPlaintext(
                protocolVersion: 1,
                baseURL: baseURL,
                bearerToken: bearerToken
            )
        )
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: AES.GCM.Nonce(data: nonceData),
            authenticating: Data("whoop-golf-bridge-pairing-v1".utf8)
        )
        return PairingSealedResponse(
            protocolVersion: 1,
            sessionID: session.offer.sessionID,
            status: "sealed",
            nonce: nonceData.base64URLEncodedString(),
            ciphertext: box.ciphertext.base64URLEncodedString(),
            tag: box.tag.base64URLEncodedString()
        )
    }

    private static func derivedKey(
        offer: BridgePairingOffer,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        purpose: String
    ) throws -> SymmetricKey {
        do {
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: offer.macPublicKey)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            return shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(hexString: offer.sessionID),
                sharedInfo: Data("whoop-golf-pair-v1:\(purpose)".utf8),
                outputByteCount: 32
            )
        } catch {
            throw BridgePairingClientError.invalidOffer
        }
    }

    private static func transcript(
        _ offer: BridgePairingOffer,
        _ privateKey: Curve25519.KeyAgreement.PrivateKey
    ) -> Data {
        [
            "whoop-golf-bridge-pairing-v1",
            offer.sessionID,
            offer.baseURL,
            pairingDateFormatter().string(from: offer.expiresAt),
            offer.macPublicKey.base64URLEncodedString(),
            privateKey.publicKey.rawRepresentation.base64URLEncodedString(),
        ].joined(separator: "\u{001f}").data(using: .utf8)!
    }

    private static func error(for status: Int) -> BridgePairingClientError {
        switch status {
        case 401: .authenticationFailed
        case 409: .conflict
        case 410: .expired
        case 425: .notReady
        case 500...599: .serverUnavailable
        default: .invalidResponse
        }
    }

    private static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let lhs = Array(left.utf8)
        let rhs = Array(right.utf8)
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }

    static func pairingEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .formatted(pairingDateFormatter())
        return encoder
    }

    static func pairingDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(pairingDateFormatter())
        return decoder
    }

    static func pairingDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }
}

private struct PairingClaimBody: Encodable {
    let protocolVersion: Int
    let sessionID: String
    let phonePublicKey: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", sessionID, phonePublicKey
    }
}

private struct PairingProofBody: Encodable {
    let protocolVersion: Int
    let sessionID: String
    let phonePublicKey: String
    let proof: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", sessionID, phonePublicKey, proof
    }
}

private struct PairingStatusResponse: Decodable {
    let protocolVersion: Int
    let sessionID: String
    let expiresAt: Date
    let shortAuthenticationString: String
    let status: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol", sessionID, expiresAt, shortAuthenticationString, status
    }

    init(from decoder: Decoder) throws {
        try BridgePairingStrictDecoding.requireExactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        shortAuthenticationString = try values.decode(String.self, forKey: .shortAuthenticationString)
        status = try values.decode(String.self, forKey: .status)
    }
}

struct PairingSealedResponse: Decodable {
    let protocolVersion: Int
    let sessionID: String
    let status: String
    let nonce: String
    let ciphertext: String
    let tag: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol", sessionID, status, nonce, ciphertext, tag
    }

    init(
        protocolVersion: Int,
        sessionID: String,
        status: String,
        nonce: String,
        ciphertext: String,
        tag: String
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.status = status
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        try BridgePairingStrictDecoding.requireExactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        status = try values.decode(String.self, forKey: .status)
        nonce = try values.decode(String.self, forKey: .nonce)
        ciphertext = try values.decode(String.self, forKey: .ciphertext)
        tag = try values.decode(String.self, forKey: .tag)
    }
}

private struct PairingPlaintext: Codable {
    let protocolVersion: Int
    let baseURL: String
    let bearerToken: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol", baseURL, bearerToken
    }

    init(protocolVersion: Int, baseURL: String, bearerToken: String) {
        self.protocolVersion = protocolVersion
        self.baseURL = baseURL
        self.bearerToken = bearerToken
    }

    init(from decoder: Decoder) throws {
        try BridgePairingStrictDecoding.requireExactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        bearerToken = try values.decode(String.self, forKey: .bearerToken)
    }
}

private final class URLSessionBridgePairingTransport: BridgeHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult {
        let (data, response) = try await session.data(for: request)
        guard data.count <= maximumResponseBytes,
              let http = response as? HTTPURLResponse else {
            throw BridgePairingClientError.invalidResponse
        }
        return BridgeHTTPResult(data: data, statusCode: http.statusCode)
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        guard value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        guard let decoded = Data(base64Encoded: base64),
              decoded.base64URLEncodedString() == value else { return nil }
        self = decoded
    }

    init(hexString: String) {
        self.init(stride(from: 0, to: hexString.count, by: 2).compactMap { offset in
            let start = hexString.index(hexString.startIndex, offsetBy: offset)
            let end = hexString.index(start, offsetBy: 2)
            return UInt8(hexString[start..<end], radix: 16)
        })
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

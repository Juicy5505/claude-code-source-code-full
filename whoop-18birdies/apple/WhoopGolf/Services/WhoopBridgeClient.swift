import CryptoKit
import Foundation

struct BridgeConfiguration: Sendable {
    let baseURL: URL
    let bearerToken: String

    init(baseURLString: String, bearerToken: String) throws {
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              bearerToken == trimmedToken,
              (1...512).contains(bearerToken.utf8.count),
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              bearerToken.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw WhoopBridgeError.invalidConfiguration }
        self.baseURL = url
        self.bearerToken = bearerToken
    }
}

enum WhoopBridgeError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case invalidRoundPayload
    case unauthorised
    case noData
    case serverUnavailable
    case invalidResponse
    case requestTooLarge
    case responseTooLarge
    case motionRequestNotFound
    case motionRequestConflict
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter the private HTTPS bridge address and its device token."
        case .invalidRoundPayload: "The round contains invalid or incomplete upload fields."
        case .unauthorised: "The bridge rejected this device token."
        case .noData: "No cached WHOOP physiology exists for this date."
        case .serverUnavailable: "The Mac bridge is not available right now."
        case .invalidResponse: "The bridge returned an unreadable response."
        case .requestTooLarge: "The bridge request exceeded the safe size limit."
        case .responseTooLarge: "The bridge response exceeded the safe size limit."
        case .motionRequestNotFound: "No WHOOP motion request exists for this round."
        case .motionRequestConflict: "A different WHOOP motion request already exists for this round."
        case .http(let code): "The bridge returned HTTP \(code)."
        }
    }
}

/// Exact fields accepted by POST /v1/rounds. Par and gross score are required;
/// callers must never manufacture either value from score-to-par.
struct BridgeRoundPayload: Codable, Hashable, Sendable {
    let localDate: String
    let course: String
    let holes: Int
    let par: Int
    let grossScore: Int
    let startedAt: Date
    let endedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case localDate = "date"
        case course
        case holes
        case par
        case grossScore = "score"
        case startedAt
        case endedAt
    }

    init(
        localDate: String,
        course: String,
        holes: Int,
        par: Int,
        grossScore: Int,
        startedAt: Date,
        endedAt: Date?
    ) throws {
        let trimmedCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isCalendarDate(localDate),
              !trimmedCourse.isEmpty,
              trimmedCourse.utf8.count <= 200,
              trimmedCourse.rangeOfCharacter(from: .controlCharacters) == nil,
              (1...36).contains(holes),
              (1...200).contains(par),
              (1...400).contains(grossScore),
              Self.isSupportedTimestamp(startedAt),
              endedAt.map(Self.isSupportedTimestamp) != false,
              endedAt.map({ $0 >= startedAt }) != false
        else { throw WhoopBridgeError.invalidRoundPayload }

        self.localDate = localDate
        self.course = trimmedCourse
        self.holes = holes
        self.par = par
        self.grossScore = grossScore
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    init(round: GolfRound) throws {
        guard round.isFinished,
              let grossScore = round.grossScore,
              let totalPar = round.totalPar,
              let endedAt = round.endedAt else {
            throw WhoopBridgeError.invalidRoundPayload
        }
        try self.init(
            localDate: round.localDate,
            course: round.courseName,
            holes: round.holeCount.rawValue,
            par: totalPar,
            grossScore: grossScore,
            startedAt: round.startedAt,
            endedAt: endedAt
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            localDate: values.decode(String.self, forKey: .localDate),
            course: values.decode(String.self, forKey: .course),
            holes: values.decode(Int.self, forKey: .holes),
            par: values.decode(Int.self, forKey: .par),
            grossScore: values.decode(Int.self, forKey: .grossScore),
            startedAt: values.decode(Date.self, forKey: .startedAt),
            endedAt: values.decodeIfPresent(Date.self, forKey: .endedAt)
        )
    }

    /// Stable across launches and independent of queue order. This identifier
    /// remains local; the server derives its own round identity from the
    /// canonical date/course/hole fields already present in the JSON body.
    var outboxID: String {
        let fields = [
            localDate,
            course,
            String(holes),
            String(par),
            String(grossScore),
            String(Int64(startedAt.timeIntervalSince1970.rounded(.towardZero))),
            endedAt.map {
                String(Int64($0.timeIntervalSince1970.rounded(.towardZero)))
            } ?? "nil"
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isCalendarDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard value.count == 10,
              parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...9_999).contains(year)
        else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }

    private static func isSupportedTimestamp(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
            && date >= .distantPast
            && date <= .distantFuture
    }
}

struct BridgeRoundUploadResponse: Codable, Equatable, Sendable {
    let apiVersion: Int
    let accepted: Int
    let stored: Int
    let dates: [String]
}

struct BridgeHTTPResult: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { normalized, header in
            normalized[header.key.lowercased()] = header.value
        }
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

protocol BridgeHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult
}

/// Streams at most the configured number of bytes into memory. A declared or
/// actual oversized response is rejected before decoding.
private final class URLSessionBridgeTransport: BridgeHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> BridgeHTTPResult {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhoopBridgeError.invalidResponse
        }
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            throw WhoopBridgeError.responseTooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw WhoopBridgeError.responseTooLarge
            }
            data.append(byte)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key).lowercased()] = String(describing: field.value)
        }
        return BridgeHTTPResult(data: data, statusCode: http.statusCode, headers: headers)
    }
}

protocol BridgeRoundUploading: Sendable {
    func uploadRound(_ payload: BridgeRoundPayload) async throws -> BridgeRoundUploadResponse
}

enum WhoopMotionPullResult: Equatable, Sendable {
    case pending
    case notModified(etag: String)
    case available(envelope: WhoopMotionEnvelope, payload: Data, etag: String)
}

actor WhoopBridgeClient: BridgeRoundUploading {
    private let configuration: BridgeConfiguration
    private let transport: any BridgeHTTPTransport
    private let decoder: JSONDecoder
    private let maximumRequestBytes = 1_000_000
    private let maximumResponseBytes = 1_048_576
    private let now: @Sendable () -> Date

    init(configuration: BridgeConfiguration) {
        self.configuration = configuration
        self.transport = URLSessionBridgeTransport()
        self.decoder = Self.makeDecoder()
        self.now = { .now }
    }

    init(
        configuration: BridgeConfiguration,
        transport: any BridgeHTTPTransport,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.decoder = Self.makeDecoder()
        self.now = now
    }

    func day(_ localDate: String) async throws -> DayResponse {
        guard Self.isCalendarDate(localDate) else { throw WhoopBridgeError.invalidResponse }
        let request = try Self.dayRequest(configuration: configuration, localDate: localDate)
        let result = try await sendWithRetry(request)
        switch result.statusCode {
        case 200:
            do {
                let response = try decoder.decode(DayResponse.self, from: result.data)
                guard try Self.isStrictlyValidDayResponse(
                    response,
                    data: result.data,
                    expectedDate: localDate,
                    now: now()
                ) else {
                    throw WhoopBridgeError.invalidResponse
                }
                return response
            } catch {
                if let bridgeError = error as? WhoopBridgeError { throw bridgeError }
                throw WhoopBridgeError.invalidResponse
            }
        case 401: throw WhoopBridgeError.unauthorised
        case 404: throw WhoopBridgeError.noData
        default: throw WhoopBridgeError.http(result.statusCode)
        }
    }

    func uploadRound(_ payload: BridgeRoundPayload) async throws -> BridgeRoundUploadResponse {
        let request = try Self.roundRequest(
            configuration: configuration,
            payload: payload,
            maximumRequestBytes: maximumRequestBytes
        )
        let result = try await sendWithRetry(request)
        switch result.statusCode {
        case 200:
            let response: BridgeRoundUploadResponse
            do {
                response = try decoder.decode(BridgeRoundUploadResponse.self, from: result.data)
            } catch {
                throw WhoopBridgeError.invalidResponse
            }
            guard response.apiVersion == 1,
                  response.accepted >= 1,
                  response.stored >= 1,
                  response.dates.contains(payload.localDate)
            else { throw WhoopBridgeError.invalidResponse }
            return response
        case 400: throw WhoopBridgeError.invalidRoundPayload
        case 401: throw WhoopBridgeError.unauthorised
        case 413: throw WhoopBridgeError.requestTooLarge
        default: throw WhoopBridgeError.http(result.statusCode)
        }
    }

    /// Creates an idempotent delayed WHOOP 5 historical-motion request. The
    /// request contains only the local round identity and its time window.
    func requestWhoopMotion(_ payload: WhoopMotionRequest) async throws {
        let request = try Self.whoopMotionRequest(
            configuration: configuration,
            payload: payload,
            maximumRequestBytes: maximumRequestBytes
        )
        let result = try await sendWithRetry(request)
        switch result.statusCode {
        case 202:
            let response: WhoopMotionPendingResponse
            do {
                response = try decoder.decode(WhoopMotionPendingResponse.self, from: result.data)
            } catch {
                throw WhoopBridgeError.invalidResponse
            }
            guard response.roundID == payload.roundID else {
                throw WhoopBridgeError.invalidResponse
            }
        case 400: throw WhoopBridgeError.invalidResponse
        case 401: throw WhoopBridgeError.unauthorised
        case 409: throw WhoopBridgeError.motionRequestConflict
        case 413: throw WhoopBridgeError.requestTooLarge
        default: throw WhoopBridgeError.http(result.statusCode)
        }
    }

    /// Pulls a derived swing-event envelope. A 200 response retains its exact
    /// bytes for protected import storage, and its strong ETag must equal the
    /// SHA-256 of those bytes. No raw frame or GPS response is accepted by the
    /// strict envelope decoder.
    func pullWhoopMotion(
        roundID: UUID,
        ifNoneMatch etag: String? = nil
    ) async throws -> WhoopMotionPullResult {
        let request = try Self.whoopMotionPullRequest(
            configuration: configuration,
            roundID: roundID,
            ifNoneMatch: etag
        )
        let result = try await sendWithRetry(request)
        switch result.statusCode {
        case 200:
            guard let responseETag = result.header("etag"),
                  let digest = Self.strongSHA256ETagDigest(responseETag),
                  digest == Self.sha256Hex(result.data) else {
                throw WhoopBridgeError.invalidResponse
            }
            let envelope: WhoopMotionEnvelope
            do {
                envelope = try decoder.decode(WhoopMotionEnvelope.self, from: result.data)
            } catch {
                throw WhoopBridgeError.invalidResponse
            }
            guard envelope.roundID == roundID else { throw WhoopBridgeError.invalidResponse }
            return .available(envelope: envelope, payload: result.data, etag: responseETag)
        case 202:
            let response: WhoopMotionPendingResponse
            do {
                response = try decoder.decode(WhoopMotionPendingResponse.self, from: result.data)
            } catch {
                throw WhoopBridgeError.invalidResponse
            }
            guard response.roundID == roundID else { throw WhoopBridgeError.invalidResponse }
            return .pending
        case 304:
            guard result.data.isEmpty, let etag else { throw WhoopBridgeError.invalidResponse }
            return .notModified(etag: etag)
        case 401: throw WhoopBridgeError.unauthorised
        case 404: throw WhoopBridgeError.motionRequestNotFound
        default: throw WhoopBridgeError.http(result.statusCode)
        }
    }

    static func roundRequest(
        configuration: BridgeConfiguration,
        payload: BridgeRoundPayload,
        maximumRequestBytes: Int = 1_000_000
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("rounds")
        var request = authenticatedRequest(url: endpoint, configuration: configuration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = Self.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw WhoopBridgeError.invalidRoundPayload
        }
        guard body.count <= maximumRequestBytes else { throw WhoopBridgeError.requestTooLarge }
        request.httpBody = body
        return request
    }

    static func whoopMotionRequest(
        configuration: BridgeConfiguration,
        payload: WhoopMotionRequest,
        maximumRequestBytes: Int = 1_000_000
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("whoop-motion")
            .appendingPathComponent("requests")
        var request = authenticatedRequest(url: endpoint, configuration: configuration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = Self.makeEncoder()
        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw WhoopBridgeError.invalidResponse
        }
        guard body.count <= maximumRequestBytes else { throw WhoopBridgeError.requestTooLarge }
        request.httpBody = body
        return request
    }

    static func whoopMotionPullRequest(
        configuration: BridgeConfiguration,
        roundID: UUID,
        ifNoneMatch etag: String? = nil
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("whoop-motion")
            .appendingPathComponent("rounds")
            .appendingPathComponent(roundID.uuidString.lowercased())
        var request = authenticatedRequest(url: endpoint, configuration: configuration)
        request.httpMethod = "GET"
        if let etag {
            guard isValidStrongMotionETag(etag) else {
                throw WhoopBridgeError.invalidConfiguration
            }
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    private static func dayRequest(
        configuration: BridgeConfiguration,
        localDate: String
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("day")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WhoopBridgeError.invalidConfiguration
        }
        components.queryItems = [URLQueryItem(name: "date", value: localDate)]
        guard let url = components.url else { throw WhoopBridgeError.invalidConfiguration }
        var request = authenticatedRequest(url: url, configuration: configuration)
        request.httpMethod = "GET"
        return request
    }

    private static func authenticatedRequest(
        url: URL,
        configuration: BridgeConfiguration
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func isValidStrongMotionETag(_ etag: String) -> Bool {
        strongSHA256ETagDigest(etag) != nil
    }

    private static func strongSHA256ETagDigest(_ etag: String) -> String? {
        guard etag.utf8.count == 66,
              etag.first == "\"", etag.last == "\"" else { return nil }
        let digest = String(etag.dropFirst().dropLast())
        return WhoopMotionEnvelope.isLowercaseSHA256(digest) ? digest : nil
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Rejects schema drift and provenance confusion at the network boundary.
    /// WHOOP physiology must identify itself as cached provider data, while
    /// golf readiness must identify itself as our derived (non-WHOOP) model.
    private static func isStrictlyValidDayResponse(
        _ response: DayResponse,
        data: Data,
        expectedDate: String,
        now: Date
    ) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set([
                "apiVersion", "date", "generatedAt", "freshness", "physiology", "golfReadiness"
              ]),
              let freshness = root["freshness"] as? [String: Any],
              Set(freshness.keys) == Set(["lastCompleteSyncAt", "stale", "staleAfterSeconds"]),
              let physiology = root["physiology"] as? [String: Any],
              Set(physiology.keys) == Set([
                "status", "recoveryPercent", "hrvRmssdMs", "restingHeartRateBpm",
                "spo2Percent", "skinTemperatureCelsius", "sleepHours",
                "sleepPerformancePercent", "sleepEfficiencyPercent", "dayStrain",
                "priorDayStrain", "provenance"
              ]),
              let readiness = root["golfReadiness"] as? [String: Any],
              Set(readiness.keys).isSubset(of: Set([
                "available", "score", "verdict", "personalised", "components", "advice",
                "reason", "provenance"
              ])),
              Set(["available", "score", "verdict", "personalised", "components", "advice", "provenance"])
                .isSubset(of: Set(readiness.keys)),
              let providerProvenance = physiology["provenance"] as? [String: Any],
              Set(providerProvenance.keys) == Set(["kind", "provider", "source"]),
              providerProvenance["kind"] as? String == "providerData",
              providerProvenance["provider"] as? String == "WHOOP",
              providerProvenance["source"] as? String == "localSqliteCache",
              let derivedProvenance = readiness["provenance"] as? [String: Any],
              Set(derivedProvenance.keys) == Set([
                "kind", "producer", "model", "isWhoopMetric", "note"
              ]),
              derivedProvenance["kind"] as? String == "derivedAnalysis",
              derivedProvenance["producer"] as? String == "whoop-18birdies",
              derivedProvenance["model"] as? String == "golf-readiness-v1",
              derivedProvenance["isWhoopMetric"] as? Bool == false,
              let note = derivedProvenance["note"] as? String,
              isBoundedText(note, maximumUTF8Bytes: 500),
              let rawComponents = readiness["components"] as? [[String: Any]],
              rawComponents.allSatisfy({
                  Set($0.keys) == Set(["label", "value", "weight", "detail"])
              }),
              let rawAdvice = readiness["advice"] as? [String],
              response.apiVersion == 1,
              response.date == expectedDate,
              isCalendarDate(response.date),
              response.generatedAt.timeIntervalSince1970.isFinite,
              response.generatedAt <= now.addingTimeInterval(5 * 60),
              response.freshness.lastCompleteSyncAt.map({ $0 <= now.addingTimeInterval(5 * 60) }) != false,
              (60...604_800).contains(response.freshness.staleAfterSeconds),
              ["scored", "partial", "pending"].contains(response.physiology.status),
              bounded(response.physiology.recoveryPercent, 0...100),
              bounded(response.physiology.hrvRmssdMs, 0...1_000),
              bounded(response.physiology.restingHeartRateBpm, 1...250),
              bounded(response.physiology.spo2Percent, 0...100),
              bounded(response.physiology.skinTemperatureCelsius, 0...60),
              bounded(response.physiology.sleepHours, 0...48),
              bounded(response.physiology.sleepPerformancePercent, 0...100),
              bounded(response.physiology.sleepEfficiencyPercent, 0...100),
              bounded(response.physiology.dayStrain, 0...21),
              bounded(response.physiology.priorDayStrain, 0...21),
              response.golfReadiness.components.count <= 32,
              response.golfReadiness.advice.count <= 32,
              rawComponents.count == response.golfReadiness.components.count,
              rawAdvice == response.golfReadiness.advice,
              response.golfReadiness.advice.allSatisfy({ isBoundedText($0, maximumUTF8Bytes: 1_000) }),
              response.golfReadiness.components.allSatisfy({ component in
                  isBoundedText(component.label, maximumUTF8Bytes: 128)
                    && isBoundedText(component.detail, maximumUTF8Bytes: 1_000)
                    && component.value.map({ $0.isFinite && (0...100).contains($0) }) == true
                    && component.weight.isFinite
                    && (0...1).contains(component.weight)
              }),
              response.golfReadiness.score.map({ $0.isFinite && (0...100).contains($0) }) != false,
              response.golfReadiness.verdict.map({ isBoundedText($0, maximumUTF8Bytes: 128) }) != false,
              response.golfReadiness.reason.map({ isBoundedText($0, maximumUTF8Bytes: 128) }) != false
        else { return false }

        if response.golfReadiness.available {
            return response.golfReadiness.score != nil
                && response.golfReadiness.verdict != nil
                && response.golfReadiness.reason == nil
        }
        return response.golfReadiness.score == nil
            && response.golfReadiness.verdict == nil
            && response.golfReadiness.reason != nil
    }

    private static func bounded(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }

    private static func isBoundedText(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumUTF8Bytes
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isCalendarDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    private func sendWithRetry(_ request: URLRequest) async throws -> BridgeHTTPResult {
        var lastError: Error = WhoopBridgeError.serverUnavailable
        for attempt in 0..<3 {
            do {
                let result = try await transport.send(
                    request,
                    maximumResponseBytes: maximumResponseBytes
                )
                guard result.data.count <= maximumResponseBytes else {
                    throw WhoopBridgeError.responseTooLarge
                }
                if result.statusCode == 429 || (500...599).contains(result.statusCode) {
                    lastError = WhoopBridgeError.serverUnavailable
                    if attempt < 2 {
                        try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                        continue
                    }
                    throw WhoopBridgeError.serverUnavailable
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WhoopBridgeError {
                if case .serverUnavailable = error {
                    lastError = error
                    if attempt < 2 {
                        try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                        continue
                    }
                } else {
                    throw error
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = WhoopBridgeError.serverUnavailable
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                    continue
                }
            }
        }
        throw lastError
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: string) ?? standard.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}

struct BridgeRoundOutboxEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let payload: BridgeRoundPayload
    let enqueuedAt: Date
}

enum BridgeRoundOutboxError: LocalizedError, Equatable, Sendable {
    case unavailable
    case corrupt
    case flushAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .unavailable: "The protected round upload queue is unavailable."
        case .corrupt: "The protected round upload queue could not be decoded."
        case .flushAlreadyRunning: "A round upload retry is already running."
        }
    }
}

/// Durable at-least-once delivery. An entry is removed only after a successful
/// server acknowledgement. A crash between upload and local acknowledgement
/// resends the same canonical payload, which the server stores idempotently.
actor BridgeRoundOutbox {
    struct FlushResult: Equatable, Sendable {
        let delivered: Int
        let remaining: Int
    }

    private struct Envelope: Codable, Sendable {
        let version: Int
        let entries: [BridgeRoundOutboxEntry]
    }

    private let directory: URL
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var isFlushing = false

    init(
        directory: URL? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("WhoopGolf", isDirectory: true)
            .appendingPathComponent("Bridge", isDirectory: true)
        let documentsFallback = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(".WhoopGolf-Bridge", isDirectory: true)
        guard let resolved = directory ?? defaultDirectory ?? documentsFallback else {
            preconditionFailure("No durable app container is available for the round upload queue.")
        }
        self.directory = resolved
        self.fileURL = resolved.appendingPathComponent("round-upload-outbox.json")
        self.now = now

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    func enqueue(_ payload: BridgeRoundPayload) throws -> String {
        var entries = try loadEntries()
        let id = payload.outboxID
        if entries.contains(where: { $0.id == id }) { return id }
        entries.append(BridgeRoundOutboxEntry(id: id, payload: payload, enqueuedAt: now()))
        try persist(entries)
        return id
    }

    func pending() throws -> [BridgeRoundOutboxEntry] {
        try loadEntries()
    }

    @discardableResult
    func acknowledge(id: String) throws -> Bool {
        let entries = try loadEntries()
        let remaining = entries.filter { $0.id != id }
        guard remaining.count != entries.count else { return false }
        try persist(remaining)
        return true
    }

    func flush(using uploader: any BridgeRoundUploading) async throws -> FlushResult {
        guard !isFlushing else { throw BridgeRoundOutboxError.flushAlreadyRunning }
        isFlushing = true
        defer { isFlushing = false }

        let queued = try loadEntries()
        var delivered = 0
        for entry in queued {
            _ = try await uploader.uploadRound(entry.payload)
            // Persist the acknowledgement after every item. If this write
            // fails, the item remains queued and is safely retried later.
            if try acknowledge(id: entry.id) {
                delivered += 1
            }
        }
        return FlushResult(delivered: delivered, remaining: try loadEntries().count)
    }

    private func loadEntries() throws -> [BridgeRoundOutboxEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw BridgeRoundOutboxError.unavailable
        }

        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw BridgeRoundOutboxError.corrupt
        }
        let ids = envelope.entries.map(\.id)
        guard envelope.version == 1,
              Set(ids).count == ids.count,
              envelope.entries.allSatisfy({ $0.id == $0.payload.outboxID })
        else { throw BridgeRoundOutboxError.corrupt }
        return envelope.entries
    }

    private func persist(_ entries: [BridgeRoundOutboxEntry]) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    .posixPermissions: 0o700
                ]
            )
            try FileManager.default.setAttributes(
                [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    .posixPermissions: 0o700
                ],
                ofItemAtPath: directory.path
            )
            let data = try encoder.encode(Envelope(version: 1, entries: entries))
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try FileManager.default.setAttributes(
                [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    .posixPermissions: 0o600
                ],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw BridgeRoundOutboxError.unavailable
        }
    }
}

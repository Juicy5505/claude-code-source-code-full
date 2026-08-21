import CryptoKit
import Foundation

enum WhoopMotionContractError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case invalidEnvelope(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The WHOOP motion request did not meet the versioned transfer contract."
        case .invalidEnvelope(let reason):
            "The WHOOP motion batch was rejected: \(reason)"
        }
    }
}

private struct WhoopMotionCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private enum WhoopMotionStrictDecoding {
    static func requireExactKeys(
        _ decoder: Decoder,
        expected: Set<String>,
        context: String
    ) throws {
        let container = try decoder.container(keyedBy: WhoopMotionCodingKey.self)
        let actual = Set(container.allKeys.map(\.stringValue))
        guard actual == expected else {
            throw WhoopMotionContractError.invalidEnvelope("\(context) has unexpected or missing fields")
        }
    }

    static func requirePresent<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K,
        context: String
    ) throws {
        guard container.contains(key) else {
            throw WhoopMotionContractError.invalidEnvelope("\(context) is missing \(key.stringValue)")
        }
    }
}

struct WhoopMotionRequest: Codable, Equatable, Sendable {
    static let apiVersion = 1
    static let schemaVersion = 1
    static let minimumRoundDuration: TimeInterval = 60
    static let maximumRoundDuration: TimeInterval = 24 * 60 * 60
    static let maximumEarlyRequestOffset: TimeInterval = 5 * 60
    static let maximumDelayedRequestOffset: TimeInterval = 7 * 24 * 60 * 60

    let roundID: UUID
    let startedAt: Date
    let endedAt: Date
    let requestedAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case apiVersion
        case schemaVersion
        case roundID
        case startedAt
        case endedAt
        case requestedAt
    }

    init(roundID: UUID, startedAt: Date, endedAt: Date, requestedAt: Date = .now) throws {
        let duration = endedAt.timeIntervalSince(startedAt)
        guard Self.validDate(startedAt), Self.validDate(endedAt), Self.validDate(requestedAt),
              duration.isFinite,
              (Self.minimumRoundDuration...Self.maximumRoundDuration).contains(duration),
              requestedAt >= startedAt.addingTimeInterval(-Self.maximumEarlyRequestOffset),
              requestedAt <= endedAt.addingTimeInterval(Self.maximumDelayedRequestOffset)
        else { throw WhoopMotionContractError.invalidRequest }
        self.roundID = roundID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.requestedAt = requestedAt
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "motion request"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .apiVersion) == Self.apiVersion,
              try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion
        else { throw WhoopMotionContractError.invalidRequest }
        try self.init(
            roundID: values.decode(UUID.self, forKey: .roundID),
            startedAt: values.decode(Date.self, forKey: .startedAt),
            endedAt: values.decode(Date.self, forKey: .endedAt),
            requestedAt: values.decode(Date.self, forKey: .requestedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.apiVersion, forKey: .apiVersion)
        try values.encode(Self.schemaVersion, forKey: .schemaVersion)
        try values.encode(roundID, forKey: .roundID)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(endedAt, forKey: .endedAt)
        try values.encode(requestedAt, forKey: .requestedAt)
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }
}

struct WhoopMotionPendingResponse: Codable, Equatable, Sendable {
    let status: String
    let roundID: UUID

    init(roundID: UUID) {
        self.status = "pending"
        self.roundID = roundID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case roundID
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "pending response"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(String.self, forKey: .status)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        guard status == "pending" else {
            throw WhoopMotionContractError.invalidEnvelope("pending response has an invalid status")
        }
    }
}

struct WhoopMotionEnvelope: Codable, Equatable, Sendable {
    static let apiVersion = 1
    static let supportedSchemaVersions = 1...2
    static let kind = "whoop5HistoricalSwingEvents"
    static let maximumEvents = 5_000
    static let maximumGaps = 1_000

    let schemaVersion: Int
    let batchID: String
    let roundID: UUID
    let generatedAt: Date
    let source: WhoopMotionSource
    let coverage: WhoopMotionCoverage
    let events: [WhoopMotionEvent]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case apiVersion
        case schemaVersion
        case kind
        case batchID
        case roundID
        case generatedAt
        case source
        case coverage
        case events
        case nextCursor
    }

    init(
        schemaVersion: Int = 1,
        batchID: String,
        roundID: UUID,
        generatedAt: Date,
        source: WhoopMotionSource,
        coverage: WhoopMotionCoverage,
        events: [WhoopMotionEvent],
        nextCursor: String? = nil
    ) throws {
        guard Self.supportedSchemaVersions.contains(schemaVersion),
              Self.isLowercaseSHA256(batchID),
              generatedAt.timeIntervalSince1970.isFinite,
              generatedAt >= coverage.roundStartedAt.addingTimeInterval(-5 * 60),
              source.offloadCompletedAt >= coverage.roundStartedAt.addingTimeInterval(-5 * 60),
              source.offloadCompletedAt <= generatedAt.addingTimeInterval(5 * 60),
              events.count <= Self.maximumEvents,
              nextCursor == nil,
              coverage.gaps.count <= Self.maximumGaps,
              coverage.roundEndedAt >= coverage.roundStartedAt,
              (WhoopMotionRequest.minimumRoundDuration...WhoopMotionRequest.maximumRoundDuration)
                .contains(coverage.roundEndedAt.timeIntervalSince(coverage.roundStartedAt)),
              coverage.firstFrameAt.map({ Self.contains($0, in: coverage) }) != false,
              coverage.lastFrameAt.map({ Self.contains($0, in: coverage) }) != false,
              coverage.firstFrameAt.map({ first in
                  coverage.lastFrameAt.map { $0 >= first } ?? true
              }) != false
        else {
            throw WhoopMotionContractError.invalidEnvelope("top-level identity or coverage is invalid")
        }

        let identities = Set(events.map(\.eventID))
        guard identities.count == events.count else {
            throw WhoopMotionContractError.invalidEnvelope("event identities are not unique")
        }
        guard zip(events, events.dropFirst()).allSatisfy({ first, second in
            first.observedAt <= second.observedAt
        }) else {
            throw WhoopMotionContractError.invalidEnvelope("motion events are not canonically ordered")
        }
        let pairedFrameBounds = (coverage.firstFrameAt == nil) == (coverage.lastFrameAt == nil)
        let countsMatchBounds = coverage.decodedFrameCount == 0
            ? coverage.firstFrameAt == nil
            : coverage.firstFrameAt != nil
        guard pairedFrameBounds, countsMatchBounds else {
            throw WhoopMotionContractError.invalidEnvelope("coverage bounds and counts are inconsistent")
        }
        for event in events {
            try event.validate(roundID: roundID, coverage: coverage, source: source)
            guard (schemaVersion == 1 && event.wristAnalysis == nil)
                    || (schemaVersion == 2 && event.wristAnalysis != nil) else {
                throw WhoopMotionContractError.invalidEnvelope(
                    schemaVersion == 1
                        ? "schema 1 forbids wrist analysis"
                        : "schema 2 requires wrist analysis for every event"
                )
            }
            if let analysis = event.wristAnalysis {
                try analysis.validateSummary(against: event)
            }
        }
        for (index, gap) in coverage.gaps.enumerated() {
            guard gap.through >= gap.from,
                  Self.contains(gap.from, in: coverage),
                  Self.contains(gap.through, in: coverage) else {
                throw WhoopMotionContractError.invalidEnvelope("a coverage gap is outside the round")
            }
            if index > 0, coverage.gaps[index - 1].through >= gap.from {
                throw WhoopMotionContractError.invalidEnvelope("coverage gaps overlap or are unordered")
            }
        }

        self.schemaVersion = schemaVersion
        self.batchID = batchID
        self.roundID = roundID
        self.generatedAt = generatedAt
        self.source = source
        self.coverage = coverage
        self.events = events
        self.nextCursor = nil
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "motion envelope"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard try values.decode(Int.self, forKey: .apiVersion) == Self.apiVersion,
              Self.supportedSchemaVersions.contains(schemaVersion),
              try values.decode(String.self, forKey: .kind) == Self.kind
        else { throw WhoopMotionContractError.invalidEnvelope("unsupported envelope version or kind") }
        try WhoopMotionStrictDecoding.requirePresent(values, .nextCursor, context: "motion envelope")
        guard try values.decodeNil(forKey: .nextCursor) else {
            throw WhoopMotionContractError.invalidEnvelope("pagination is not supported by schema 1")
        }
        try self.init(
            schemaVersion: schemaVersion,
            batchID: values.decode(String.self, forKey: .batchID),
            roundID: values.decode(UUID.self, forKey: .roundID),
            generatedAt: values.decode(Date.self, forKey: .generatedAt),
            source: values.decode(WhoopMotionSource.self, forKey: .source),
            coverage: values.decode(WhoopMotionCoverage.self, forKey: .coverage),
            events: values.decode([WhoopMotionEvent].self, forKey: .events),
            nextCursor: nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.apiVersion, forKey: .apiVersion)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(Self.kind, forKey: .kind)
        try values.encode(batchID, forKey: .batchID)
        try values.encode(roundID, forKey: .roundID)
        try values.encode(generatedAt, forKey: .generatedAt)
        try values.encode(source, forKey: .source)
        try values.encode(coverage, forKey: .coverage)
        try values.encode(events, forKey: .events)
        try values.encodeNil(forKey: .nextCursor)
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func contains(_ date: Date, in coverage: WhoopMotionCoverage) -> Bool {
        date >= coverage.roundStartedAt && date <= coverage.roundEndedAt
    }
}

struct WhoopMotionSource: Codable, Equatable, Sendable {
    let deviceFamily: String
    let captureMode: String
    let sampleRateHz: Int
    let offloadCompletedAt: Date
    let firmwareVersion: String?
    let decoder: WhoopMotionComponent
    let detector: WhoopMotionComponent

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case deviceFamily
        case captureMode
        case sampleRateHz
        case offloadCompletedAt
        case firmwareVersion
        case decoder
        case detector
    }

    init(
        deviceFamily: String,
        captureMode: String,
        sampleRateHz: Int,
        offloadCompletedAt: Date,
        firmwareVersion: String?,
        decoder: WhoopMotionComponent,
        detector: WhoopMotionComponent
    ) throws {
        guard deviceFamily == "whoop5",
              captureMode == "historicalOffload",
              sampleRateHz == 100,
              offloadCompletedAt.timeIntervalSince1970.isFinite,
              firmwareVersion.map({
                  !$0.isEmpty && $0.utf8.count <= 128 && $0.unicodeScalars.allSatisfy {
                      (0x20...0x7e).contains($0.value)
                  }
              }) != false,
              decoder.name == "whoop5-imu-facts",
              detector.name == "whoop-golf-swing"
        else { throw WhoopMotionContractError.invalidEnvelope("motion source is unsupported") }
        self.deviceFamily = deviceFamily
        self.captureMode = captureMode
        self.sampleRateHz = sampleRateHz
        self.offloadCompletedAt = offloadCompletedAt
        self.firmwareVersion = firmwareVersion
        self.decoder = decoder
        self.detector = detector
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "motion source"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .firmwareVersion, context: "motion source")
        try self.init(
            deviceFamily: values.decode(String.self, forKey: .deviceFamily),
            captureMode: values.decode(String.self, forKey: .captureMode),
            sampleRateHz: values.decode(Int.self, forKey: .sampleRateHz),
            offloadCompletedAt: values.decode(Date.self, forKey: .offloadCompletedAt),
            firmwareVersion: values.decodeIfPresent(String.self, forKey: .firmwareVersion),
            decoder: values.decode(WhoopMotionComponent.self, forKey: .decoder),
            detector: values.decode(WhoopMotionComponent.self, forKey: .detector)
        )
    }
}

struct WhoopMotionComponent: Codable, Equatable, Hashable, Sendable {
    let name: String
    let version: String

    private enum CodingKeys: String, CodingKey, CaseIterable { case name, version }

    init(name: String, version: String) throws {
        guard !name.isEmpty, name.utf8.count <= 64, !name.containsControlCharacters,
              version.utf8.count <= 64, Self.isSemanticVersion(version) else {
            throw WhoopMotionContractError.invalidEnvelope("component name or version is invalid")
        }
        self.name = name
        self.version = version
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "motion component"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: values.decode(String.self, forKey: .name),
            version: values.decode(String.self, forKey: .version)
        )
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(
            of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#,
            options: .regularExpression
        ) != nil
    }
}

struct WhoopMotionCoverage: Codable, Equatable, Sendable {
    let roundStartedAt: Date
    let roundEndedAt: Date
    let firstFrameAt: Date?
    let lastFrameAt: Date?
    let decodedFrameCount: Int
    let uniqueSecondCount: Int
    let offloadTerminal: WhoopMotionOffloadTerminal
    let frameCoverage: WhoopMotionFrameCoverage
    let complete: Bool
    let gaps: [WhoopMotionGap]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case roundStartedAt
        case roundEndedAt
        case firstFrameAt
        case lastFrameAt
        case decodedFrameCount
        case uniqueSecondCount
        case offloadTerminal
        case frameCoverage
        case complete
        case gaps
    }

    init(
        roundStartedAt: Date,
        roundEndedAt: Date,
        firstFrameAt: Date?,
        lastFrameAt: Date?,
        decodedFrameCount: Int,
        uniqueSecondCount: Int,
        offloadTerminal: WhoopMotionOffloadTerminal,
        frameCoverage: WhoopMotionFrameCoverage,
        complete: Bool,
        gaps: [WhoopMotionGap]
    ) throws {
        guard decodedFrameCount >= 0,
              uniqueSecondCount >= 0,
              uniqueSecondCount <= decodedFrameCount,
              gaps.count <= WhoopMotionEnvelope.maximumGaps,
              roundStartedAt.timeIntervalSince1970.isFinite,
              roundEndedAt.timeIntervalSince1970.isFinite,
              firstFrameAt?.timeIntervalSince1970.isFinite != false,
              lastFrameAt?.timeIntervalSince1970.isFinite != false
        else { throw WhoopMotionContractError.invalidEnvelope("coverage counts or timestamps are invalid") }
        self.roundStartedAt = roundStartedAt
        self.roundEndedAt = roundEndedAt
        self.firstFrameAt = firstFrameAt
        self.lastFrameAt = lastFrameAt
        self.decodedFrameCount = decodedFrameCount
        self.uniqueSecondCount = uniqueSecondCount
        self.offloadTerminal = offloadTerminal
        self.frameCoverage = frameCoverage
        self.complete = complete
        self.gaps = gaps
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "motion coverage"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .firstFrameAt, context: "motion coverage")
        try WhoopMotionStrictDecoding.requirePresent(values, .lastFrameAt, context: "motion coverage")
        try self.init(
            roundStartedAt: values.decode(Date.self, forKey: .roundStartedAt),
            roundEndedAt: values.decode(Date.self, forKey: .roundEndedAt),
            firstFrameAt: values.decodeIfPresent(Date.self, forKey: .firstFrameAt),
            lastFrameAt: values.decodeIfPresent(Date.self, forKey: .lastFrameAt),
            decodedFrameCount: values.decode(Int.self, forKey: .decodedFrameCount),
            uniqueSecondCount: values.decode(Int.self, forKey: .uniqueSecondCount),
            offloadTerminal: values.decode(WhoopMotionOffloadTerminal.self, forKey: .offloadTerminal),
            frameCoverage: values.decode(WhoopMotionFrameCoverage.self, forKey: .frameCoverage),
            complete: values.decode(Bool.self, forKey: .complete),
            gaps: values.decode([WhoopMotionGap].self, forKey: .gaps)
        )
    }
}

enum WhoopMotionOffloadTerminal: String, Codable, Equatable, Sendable {
    case historyComplete
    case connectionEnded
    case unknown
}

enum WhoopMotionFrameCoverage: String, Codable, Equatable, Sendable {
    case continuous
    case gapped
    case unknown
}

struct WhoopMotionGap: Codable, Equatable, Sendable {
    let from: Date
    let through: Date

    private enum CodingKeys: String, CodingKey, CaseIterable { case from, through }

    init(from: Date, through: Date) throws {
        guard from.timeIntervalSince1970.isFinite, through.timeIntervalSince1970.isFinite else {
            throw WhoopMotionContractError.invalidEnvelope("coverage gap timestamp is invalid")
        }
        self.from = from
        self.through = through
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "coverage gap"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            from: values.decode(Date.self, forKey: .from),
            through: values.decode(Date.self, forKey: .through)
        )
    }
}

// MARK: - Derived WHOOP wrist rotation (batch schema v2)

struct WhoopMotionVector3: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    private enum CodingKeys: String, CodingKey, CaseIterable { case x, y, z }

    init(x: Double, y: Double, z: Double, allowedRange: ClosedRange<Double> = -2_000...2_000) throws {
        guard [x, y, z].allSatisfy({ $0.isFinite && allowedRange.contains($0) }) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist vector is outside its allowed range")
        }
        self.x = x
        self.y = y
        self.z = z
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist vector"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: values.decode(Double.self, forKey: .x),
            y: values.decode(Double.self, forKey: .y),
            z: values.decode(Double.self, forKey: .z)
        )
    }

    fileprivate var magnitude: Double { sqrt((x * x) + (y * y) + (z * z)) }
}

struct WhoopMotionUnitQuaternion: Codable, Equatable, Hashable, Sendable {
    let w: Double
    let x: Double
    let y: Double
    let z: Double

    private enum CodingKeys: String, CodingKey, CaseIterable { case w, x, y, z }

    init(w: Double, x: Double, y: Double, z: Double) throws {
        let components = [w, x, y, z]
        let magnitude = sqrt(components.reduce(0) { $0 + ($1 * $1) })
        guard components.allSatisfy({ $0.isFinite && (-1...1).contains($0) }),
              (0.999...1.001).contains(magnitude) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist orientation is not a unit quaternion")
        }
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist orientation"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            w: values.decode(Double.self, forKey: .w),
            x: values.decode(Double.self, forKey: .x),
            y: values.decode(Double.self, forKey: .y),
            z: values.decode(Double.self, forKey: .z)
        )
    }
}

struct WhoopWristMeasurementScope: Codable, Equatable, Hashable, Sendable {
    static let omissions = [
        "clubheadPath", "clubfaceAngle", "absoluteHeading", "ballFlight", "translation",
    ]

    let label: String
    let referenceFrame: String
    let interpretation: String
    let explicitlyNotMeasured: [String]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, referenceFrame, interpretation, explicitlyNotMeasured
    }

    init(
        label: String = "wristRotationOnly",
        referenceFrame: String = "addressRelativeWhoopSensor",
        interpretation: String = "wristOrientationNotClubheadOrBallPath",
        explicitlyNotMeasured: [String] = Self.omissions
    ) throws {
        guard label == "wristRotationOnly",
              referenceFrame == "addressRelativeWhoopSensor",
              interpretation == "wristOrientationNotClubheadOrBallPath",
              explicitlyNotMeasured == Self.omissions else {
            throw WhoopMotionContractError.invalidEnvelope("wrist measurement scope is invalid")
        }
        self.label = label
        self.referenceFrame = referenceFrame
        self.interpretation = interpretation
        self.explicitlyNotMeasured = explicitlyNotMeasured
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist measurement scope"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            label: values.decode(String.self, forKey: .label),
            referenceFrame: values.decode(String.self, forKey: .referenceFrame),
            interpretation: values.decode(String.self, forKey: .interpretation),
            explicitlyNotMeasured: values.decode([String].self, forKey: .explicitlyNotMeasured)
        )
    }
}

struct WhoopWristSampling: Codable, Equatable, Hashable, Sendable {
    let sampleCount: Int
    let estimatedSampleRateHz: Double?
    let timingResolutionMilliseconds: Double?
    let gapCount: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sampleCount, estimatedSampleRateHz, timingResolutionMilliseconds, gapCount
    }

    init(
        sampleCount: Int,
        estimatedSampleRateHz: Double?,
        timingResolutionMilliseconds: Double?,
        gapCount: Int
    ) throws {
        guard (1...10_000).contains(sampleCount),
              (0..<sampleCount).contains(gapCount),
              Self.valid(estimatedSampleRateHz, in: 1...1_000),
              Self.valid(timingResolutionMilliseconds, in: 0.1...1_000) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist sampling metadata is invalid")
        }
        self.sampleCount = sampleCount
        self.estimatedSampleRateHz = estimatedSampleRateHz
        self.timingResolutionMilliseconds = timingResolutionMilliseconds
        self.gapCount = gapCount
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist sampling"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .estimatedSampleRateHz, context: "wrist sampling")
        try WhoopMotionStrictDecoding.requirePresent(values, .timingResolutionMilliseconds, context: "wrist sampling")
        try self.init(
            sampleCount: values.decode(Int.self, forKey: .sampleCount),
            estimatedSampleRateHz: values.decodeIfPresent(Double.self, forKey: .estimatedSampleRateHz),
            timingResolutionMilliseconds: values.decodeIfPresent(Double.self, forKey: .timingResolutionMilliseconds),
            gapCount: values.decode(Int.self, forKey: .gapCount)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sampleCount, forKey: .sampleCount)
        try values.encodeIfPresent(estimatedSampleRateHz, forKey: .estimatedSampleRateHz)
        if estimatedSampleRateHz == nil { try values.encodeNil(forKey: .estimatedSampleRateHz) }
        try values.encodeIfPresent(timingResolutionMilliseconds, forKey: .timingResolutionMilliseconds)
        if timingResolutionMilliseconds == nil { try values.encodeNil(forKey: .timingResolutionMilliseconds) }
        try values.encode(gapCount, forKey: .gapCount)
    }

    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}

enum WhoopWristQualityStatus: String, Codable, Equatable, Hashable, Sendable {
    case usable, limited, rejected
}

enum WhoopWristQualityReason: String, Codable, Equatable, Hashable, Sendable {
    case insufficientWindow
    case sampleRateMismatch
    case coverageGap
    case noAddressPause
    case transitionUnresolved
    case accelerometerSaturation
    case gyroscopeSaturation
}

struct WhoopWristQuality: Codable, Equatable, Hashable, Sendable {
    let status: WhoopWristQualityStatus
    let reasons: [WhoopWristQualityReason]

    private enum CodingKeys: String, CodingKey, CaseIterable { case status, reasons }

    init(status: WhoopWristQualityStatus, reasons: [WhoopWristQualityReason]) throws {
        guard reasons.count <= 7, Set(reasons).count == reasons.count else {
            throw WhoopMotionContractError.invalidEnvelope("wrist quality reasons are invalid")
        }
        self.status = status
        self.reasons = reasons
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist quality"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            status: values.decode(WhoopWristQualityStatus.self, forKey: .status),
            reasons: values.decode([WhoopWristQualityReason].self, forKey: .reasons)
        )
    }
}

enum WhoopWristCalibrationLabel: String, Codable, Equatable, Hashable, Sendable {
    case uncalibrated, addressBiasOnly, mountingDeclared, personalBaseline
}

struct WhoopWristCalibration: Codable, Equatable, Hashable, Sendable {
    let label: WhoopWristCalibrationLabel
    let quietSampleCount: Int
    let gyroscopeBiasDegreesPerSecond: WhoopMotionVector3?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, quietSampleCount, gyroscopeBiasDegreesPerSecond
    }

    init(
        label: WhoopWristCalibrationLabel,
        quietSampleCount: Int,
        gyroscopeBiasDegreesPerSecond: WhoopMotionVector3?,
        maximumSampleCount: Int = 10_000
    ) throws {
        let zeroCalibration = gyroscopeBiasDegreesPerSecond == nil && quietSampleCount == 0
        guard (0...maximumSampleCount).contains(quietSampleCount),
              (label == .uncalibrated) == zeroCalibration else {
            throw WhoopMotionContractError.invalidEnvelope("wrist calibration is inconsistent")
        }
        self.label = label
        self.quietSampleCount = quietSampleCount
        self.gyroscopeBiasDegreesPerSecond = gyroscopeBiasDegreesPerSecond
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist calibration"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .gyroscopeBiasDegreesPerSecond, context: "wrist calibration")
        try self.init(
            label: values.decode(WhoopWristCalibrationLabel.self, forKey: .label),
            quietSampleCount: values.decode(Int.self, forKey: .quietSampleCount),
            gyroscopeBiasDegreesPerSecond: values.decodeIfPresent(
                WhoopMotionVector3.self,
                forKey: .gyroscopeBiasDegreesPerSecond
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(label, forKey: .label)
        try values.encode(quietSampleCount, forKey: .quietSampleCount)
        if let gyroscopeBiasDegreesPerSecond {
            try values.encode(gyroscopeBiasDegreesPerSecond, forKey: .gyroscopeBiasDegreesPerSecond)
        } else {
            try values.encodeNil(forKey: .gyroscopeBiasDegreesPerSecond)
        }
    }
}

enum WhoopWristTransitionMethod: String, Codable, Equatable, Hashable, Sendable {
    case gyroReversal, activityValley
}

struct WhoopWristPhases: Codable, Equatable, Hashable, Sendable {
    let transitionMethod: WhoopWristTransitionMethod?
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case transitionMethod, backswingSeconds, downswingSeconds, tempoRatio
    }

    init(
        transitionMethod: WhoopWristTransitionMethod?,
        backswingSeconds: Double?,
        downswingSeconds: Double?,
        tempoRatio: Double?
    ) throws {
        guard Self.valid(backswingSeconds, in: 0...10),
              Self.valid(downswingSeconds, in: 0...10),
              Self.valid(tempoRatio, in: 0...20) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist phase metrics are invalid")
        }
        self.transitionMethod = transitionMethod
        self.backswingSeconds = backswingSeconds
        self.downswingSeconds = downswingSeconds
        self.tempoRatio = tempoRatio
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist phases"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
            try WhoopMotionStrictDecoding.requirePresent(values, key, context: "wrist phases")
        }
        try self.init(
            transitionMethod: values.decodeIfPresent(WhoopWristTransitionMethod.self, forKey: .transitionMethod),
            backswingSeconds: values.decodeIfPresent(Double.self, forKey: .backswingSeconds),
            downswingSeconds: values.decodeIfPresent(Double.self, forKey: .downswingSeconds),
            tempoRatio: values.decodeIfPresent(Double.self, forKey: .tempoRatio)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeNullable(transitionMethod, into: &values, forKey: .transitionMethod)
        try Self.encodeNullable(backswingSeconds, into: &values, forKey: .backswingSeconds)
        try Self.encodeNullable(downswingSeconds, into: &values, forKey: .downswingSeconds)
        try Self.encodeNullable(tempoRatio, into: &values, forKey: .tempoRatio)
    }

    private static func encodeNullable<T: Encodable>(
        _ value: T?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value { try container.encode(value, forKey: key) }
        else { try container.encodeNil(forKey: key) }
    }

    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}

struct WhoopWristFeatures: Codable, Equatable, Hashable, Sendable {
    let peakSpecificForceG: Double
    let peakAddressRelativeAccelerationG: Double?
    let peakAngularSpeedDegreesPerSecond: Double
    let totalAngularTravelToImpactDegrees: Double?
    let dominantAngularAxisSensor: WhoopMotionVector3?
    let angularAxisConcentration: Double?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case peakSpecificForceG
        case peakAddressRelativeAccelerationG
        case peakAngularSpeedDegreesPerSecond
        case totalAngularTravelToImpactDegrees
        case dominantAngularAxisSensor
        case angularAxisConcentration
    }

    init(
        peakSpecificForceG: Double,
        peakAddressRelativeAccelerationG: Double?,
        peakAngularSpeedDegreesPerSecond: Double,
        totalAngularTravelToImpactDegrees: Double?,
        dominantAngularAxisSensor: WhoopMotionVector3?,
        angularAxisConcentration: Double?
    ) throws {
        guard peakSpecificForceG.isFinite, (0...100).contains(peakSpecificForceG),
              peakAngularSpeedDegreesPerSecond.isFinite,
              (0...10_000).contains(peakAngularSpeedDegreesPerSecond),
              Self.valid(peakAddressRelativeAccelerationG, in: 0...100),
              Self.valid(totalAngularTravelToImpactDegrees, in: 0...20_000),
              Self.valid(angularAxisConcentration, in: 0...1),
              dominantAngularAxisSensor.map({ axis in
                  (-1...1).contains(axis.x)
                      && (-1...1).contains(axis.y)
                      && (-1...1).contains(axis.z)
                      && (0.999...1.001).contains(axis.magnitude)
              }) != false else {
            throw WhoopMotionContractError.invalidEnvelope("wrist motion features are invalid")
        }
        self.peakSpecificForceG = peakSpecificForceG
        self.peakAddressRelativeAccelerationG = peakAddressRelativeAccelerationG
        self.peakAngularSpeedDegreesPerSecond = peakAngularSpeedDegreesPerSecond
        self.totalAngularTravelToImpactDegrees = totalAngularTravelToImpactDegrees
        self.dominantAngularAxisSensor = dominantAngularAxisSensor
        self.angularAxisConcentration = angularAxisConcentration
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist features"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in [
            CodingKeys.peakAddressRelativeAccelerationG,
            .totalAngularTravelToImpactDegrees,
            .dominantAngularAxisSensor,
            .angularAxisConcentration,
        ] {
            try WhoopMotionStrictDecoding.requirePresent(values, key, context: "wrist features")
        }
        try self.init(
            peakSpecificForceG: values.decode(Double.self, forKey: .peakSpecificForceG),
            peakAddressRelativeAccelerationG: values.decodeIfPresent(Double.self, forKey: .peakAddressRelativeAccelerationG),
            peakAngularSpeedDegreesPerSecond: values.decode(Double.self, forKey: .peakAngularSpeedDegreesPerSecond),
            totalAngularTravelToImpactDegrees: values.decodeIfPresent(Double.self, forKey: .totalAngularTravelToImpactDegrees),
            dominantAngularAxisSensor: values.decodeIfPresent(WhoopMotionVector3.self, forKey: .dominantAngularAxisSensor),
            angularAxisConcentration: values.decodeIfPresent(Double.self, forKey: .angularAxisConcentration)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(peakSpecificForceG, forKey: .peakSpecificForceG)
        try values.encode(peakAngularSpeedDegreesPerSecond, forKey: .peakAngularSpeedDegreesPerSecond)
        try Self.encodeNullable(peakAddressRelativeAccelerationG, into: &values, forKey: .peakAddressRelativeAccelerationG)
        try Self.encodeNullable(totalAngularTravelToImpactDegrees, into: &values, forKey: .totalAngularTravelToImpactDegrees)
        try Self.encodeNullable(dominantAngularAxisSensor, into: &values, forKey: .dominantAngularAxisSensor)
        try Self.encodeNullable(angularAxisConcentration, into: &values, forKey: .angularAxisConcentration)
    }

    private static func encodeNullable<T: Encodable>(
        _ value: T?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value { try container.encode(value, forKey: key) }
        else { try container.encodeNil(forKey: key) }
    }

    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}

enum WhoopWristTracePhase: String, Codable, Equatable, Hashable, Sendable {
    case takeaway, backswing, transition, downswing, impact, unresolved
}

struct WhoopWristTracePoint: Codable, Equatable, Hashable, Sendable {
    let offsetMilliseconds: Double
    let phase: WhoopWristTracePhase
    let orientation: WhoopMotionUnitQuaternion

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case offsetMilliseconds, phase, orientation
    }

    init(
        offsetMilliseconds: Double,
        phase: WhoopWristTracePhase,
        orientation: WhoopMotionUnitQuaternion
    ) throws {
        guard offsetMilliseconds.isFinite, (-10_000...0).contains(offsetMilliseconds) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist trace time is invalid")
        }
        self.offsetMilliseconds = offsetMilliseconds
        self.phase = phase
        self.orientation = orientation
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist trace point"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            offsetMilliseconds: values.decode(Double.self, forKey: .offsetMilliseconds),
            phase: values.decode(WhoopWristTracePhase.self, forKey: .phase),
            orientation: values.decode(WhoopMotionUnitQuaternion.self, forKey: .orientation)
        )
    }
}

struct WhoopWristOrientationTrace: Codable, Equatable, Hashable, Sendable {
    let label: String
    let representation: String
    let quaternionSemantics: String
    let integration: String
    let points: [WhoopWristTracePoint]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, representation, quaternionSemantics, integration, points
    }

    init(
        label: String = "addressRelativeWhoopSensorOrientation",
        representation: String = "unitQuaternion",
        quaternionSemantics: String = "rotatesCurrentWhoopSensorFrameIntoAddressWhoopSensorFrame",
        integration: String = "biasCorrectedMidpointGyroscope",
        points: [WhoopWristTracePoint]
    ) throws {
        guard label == "addressRelativeWhoopSensorOrientation",
              representation == "unitQuaternion",
              quaternionSemantics == "rotatesCurrentWhoopSensorFrameIntoAddressWhoopSensorFrame",
              integration == "biasCorrectedMidpointGyroscope",
              (2...25).contains(points.count),
              points.first?.offsetMilliseconds ?? 0 < 0,
              points.last?.offsetMilliseconds == 0,
              points.last?.phase == .impact,
              zip(points, points.dropFirst()).allSatisfy({ $0.offsetMilliseconds < $1.offsetMilliseconds }) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist orientation trace is invalid")
        }
        self.label = label
        self.representation = representation
        self.quaternionSemantics = quaternionSemantics
        self.integration = integration
        self.points = points
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist orientation trace"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            label: values.decode(String.self, forKey: .label),
            representation: values.decode(String.self, forKey: .representation),
            quaternionSemantics: values.decode(String.self, forKey: .quaternionSemantics),
            integration: values.decode(String.self, forKey: .integration),
            points: values.decode([WhoopWristTracePoint].self, forKey: .points)
        )
    }
}

struct WhoopWristUncertainty: Codable, Equatable, Hashable, Sendable {
    static let unobservables = [
        "absoluteYawWithoutMagnetometer",
        "translationWithoutDrift",
        "clubheadPosition",
        "clubfaceOrientation",
    ]

    let kind: String
    let phaseBoundaryPlusMinusMilliseconds: Double?
    let orientationAtImpactPlusMinusDegrees: Double?
    let unobservable: [String]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, phaseBoundaryPlusMinusMilliseconds, orientationAtImpactPlusMinusDegrees, unobservable
    }

    init(
        kind: String = "heuristicResolutionBoundNotConfidenceInterval",
        phaseBoundaryPlusMinusMilliseconds: Double?,
        orientationAtImpactPlusMinusDegrees: Double?,
        unobservable: [String] = Self.unobservables
    ) throws {
        guard kind == "heuristicResolutionBoundNotConfidenceInterval",
              unobservable == Self.unobservables,
              Self.valid(phaseBoundaryPlusMinusMilliseconds, in: 0...10_000),
              Self.valid(orientationAtImpactPlusMinusDegrees, in: 0...360) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist uncertainty is invalid")
        }
        self.kind = kind
        self.phaseBoundaryPlusMinusMilliseconds = phaseBoundaryPlusMinusMilliseconds
        self.orientationAtImpactPlusMinusDegrees = orientationAtImpactPlusMinusDegrees
        self.unobservable = unobservable
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist uncertainty"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .phaseBoundaryPlusMinusMilliseconds, context: "wrist uncertainty")
        try WhoopMotionStrictDecoding.requirePresent(values, .orientationAtImpactPlusMinusDegrees, context: "wrist uncertainty")
        try self.init(
            kind: values.decode(String.self, forKey: .kind),
            phaseBoundaryPlusMinusMilliseconds: values.decodeIfPresent(Double.self, forKey: .phaseBoundaryPlusMinusMilliseconds),
            orientationAtImpactPlusMinusDegrees: values.decodeIfPresent(Double.self, forKey: .orientationAtImpactPlusMinusDegrees),
            unobservable: values.decode([String].self, forKey: .unobservable)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        if let phaseBoundaryPlusMinusMilliseconds {
            try values.encode(phaseBoundaryPlusMinusMilliseconds, forKey: .phaseBoundaryPlusMinusMilliseconds)
        } else { try values.encodeNil(forKey: .phaseBoundaryPlusMinusMilliseconds) }
        if let orientationAtImpactPlusMinusDegrees {
            try values.encode(orientationAtImpactPlusMinusDegrees, forKey: .orientationAtImpactPlusMinusDegrees)
        } else { try values.encodeNil(forKey: .orientationAtImpactPlusMinusDegrees) }
        try values.encode(unobservable, forKey: .unobservable)
    }

    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}

struct WhoopMotionWristAnalysis: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    static let kind = "whoopWristRotationTrace"

    let algorithm: WhoopMotionComponent
    let measurementScope: WhoopWristMeasurementScope
    let sampling: WhoopWristSampling
    let quality: WhoopWristQuality
    let calibration: WhoopWristCalibration
    let phases: WhoopWristPhases
    let features: WhoopWristFeatures
    let orientationTrace: WhoopWristOrientationTrace?
    let uncertainty: WhoopWristUncertainty

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, kind, algorithm, measurementScope, sampling, quality
        case calibration, phases, features, orientationTrace, uncertainty
    }

    init(
        algorithm: WhoopMotionComponent,
        measurementScope: WhoopWristMeasurementScope,
        sampling: WhoopWristSampling,
        quality: WhoopWristQuality,
        calibration: WhoopWristCalibration,
        phases: WhoopWristPhases,
        features: WhoopWristFeatures,
        orientationTrace: WhoopWristOrientationTrace?,
        uncertainty: WhoopWristUncertainty
    ) throws {
        guard algorithm.name == "whoop-wrist-motion",
              calibration.quietSampleCount <= sampling.sampleCount,
              (orientationTrace == nil) == (uncertainty.orientationAtImpactPlusMinusDegrees == nil) else {
            throw WhoopMotionContractError.invalidEnvelope("wrist analysis fields are inconsistent")
        }
        self.algorithm = algorithm
        self.measurementScope = measurementScope
        self.sampling = sampling
        self.quality = quality
        self.calibration = calibration
        self.phases = phases
        self.features = features
        self.orientationTrace = orientationTrace
        self.uncertainty = uncertainty
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "wrist analysis"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(String.self, forKey: .kind) == Self.kind else {
            throw WhoopMotionContractError.invalidEnvelope("unsupported wrist analysis schema")
        }
        try WhoopMotionStrictDecoding.requirePresent(values, .orientationTrace, context: "wrist analysis")
        try self.init(
            algorithm: values.decode(WhoopMotionComponent.self, forKey: .algorithm),
            measurementScope: values.decode(WhoopWristMeasurementScope.self, forKey: .measurementScope),
            sampling: values.decode(WhoopWristSampling.self, forKey: .sampling),
            quality: values.decode(WhoopWristQuality.self, forKey: .quality),
            calibration: values.decode(WhoopWristCalibration.self, forKey: .calibration),
            phases: values.decode(WhoopWristPhases.self, forKey: .phases),
            features: values.decode(WhoopWristFeatures.self, forKey: .features),
            orientationTrace: values.decodeIfPresent(WhoopWristOrientationTrace.self, forKey: .orientationTrace),
            uncertainty: values.decode(WhoopWristUncertainty.self, forKey: .uncertainty)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.schemaVersion, forKey: .schemaVersion)
        try values.encode(Self.kind, forKey: .kind)
        try values.encode(algorithm, forKey: .algorithm)
        try values.encode(measurementScope, forKey: .measurementScope)
        try values.encode(sampling, forKey: .sampling)
        try values.encode(quality, forKey: .quality)
        try values.encode(calibration, forKey: .calibration)
        try values.encode(phases, forKey: .phases)
        try values.encode(features, forKey: .features)
        if let orientationTrace { try values.encode(orientationTrace, forKey: .orientationTrace) }
        else { try values.encodeNil(forKey: .orientationTrace) }
        try values.encode(uncertainty, forKey: .uncertainty)
    }

    fileprivate func validateSummary(against event: WhoopMotionEvent) throws {
        guard phases.backswingSeconds == event.metrics.backswingSeconds,
              phases.downswingSeconds == event.metrics.downswingSeconds,
              phases.tempoRatio == event.metrics.tempoRatio,
              features.peakSpecificForceG == event.metrics.peakG else {
            throw WhoopMotionContractError.invalidEnvelope("wrist analysis disagrees with summary metrics")
        }
        if event.classification.decision == .accepted {
            guard quality.status == .usable,
                  calibration.label == .personalBaseline,
                  orientationTrace != nil else {
                throw WhoopMotionContractError.invalidEnvelope(
                    "accepted wrist analysis lacks usable personal calibration"
                )
            }
        }
    }
}

struct WhoopMotionEvent: Codable, Equatable, Sendable {
    let eventID: String
    let observedAt: Date
    let frameRef: WhoopMotionFrameReference
    let classification: WhoopMotionClassification
    let metrics: WhoopMotionMetrics
    let wristAnalysis: WhoopMotionWristAnalysis?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID
        case observedAt
        case frameRef
        case classification
        case metrics
        case wristAnalysis
    }

    init(
        eventID: String,
        observedAt: Date,
        frameRef: WhoopMotionFrameReference,
        classification: WhoopMotionClassification,
        metrics: WhoopMotionMetrics,
        wristAnalysis: WhoopMotionWristAnalysis? = nil
    ) throws {
        guard WhoopMotionEnvelope.isLowercaseSHA256(eventID),
              observedAt.timeIntervalSince1970.isFinite else {
            throw WhoopMotionContractError.invalidEnvelope("motion event identity or timestamp is invalid")
        }
        self.eventID = eventID
        self.observedAt = observedAt
        self.frameRef = frameRef
        self.classification = classification
        self.metrics = metrics
        self.wristAnalysis = wristAnalysis
    }

    init(from decoder: Decoder) throws {
        let baseKeys: Set<String> = ["eventID", "observedAt", "frameRef", "classification", "metrics"]
        let container = try decoder.container(keyedBy: WhoopMotionCodingKey.self)
        let actualKeys = Set(container.allKeys.map(\.stringValue))
        guard actualKeys == baseKeys || actualKeys == baseKeys.union(["wristAnalysis"]) else {
            throw WhoopMotionContractError.invalidEnvelope("motion event has unexpected or missing fields")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let wristAnalysis: WhoopMotionWristAnalysis?
        if actualKeys.contains(CodingKeys.wristAnalysis.rawValue) {
            // A present key must contain the schema-v2 object. In particular,
            // explicit null is not equivalent to absence: schema v1 forbids
            // this key, while schema v2 requires a non-null analysis.
            wristAnalysis = try values.decode(
                WhoopMotionWristAnalysis.self,
                forKey: .wristAnalysis
            )
        } else {
            wristAnalysis = nil
        }
        try self.init(
            eventID: values.decode(String.self, forKey: .eventID),
            observedAt: values.decode(Date.self, forKey: .observedAt),
            frameRef: values.decode(WhoopMotionFrameReference.self, forKey: .frameRef),
            classification: values.decode(WhoopMotionClassification.self, forKey: .classification),
            metrics: values.decode(WhoopMotionMetrics.self, forKey: .metrics),
            wristAnalysis: wristAnalysis
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(eventID, forKey: .eventID)
        try values.encode(observedAt, forKey: .observedAt)
        try values.encode(frameRef, forKey: .frameRef)
        try values.encode(classification, forKey: .classification)
        try values.encode(metrics, forKey: .metrics)
        if let wristAnalysis {
            try values.encode(wristAnalysis, forKey: .wristAnalysis)
        }
    }

    var swingUUID: UUID {
        let bytes = Self.hexBytes(eventID)
        var identity = Array(bytes.prefix(16))
        identity[6] = (identity[6] & 0x0f) | 0x80
        identity[8] = (identity[8] & 0x3f) | 0x80
        return UUID(uuid: (
            identity[0], identity[1], identity[2], identity[3],
            identity[4], identity[5], identity[6], identity[7],
            identity[8], identity[9], identity[10], identity[11],
            identity[12], identity[13], identity[14], identity[15]
        ))
    }

    fileprivate func validate(
        roundID: UUID,
        coverage: WhoopMotionCoverage,
        source: WhoopMotionSource
    ) throws {
        guard observedAt >= coverage.roundStartedAt, observedAt <= coverage.roundEndedAt else {
            throw WhoopMotionContractError.invalidEnvelope("motion event is outside the round")
        }
        let frameTime = Date(
            timeIntervalSince1970: TimeInterval(frameRef.baseUnixSeconds)
                + (TimeInterval(frameRef.sampleIndex) / TimeInterval(source.sampleRateHz))
        )
        guard abs(observedAt.timeIntervalSince(frameTime)) <= 0.001 else {
            throw WhoopMotionContractError.invalidEnvelope("motion event timestamp does not match its frame reference")
        }
        let epochMilliseconds = Int64((observedAt.timeIntervalSince1970 * 1_000).rounded())
        let preimage = [
            "whoop5-swing-v1",
            roundID.uuidString.lowercased(),
            String(epochMilliseconds),
            frameRef.sha256,
            String(frameRef.sampleIndex),
            source.detector.version,
        ].joined(separator: "\u{001F}")
        let expected = SHA256.hash(data: Data(preimage.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard eventID == expected else {
            throw WhoopMotionContractError.invalidEnvelope("motion event identity does not match its canonical fields")
        }
        if let heartRate = metrics.heartRate {
            guard heartRate.observedAt >= coverage.roundStartedAt,
                  heartRate.observedAt <= coverage.roundEndedAt else {
                throw WhoopMotionContractError.invalidEnvelope("heart-rate observation is outside the round")
            }
        }
    }

    private static func hexBytes(_ value: String) -> [UInt8] {
        stride(from: 0, to: value.count, by: 2).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            return UInt8(value[start..<end], radix: 16)!
        }
    }
}

struct WhoopMotionFrameReference: Codable, Equatable, Sendable {
    let baseUnixSeconds: Int64
    let sampleIndex: Int
    let sha256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseUnixSeconds
        case sampleIndex
        case sha256
    }

    init(baseUnixSeconds: Int64, sampleIndex: Int, sha256: String) throws {
        guard baseUnixSeconds >= 0,
              (0...99).contains(sampleIndex),
              WhoopMotionEnvelope.isLowercaseSHA256(sha256) else {
            throw WhoopMotionContractError.invalidEnvelope("frame reference is invalid")
        }
        self.baseUnixSeconds = baseUnixSeconds
        self.sampleIndex = sampleIndex
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "frame reference"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            baseUnixSeconds: values.decode(Int64.self, forKey: .baseUnixSeconds),
            sampleIndex: values.decode(Int.self, forKey: .sampleIndex),
            sha256: values.decode(String.self, forKey: .sha256)
        )
    }
}

enum WhoopMotionDecision: String, Codable, Equatable, Sendable {
    case accepted
    case needsReview
}

enum WhoopMotionReviewReason: String, Codable, Equatable, Sendable {
    case lowDetectorConfidence
    case coverageGapNearEvent
    case duplicateCandidate
    case roundBoundary
}

struct WhoopMotionClassification: Codable, Equatable, Sendable {
    let label: String
    let decision: WhoopMotionDecision
    let confidence: Double
    let reasons: [WhoopMotionReviewReason]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label
        case decision
        case confidence
        case reasons
    }

    init(
        label: String,
        decision: WhoopMotionDecision,
        confidence: Double,
        reasons: [WhoopMotionReviewReason]
    ) throws {
        guard label == "golfSwingCandidate",
              confidence.isFinite, (0...1).contains(confidence),
              reasons.count <= 4,
              Set(reasons).count == reasons.count else {
            throw WhoopMotionContractError.invalidEnvelope("swing classification is invalid")
        }
        self.label = label
        self.decision = decision
        self.confidence = confidence
        self.reasons = reasons
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "swing classification"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            label: values.decode(String.self, forKey: .label),
            decision: values.decode(WhoopMotionDecision.self, forKey: .decision),
            confidence: values.decode(Double.self, forKey: .confidence),
            reasons: values.decode([WhoopMotionReviewReason].self, forKey: .reasons)
        )
    }
}

struct WhoopMotionMetrics: Codable, Equatable, Sendable {
    let peakG: Double
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?
    let heartRate: WhoopMotionHeartRate?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case peakG
        case backswingSeconds
        case downswingSeconds
        case tempoRatio
        case heartRate
    }

    init(
        peakG: Double,
        backswingSeconds: Double?,
        downswingSeconds: Double?,
        tempoRatio: Double?,
        heartRate: WhoopMotionHeartRate?
    ) throws {
        guard peakG.isFinite, (0...100).contains(peakG),
              Self.validOptional(backswingSeconds, range: 0...10),
              Self.validOptional(downswingSeconds, range: 0...10),
              Self.validOptional(tempoRatio, range: 0...20) else {
            throw WhoopMotionContractError.invalidEnvelope("swing metrics are invalid")
        }
        self.peakG = peakG
        self.backswingSeconds = backswingSeconds
        self.downswingSeconds = downswingSeconds
        self.tempoRatio = tempoRatio
        self.heartRate = heartRate
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "swing metrics"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try WhoopMotionStrictDecoding.requirePresent(values, .backswingSeconds, context: "swing metrics")
        try WhoopMotionStrictDecoding.requirePresent(values, .downswingSeconds, context: "swing metrics")
        try WhoopMotionStrictDecoding.requirePresent(values, .tempoRatio, context: "swing metrics")
        try WhoopMotionStrictDecoding.requirePresent(values, .heartRate, context: "swing metrics")
        try self.init(
            peakG: values.decode(Double.self, forKey: .peakG),
            backswingSeconds: values.decodeIfPresent(Double.self, forKey: .backswingSeconds),
            downswingSeconds: values.decodeIfPresent(Double.self, forKey: .downswingSeconds),
            tempoRatio: values.decodeIfPresent(Double.self, forKey: .tempoRatio),
            heartRate: values.decodeIfPresent(WhoopMotionHeartRate.self, forKey: .heartRate)
        )
    }

    private static func validOptional(
        _ value: Double?,
        range: ClosedRange<Double>
    ) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}

enum WhoopMotionHeartRateSource: String, Codable, Equatable, Sendable {
    case whoopBroadcast
    case whoopCloud

    var metricSource: MetricSource {
        switch self {
        case .whoopBroadcast: .whoopBroadcast
        case .whoopCloud: .whoopCloud
        }
    }
}

struct WhoopMotionHeartRate: Codable, Equatable, Sendable {
    let bpm: Int
    let observedAt: Date
    let source: WhoopMotionHeartRateSource
    let quality: DataQuality

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bpm
        case observedAt
        case source
        case quality
    }

    init(
        bpm: Int,
        observedAt: Date,
        source: WhoopMotionHeartRateSource,
        quality: DataQuality
    ) throws {
        guard (1...250).contains(bpm), observedAt.timeIntervalSince1970.isFinite,
              quality == .verified || quality == .estimated else {
            throw WhoopMotionContractError.invalidEnvelope("heart-rate observation is invalid")
        }
        self.bpm = bpm
        self.observedAt = observedAt
        self.source = source
        self.quality = quality
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue)),
            context: "heart-rate observation"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            bpm: values.decode(Int.self, forKey: .bpm),
            observedAt: values.decode(Date.self, forKey: .observedAt),
            source: values.decode(WhoopMotionHeartRateSource.self, forKey: .source),
            quality: values.decode(DataQuality.self, forKey: .quality)
        )
    }
}

private extension String {
    var containsControlCharacters: Bool {
        rangeOfCharacter(from: .controlCharacters) != nil
    }
}

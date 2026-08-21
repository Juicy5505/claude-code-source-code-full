import Foundation

// Phone <-> Watch round-identity contract.
//
// Lives in Shared/ because BOTH the iPhone target (WatchSessionReceiver) and the
// watchOS target (WatchSessionTransfer) must encode/decode the same envelope.
// Keeping it inside the iOS-only WatchSupport/WatchSessionReceiver.swift broke
// the WhoopGolfWatch build ("cannot find type 'WatchRoundContext' in scope").

/// The only phone -> Watch identity contract for an in-progress golf round.
///
/// The ID comes from the iPhone's persisted `GolfRound`; the Watch writes this
/// exact UUID into its session JSON. Dates and course names are display/context
/// fields only and are never used to guess a relationship.
struct WatchRoundContext: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let roundID: UUID
    let courseName: String
    let startedAt: Date

    init(roundID: UUID, courseName: String, startedAt: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.roundID = roundID
        self.courseName = courseName
        self.startedAt = startedAt
    }
}

enum WatchRoundContextError: LocalizedError, Equatable {
    case malformed
    case unsupportedSchema(Int)
    case invalidCourseName
    case invalidStartedAt
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .malformed:
            return "the phone round context is malformed"
        case .unsupportedSchema(let version):
            return "phone round context schema \(version) is unsupported"
        case .invalidCourseName:
            return "the linked phone round has an invalid course name"
        case .invalidStartedAt:
            return "the linked phone round has an invalid start time"
        case .invalidEnvelope:
            return "the phone round context envelope is inconsistent"
        }
    }
}

/// A property-list-safe application-context envelope. The explicit `cleared`
/// state replaces the previously published active value, preventing a stale
/// round ID from surviving after the iPhone finishes or abandons that round.
enum WatchRoundApplicationContextCodec {
    private static let applicationContextKey = "com.alex.whoopgolf.round-context"

    private enum State: String, Codable {
        case active
        case cleared
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let state: State
        let round: WatchRoundContext?
    }

    static func encode(_ context: WatchRoundContext?) throws -> [String: Any] {
        if let context {
            try validate(context)
        }
        let envelope = Envelope(
            schemaVersion: WatchRoundContext.currentSchemaVersion,
            state: context == nil ? .cleared : .active,
            round: context
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return [applicationContextKey: try encoder.encode(envelope)]
    }

    /// An empty dictionary is the expected state before the iPhone has ever
    /// published a round. It means "not linked", not an error.
    static func decode(_ applicationContext: [String: Any]) throws -> WatchRoundContext? {
        guard let rawValue = applicationContext[applicationContextKey] else { return nil }
        guard let data = rawValue as? Data else { throw WatchRoundContextError.malformed }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw WatchRoundContextError.malformed
        }

        guard envelope.schemaVersion == WatchRoundContext.currentSchemaVersion else {
            throw WatchRoundContextError.unsupportedSchema(envelope.schemaVersion)
        }
        switch (envelope.state, envelope.round) {
        case (.cleared, nil):
            return nil
        case (.active, .some(let context)):
            try validate(context)
            return context
        default:
            throw WatchRoundContextError.invalidEnvelope
        }
    }

    private static func validate(_ context: WatchRoundContext) throws {
        guard context.schemaVersion == WatchRoundContext.currentSchemaVersion else {
            throw WatchRoundContextError.unsupportedSchema(context.schemaVersion)
        }
        let course = context.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !course.isEmpty, course.utf8.count <= 240 else {
            throw WatchRoundContextError.invalidCourseName
        }
        guard context.startedAt.timeIntervalSince1970.isFinite,
              context.startedAt.timeIntervalSince1970 > 0 else {
            throw WatchRoundContextError.invalidStartedAt
        }
    }
}

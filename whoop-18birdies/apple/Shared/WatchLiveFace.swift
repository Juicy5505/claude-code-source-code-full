import Foundation

/// Live round face the iPhone publishes to Apple Watch: hole, optional
/// front/mid/back targeting overlay, last swing-to-swing shot yards, wrist,
/// club, and derived ball-start tendency.
///
/// - `lastShotYards`: consecutive verified swings via phone GPS
///   (`SwingShotInterval` / `ShotDistanceCalculator`). Nil until a second
///   swing finalizes the prior segment.
/// - `frontYards` / `middleYards` / `backYards`: optional green targeting
///   overlay from authorized hole geometry only. Facility search is not a
///   green map — never invent pins.
/// - `lastBallStartLabel` / `activeClubCode`: coaching overlays, not radar.
struct WatchLiveFace: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var holeNumber: Int?
    var frontYards: Int?
    var middleYards: Int?
    var backYards: Int?
    /// Stroke yards from the latest measured swing→swing GPS segment.
    var lastShotYards: Int?
    /// Latest body-relative path score (0…100) from the stroke chain.
    var lastPathScore: Int?
    /// Short path label (`on-plane`, `out-to-in`, …).
    var lastPathLabel: String?
    /// Verified stroke count for the active round.
    var strokeCount: Int?
    /// Active club short code (DR, 7i, …).
    var activeClubCode: String?
    /// Derived ball-start tendency short label (FADE, DRAW, …).
    var lastBallStartLabel: String?
    var wristMount: WatchWristMount
    var courseName: String?

    init(
        holeNumber: Int? = nil,
        frontYards: Int? = nil,
        middleYards: Int? = nil,
        backYards: Int? = nil,
        lastShotYards: Int? = nil,
        lastPathScore: Int? = nil,
        lastPathLabel: String? = nil,
        strokeCount: Int? = nil,
        activeClubCode: String? = nil,
        lastBallStartLabel: String? = nil,
        wristMount: WatchWristMount = .golferDefault,
        courseName: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.holeNumber = holeNumber
        self.frontYards = frontYards
        self.middleYards = middleYards
        self.backYards = backYards
        self.lastShotYards = lastShotYards
        self.lastPathScore = lastPathScore
        self.lastPathLabel = lastPathLabel
        self.strokeCount = strokeCount
        self.activeClubCode = activeClubCode
        self.lastBallStartLabel = lastBallStartLabel
        self.wristMount = wristMount
        self.courseName = courseName
    }

    var hasHoleMap: Bool {
        frontYards != nil || middleYards != nil || backYards != nil
    }
}

enum WatchLiveFaceCodec {
    static let applicationContextKey = "com.alex.whoopgolf.live-face"

    static func encode(_ face: WatchLiveFace) throws -> [String: Any] {
        let encoder = JSONEncoder()
        return [applicationContextKey: try encoder.encode(face)]
    }

    static func decode(_ applicationContext: [String: Any]) throws -> WatchLiveFace? {
        guard let rawValue = applicationContext[applicationContextKey] else { return nil }
        guard let data = rawValue as? Data else { return nil }
        return try JSONDecoder().decode(WatchLiveFace.self, from: data)
    }

    /// Merges live-face keys into an existing application-context dictionary
    /// without dropping the round-identity envelope.
    static func merge(_ face: WatchLiveFace, into context: [String: Any]) throws -> [String: Any] {
        var merged = context
        let encoded = try encode(face)
        for (key, value) in encoded {
            merged[key] = value
        }
        return merged
    }
}

import Foundation

/// Where the golfer wears Apple Watch during a round.
///
/// Alex's default is **trail-right**: a typical right-handed golfer with the
/// Watch on the right wrist, not Apple's left/lead-hand golf assumption.
/// Path, tempo, and improver math use `pathSign` so rotation polarity matches
/// that mount. Lead-left remains selectable; it is not the shipped default.
enum WatchWristMount: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Right wrist / trail hand for a typical right-handed golfer.
    case trailRight
    /// Left wrist / lead hand. Optional override, not the product default.
    case leadLeft

    var id: String { rawValue }

    static let golferDefault: WatchWristMount = .trailRight
    static let storageKey = "whoopgolf.watchWristMount"

    /// Multiplier applied to raw downswing yaw (°). Trail-right is −1 so the
    /// opposite-arm rotation polarity matches lead-left coaching labels
    /// (positive corrected yaw ⇒ in-to-out). Tempo ratios are time-based and
    /// do not use this sign.
    var pathSign: Double { self == .trailRight ? -1 : 1 }

    var displayName: String {
        switch self {
        case .trailRight: return "Right trail wrist"
        case .leadLeft: return "Left lead wrist"
        }
    }

    var coachingName: String {
        switch self {
        case .trailRight: return "trail wrist"
        case .leadLeft: return "lead wrist"
        }
    }

    var detail: String {
        switch self {
        case .trailRight:
            return "Watch on the right wrist. Path cues treat this as the trail hand for a typical right-handed golfer."
        case .leadLeft:
            return "Watch on the left wrist. Path cues treat this as the lead hand."
        }
    }

    /// Reads the persisted mount. When unset, writes and returns `golferDefault`
    /// (trail-right) so Settings / WCSession always see an explicit value.
    static func load(defaults: UserDefaults = .standard) -> WatchWristMount {
        if let raw = defaults.string(forKey: storageKey),
           let value = WatchWristMount(rawValue: raw) {
            return value
        }
        let fallback = WatchWristMount.golferDefault
        save(fallback, defaults: defaults)
        return fallback
    }

    static func save(_ value: WatchWristMount, defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: storageKey)
    }
}

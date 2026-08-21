import Foundation

// Phone <-> Watch coaching contract (path cue, improver tip/drill, wrist, HR).
//
// Lives in Shared/ because BOTH the iPhone target (WatchSessionReceiver) and the
// watchOS target (WatchSessionTransfer) encode/decode the same payload. Keeping
// it inside the iOS-only WatchSupport/WatchSessionReceiver.swift broke the
// WhoopGolfWatch build ("cannot find 'WatchCoachingCue' in scope").

/// Path cue + improver tip (+ optional drill) for WCSession applicationContext
/// and durable `transferUserInfo`. Strings only — no secrets, no device IDs.
struct WatchCoachingCue: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var pathCue: String?
    var improverTip: String?
    var improverDrill: String?
    var wristMount: String?
    var peakG: Double?
    var heartRateBPM: Int?

    init(
        pathCue: String? = nil,
        improverTip: String? = nil,
        improverDrill: String? = nil,
        wristMount: WatchWristMount? = nil,
        peakG: Double? = nil,
        heartRateBPM: Int? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.pathCue = pathCue
        self.improverTip = improverTip
        self.improverDrill = improverDrill
        self.wristMount = wristMount?.rawValue
        self.peakG = peakG
        self.heartRateBPM = heartRateBPM
    }
}

enum WatchCoachingCueCodec {
    static let applicationContextKey = "com.alex.whoopgolf.coaching"
    /// Flat userInfo key distinguishing coaching transfers from other payloads.
    static let userInfoKindKey = "kind"
    static let userInfoKindValue = "coaching"

    static func encode(_ cue: WatchCoachingCue) throws -> [String: Any] {
        [applicationContextKey: try JSONEncoder().encode(cue)]
    }

    static func decode(_ applicationContext: [String: Any]) throws -> WatchCoachingCue? {
        guard let rawValue = applicationContext[applicationContextKey] else { return nil }
        guard let data = rawValue as? Data else { return nil }
        return try JSONDecoder().decode(WatchCoachingCue.self, from: data)
    }

    static func merge(_ cue: WatchCoachingCue, into context: [String: Any]) throws -> [String: Any] {
        var merged = context
        for (key, value) in try encode(cue) {
            merged[key] = value
        }
        return merged
    }

    /// Property-list-safe durable transfer (survives when the counterpart is
    /// not reachable). Prefer this over `sendMessage` for coaching.
    static func userInfo(from cue: WatchCoachingCue) -> [String: Any] {
        var info: [String: Any] = [
            userInfoKindKey: userInfoKindValue,
            "schemaVersion": cue.schemaVersion,
        ]
        if let pathCue = cue.pathCue { info["pathCue"] = pathCue }
        if let tip = cue.improverTip { info["improverTip"] = tip }
        if let drill = cue.improverDrill { info["improverDrill"] = drill }
        if let wrist = cue.wristMount { info["wristMount"] = wrist }
        if let peakG = cue.peakG, peakG.isFinite { info["peakG"] = peakG }
        if let hr = cue.heartRateBPM { info["hr"] = hr }
        return info
    }

    static func cue(fromUserInfo info: [String: Any]) -> WatchCoachingCue? {
        let kind = info[userInfoKindKey] as? String
        let hasCoachingKeys = info["pathCue"] != nil
            || info["improverTip"] != nil
            || info["path"] != nil
        guard kind == userInfoKindValue || hasCoachingKeys else { return nil }

        let pathCue = (info["pathCue"] as? String) ?? (info["path"] as? String)
        let tip = info["improverTip"] as? String
        let drill = info["improverDrill"] as? String
        let wristRaw = info["wristMount"] as? String
        let peakG = info["peakG"] as? Double
        let hr = info["hr"] as? Int ?? info["heartRateBPM"] as? Int
        return WatchCoachingCue(
            pathCue: pathCue,
            improverTip: tip,
            improverDrill: drill,
            wristMount: wristRaw.flatMap(WatchWristMount.init(rawValue:)),
            peakG: peakG,
            heartRateBPM: hr
        )
    }
}

import Foundation

// MARK: - Club catalog

/// Golfer-selected club for the stroke journal. Sensors never invent club;
/// the Watch/phone picker owns this field.
enum GolfClubKind: String, Codable, CaseIterable, Hashable, Sendable {
    case driver
    case threeWood
    case fiveWood
    case hybrid
    case threeIron
    case fourIron
    case fiveIron
    case sixIron
    case sevenIron
    case eightIron
    case nineIron
    case pitchingWedge
    case gapWedge
    case sandWedge
    case lobWedge
    case putter
    case other

    static let storageKey = "whoopgolf.activeClub"

    var displayName: String {
        switch self {
        case .driver: "Driver"
        case .threeWood: "3-wood"
        case .fiveWood: "5-wood"
        case .hybrid: "Hybrid"
        case .threeIron: "3-iron"
        case .fourIron: "4-iron"
        case .fiveIron: "5-iron"
        case .sixIron: "6-iron"
        case .sevenIron: "7-iron"
        case .eightIron: "8-iron"
        case .nineIron: "9-iron"
        case .pitchingWedge: "PW"
        case .gapWedge: "GW"
        case .sandWedge: "SW"
        case .lobWedge: "LW"
        case .putter: "Putter"
        case .other: "Other"
        }
    }

    var shortCode: String {
        switch self {
        case .driver: "DR"
        case .threeWood: "3W"
        case .fiveWood: "5W"
        case .hybrid: "HY"
        case .threeIron: "3i"
        case .fourIron: "4i"
        case .fiveIron: "5i"
        case .sixIron: "6i"
        case .sevenIron: "7i"
        case .eightIron: "8i"
        case .nineIron: "9i"
        case .pitchingWedge: "PW"
        case .gapWedge: "GW"
        case .sandWedge: "SW"
        case .lobWedge: "LW"
        case .putter: "PT"
        case .other: "CL"
        }
    }

    static func normalize(_ raw: String?) -> GolfClubKind? {
        guard let trimmed = StrokeClubHint.normalize(raw) else { return nil }
        let key = trimmed.lowercased()
        if let exact = GolfClubKind(rawValue: key) { return exact }
        switch key {
        case "dr", "1w", "driver": return .driver
        case "3w", "3-wood", "three wood": return .threeWood
        case "5w", "5-wood": return .fiveWood
        case "hy", "hybrid", "rescue": return .hybrid
        case "3i", "3-iron": return .threeIron
        case "4i", "4-iron": return .fourIron
        case "5i", "5-iron": return .fiveIron
        case "6i", "6-iron": return .sixIron
        case "7i", "7-iron": return .sevenIron
        case "8i", "8-iron": return .eightIron
        case "9i", "9-iron": return .nineIron
        case "pw", "pitching": return .pitchingWedge
        case "gw", "aw", "gap": return .gapWedge
        case "sw", "sand": return .sandWedge
        case "lw", "lob": return .lobWedge
        case "pt", "putter": return .putter
        default: return .other
        }
    }

    static func load(defaults: UserDefaults = .standard) -> GolfClubKind {
        guard let raw = defaults.string(forKey: storageKey),
              let club = GolfClubKind(rawValue: raw) ?? normalize(raw) else {
            return .sevenIron
        }
        return club
    }

    static func save(_ club: GolfClubKind, defaults: UserDefaults = .standard) {
        defaults.set(club.rawValue, forKey: storageKey)
    }
}

// MARK: - Ball-start tendency (derived, not radar)

/// Estimated ball-start / curve **tendency** from wrist path + tempo.
/// Explicitly not launch-monitor carry, spin, or apex.
enum BallStartBias: String, Codable, CaseIterable, Hashable, Sendable {
    case straight
    case pull
    case pullFade
    case fade
    case push
    case pushDraw
    case draw
    case unknown

    var title: String {
        switch self {
        case .straight: "Straight tendency"
        case .pull: "Pull start"
        case .pullFade: "Pull-fade"
        case .fade: "Fade tendency"
        case .push: "Push start"
        case .pushDraw: "Push-draw"
        case .draw: "Draw tendency"
        case .unknown: "Ball start unknown"
        }
    }

    var shortLabel: String {
        switch self {
        case .straight: "STRAIGHT"
        case .pull: "PULL"
        case .pullFade: "P-FADE"
        case .fade: "FADE"
        case .push: "PUSH"
        case .pushDraw: "P-DRAW"
        case .draw: "DRAW"
        case .unknown: "—"
        }
    }
}

/// Attack / delivery feel from tempo + path severity — coaching only.
enum AttackFeel: String, Codable, CaseIterable, Hashable, Sendable {
    case neutral
    case steep
    case shallow
    case rushed
    case lazy
    case unknown

    var title: String {
        switch self {
        case .neutral: "Neutral delivery"
        case .steep: "Steep feel"
        case .shallow: "Shallow feel"
        case .rushed: "Rushed transition"
        case .lazy: "Late transition"
        case .unknown: "Delivery unknown"
        }
    }
}

// MARK: - Comprehensive shot dossier

/// One fused stroke intelligence packet: Watch live path + optional WHOOP
/// wrist enrich + club + derived ball-start bias + GPS yards.
struct ComprehensiveShotDossier: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let sequence: Int
    let club: GolfClubKind?
    let pathClass: SwingPathClass
    let pathScore: Int?
    let pathExplanation: String
    let ballStartBias: BallStartBias
    let ballStartDetail: String
    let attackFeel: AttackFeel
    let attackDetail: String
    let tempoRatio: Double?
    let peakG: Double
    let shotYards: Double?
    let heartRateBPM: Int?
    let watchLive: Bool
    let whoopEnriched: Bool
    let improverCue: String
    let fusionCaption: String
}

/// Builds honest dual-wearable tracking dossiers. Never invents clubhead path,
/// face angle, or measured ball flight from wrist IMU alone.
enum ComprehensiveShotIntelligence {
    /// Shared UI/copy: ball-start is coaching tendency, not radar.
    static let tendencyDisclaimer =
        "Ball-start is a wrist-path tendency — not launch-monitor carry, spin, or apex."

    /// Club chip when the golfer has not tagged a club for this stroke.
    static let untaggedClubLabel = "Club not tagged"
    static let untaggedClubCode = "—"

    static func clubDisplayName(_ club: GolfClubKind?) -> String {
        club?.displayName ?? untaggedClubLabel
    }

    static func clubShortCode(_ club: GolfClubKind?) -> String {
        club?.shortCode ?? untaggedClubCode
    }

    static func pathScoreLine(_ score: Int?) -> String {
        guard let score else { return "—" }
        return "\(score)"
    }

    static func ballStartBias(
        path: SwingPathClass,
        severity: PathMissSeverity = .unknown,
        tempoRatio: Double? = nil
    ) -> (BallStartBias, String) {
        switch path {
        case .onPlane:
            return (
                .straight,
                "Wrist arc stayed near on-plane — expect a more centered start; face/aim still own leftover curve."
            )
        case .outToIn:
            switch severity {
            case .mild:
                return (.fade, "Mild out-to-in wrist path — fade / soft left miss tendency (right-hander).")
            case .moderate, .severe:
                return (.pullFade, "Stronger out-to-in — pull-fade / cut-start tendency. Prefer an inside approach.")
            default:
                return (.pull, "Out-to-in wrist path — pull / cut-start bias until the downswing stays inside.")
            }
        case .inToOut:
            switch severity {
            case .mild:
                return (.draw, "Mild in-to-out wrist path — draw / soft right miss tendency (right-hander).")
            case .moderate, .severe:
                return (.pushDraw, "Stronger in-to-out — push-draw / hook-start tendency. Quiet the hands through impact.")
            default:
                return (.push, "In-to-out wrist path — push / hook-start bias until the path quiets.")
            }
        case .unknown:
            _ = tempoRatio
            return (.unknown, "Need a readable Watch path sample before ball-start tendency is estimated.")
        }
    }

    static func attackFeel(
        path: SwingPathClass,
        tempoRatio: Double?,
        peakG: Double
    ) -> (AttackFeel, String) {
        if let tempo = tempoRatio, tempo.isFinite, tempo > 0 {
            if tempo < GolfImprover.tourTempo - GolfImprover.tempoSlack {
                return (.rushed, "Tempo quicker than Tour 3:1 — transition feel is rushed; pause at the top.")
            }
            if tempo > GolfImprover.tourTempo + GolfImprover.tempoSlack {
                return (.lazy, "Tempo slower than Tour 3:1 — late transition; start down a beat sooner.")
            }
        }
        switch path {
        case .outToIn:
            return (.steep, "Out-to-in often pairs with a steeper delivery feel — flatten the downswing plane.")
        case .inToOut:
            return (.shallow, "In-to-out often pairs with a shallower delivery feel — keep width without flipping.")
        case .onPlane:
            if peakG >= 8 {
                return (.neutral, "On-plane with strong peak load — hold the same delivery width.")
            }
            return (.neutral, "On-plane delivery feel — keep tempo near 3:1.")
        case .unknown:
            return (.unknown, "Attack/delivery feel pending a scored Watch path.")
        }
    }

    static func dossier(
        for swing: GolfSwingMetrics,
        sequence: Int,
        wrist: WatchWristMount = .golferDefault,
        defaultClub: GolfClubKind? = nil
    ) -> ComprehensiveShotDossier {
        let row = GolfStrokePresentationProxy.score(for: swing, wrist: wrist)
        // Prefer live path math for bias/attack so enrichTrackingFields and UI
        // stay coherent. Persisted strings are overwritten on enrich.
        let (bias, biasDetail) = ballStartBias(
            path: row.path,
            severity: row.severity,
            tempoRatio: swing.tempoRatio
        )
        let (attack, attackDetailText) = attackFeel(
            path: row.path,
            tempoRatio: swing.tempoRatio,
            peakG: swing.peakG
        )
        let whoop = swing.wristAnalysis != nil
            || swing.provenance.source == .whoopMotion
            || swing.provenance.inputSources.contains(.whoopMotion)
            || swing.provenance.source == .derived
        let watch = swing.provenance.source == .appleWatch
            || swing.provenance.inputSources.contains(.appleWatch)
            || swing.provenance.source == .derived
        let fusion: String
        if watch && whoop {
            fusion = "Hybrid · Watch identity + WHOOP wrist enrich · one counted shot"
        } else if watch {
            fusion = "Watch live · awaiting WHOOP delayed enrich"
        } else if whoop {
            fusion = "WHOOP delayed · Watch identity preferred when both present"
        } else {
            fusion = "Manual / incomplete wearable provenance"
        }

        let club = GolfClubKind.normalize(swing.club) ?? defaultClub
        // Keep persisted detail only when it still matches the recomputed bias.
        let detail: String
        if let persisted = swing.ballStartDetail,
           !persisted.isEmpty,
           swing.resolvedBallStartBias == bias {
            detail = persisted
        } else {
            detail = biasDetail
        }

        return ComprehensiveShotDossier(
            id: swing.id,
            sequence: sequence,
            club: club,
            pathClass: row.path,
            pathScore: row.pathScore,
            pathExplanation: row.explanation.isEmpty
                ? "Path explanation pending a readable Watch sample."
                : row.explanation,
            ballStartBias: bias,
            ballStartDetail: detail,
            attackFeel: attack,
            attackDetail: attackDetailText,
            tempoRatio: swing.tempoRatio,
            peakG: swing.peakG,
            shotYards: swing.shotYards,
            heartRateBPM: swing.heartRateBPM,
            watchLive: watch,
            whoopEnriched: whoop,
            improverCue: row.tip.cue,
            fusionCaption: fusion
        )
    }

    static func dossiers(
        for round: GolfRound,
        wrist: WatchWristMount = .golferDefault,
        defaultClub: GolfClubKind? = nil
    ) -> [ComprehensiveShotDossier] {
        let ordered = round.swings.sorted { $0.capturedAt < $1.capturedAt }
        return ordered.enumerated().map { index, swing in
            dossier(for: swing, sequence: index + 1, wrist: wrist, defaultClub: defaultClub)
        }
    }

    /// Enrich metrics with club + derived ball-start / attack fields.
    /// Same derivation path as `dossier` so persisted strings match UI packets.
    static func enrichTrackingFields(
        _ swings: [GolfSwingMetrics],
        defaultClub: GolfClubKind? = nil,
        wrist: WatchWristMount = .golferDefault
    ) -> [GolfSwingMetrics] {
        swings.map { swing in
            let packet = dossier(
                for: swing,
                sequence: 1,
                wrist: wrist,
                defaultClub: defaultClub
            )
            return swing.withComprehensiveTracking(
                club: packet.club?.rawValue ?? swing.club,
                ballStartBias: packet.ballStartBias.rawValue,
                attackFeel: packet.attackFeel.rawValue,
                ballStartDetail: packet.ballStartDetail
            )
        }
    }
}

extension ComprehensiveShotDossier {
    var clubDisplayName: String {
        ComprehensiveShotIntelligence.clubDisplayName(club)
    }

    var clubShortCode: String {
        ComprehensiveShotIntelligence.clubShortCode(club)
    }

    var pathScoreLine: String {
        ComprehensiveShotIntelligence.pathScoreLine(pathScore)
    }
}

/// Thin adapter so Shared intelligence can score without importing UI modules.
/// Mirrors `GolfImprover.strokeScore` inputs already on the swing.
private enum GolfStrokePresentationProxy {
    struct Score {
        let path: SwingPathClass
        let pathScore: Int?
        let severity: PathMissSeverity
        let explanation: String
        let tip: ImproverTip
    }

    static func score(for swing: GolfSwingMetrics, wrist: WatchWristMount) -> Score {
        let path = swing.resolvedPathClass != .unknown
            ? swing.resolvedPathClass
            : {
                guard let yaw = swing.pathYawDegrees, yaw.isFinite else { return SwingPathClass.unknown }
                // Stored yaw is mount-corrected — classify with leadLeft to avoid double flip.
                return SwingPathGuidance.classify(downswingYawDegrees: yaw, wrist: .leadLeft).path
            }()
        let live = GolfImprover.strokeScore(
            path: path,
            correctedYawDegrees: swing.pathYawDegrees,
            tempoRatio: swing.tempoRatio,
            wrist: wrist,
            id: swing.id
        )
        if let persisted = swing.pathScore {
            return Score(
                path: path,
                pathScore: persisted,
                severity: live.severity,
                explanation: swing.pathExplanation ?? live.explanation,
                tip: live.tip
            )
        }
        return Score(
            path: live.path,
            pathScore: live.pathScore,
            severity: live.severity,
            explanation: live.explanation,
            tip: live.tip
        )
    }
}

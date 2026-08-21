import Foundation

/// Wrist-rotation path cue from Watch CoreMotion attitude. This is not clubhead
/// path, face angle, or ball flight — it is an on-wrist in-to-out / on-plane /
/// out-to-in hint after correcting for Watch mount (`WatchWristMount.pathSign`).
enum SwingPathClass: String, Codable, Hashable, Sendable {
    case inToOut
    case onPlane
    case outToIn
    case unknown
}

/// Who produced the body-relative path score for a stroke.
/// Watch Series 5 is the live scorer; WHOOP delayed frames may refine later.
enum SwingPathScorer: String, Codable, Hashable, Sendable {
    case watchLive
    case whoopRefined
}

/// Per-stroke body-relative path score for trail-right (default) Watch motion.
/// Codable feed for **stroke-score-shot-chain** (snake_case keys).
///
/// Honesty: score is wrist-path quality relative to the golfer's body plane
/// cue — not clubhead path, face angle, or ball flight.
struct SwingPathStrokeScore: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    /// 0…100 body-relative plane quality. Nil when yaw cannot be scored.
    let score: Int?
    let pathClass: SwingPathClass
    /// Mount-corrected yaw (°). Positive ⇒ in-to-out.
    let correctedYawDegrees: Double?
    let explanation: String
    let wrist: WatchWristMount
    let scorer: SwingPathScorer
    let tempoRatio: Double?
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case score
        case pathClass = "path_class"
        case correctedYawDegrees = "corrected_yaw_deg"
        case explanation
        case wrist
        case scorer
        case tempoRatio = "tempo_ratio"
        case schemaVersion = "schema_version"
    }

    init(
        score: Int?,
        pathClass: SwingPathClass,
        correctedYawDegrees: Double?,
        explanation: String,
        wrist: WatchWristMount,
        scorer: SwingPathScorer,
        tempoRatio: Double? = nil,
        schemaVersion: Int = SwingPathStrokeScore.currentSchemaVersion
    ) {
        self.score = score
        self.pathClass = pathClass
        self.correctedYawDegrees = correctedYawDegrees
        self.explanation = explanation
        self.wrist = wrist
        self.scorer = scorer
        self.tempoRatio = tempoRatio
        self.schemaVersion = schemaVersion
    }
}

/// Shared path classifier + per-stroke scorer used by Watch `SwingAnalysis`,
/// WhoopGolfTests, and the stroke-score-shot-chain feed.
///
/// API:
/// - `classify(downswingYawDegrees:wrist:)` → `(path, correctedYawDegrees)`
/// - `scoreStroke(...)` → live Watch `SwingPathStrokeScore` (numeric + explanation)
/// - `refineWithWhoop(live:whoopDownswingYawDegrees:whoopWrist:)` → optional delayed refine
/// - `coachingLabel` / `provenanceCaption` → short UI strings
///
/// Contract: raw downswing yaw is device degrees (transition→impact, unwrapped).
/// After `× wrist.pathSign`, **positive ⇒ in-to-out**, **|yaw| < onPlaneDegrees ⇒
/// on-plane**. Default `wrist` is `.golferDefault` (trail-right).
enum SwingPathGuidance {
    /// Degrees of mount-corrected downswing yaw treated as on-plane.
    static let onPlaneDegrees = 8.0

    /// Gaussian width (°): score ≈ 100·exp(−(yaw/σ)²). σ=18 keeps |8°|≈85.
    static let scoreSigmaDegrees = 18.0

    /// Live Watch weight when blending a delayed WHOOP yaw refine.
    static let liveBlendWeight = 0.7

    /// Classifies signed downswing yaw in device degrees, then applies wrist
    /// mount polarity. Positive after correction is in-to-out.
    static func classify(
        downswingYawDegrees: Double?,
        wrist: WatchWristMount = .golferDefault
    ) -> (path: SwingPathClass, correctedYawDegrees: Double?) {
        guard let yaw = downswingYawDegrees, yaw.isFinite else {
            return (.unknown, nil)
        }
        let corrected = yaw * wrist.pathSign
        let path: SwingPathClass
        if abs(corrected) < onPlaneDegrees {
            path = .onPlane
        } else if corrected > 0 {
            path = .inToOut
        } else {
            path = .outToIn
        }
        return (path, round1(corrected))
    }

    /// Live Series 5 scorer: body-relative numeric score + explanation per stroke.
    static func scoreStroke(
        downswingYawDegrees: Double?,
        tempoRatio: Double? = nil,
        wrist: WatchWristMount = .golferDefault
    ) -> SwingPathStrokeScore {
        let classified = classify(downswingYawDegrees: downswingYawDegrees, wrist: wrist)
        return makeScore(
            path: classified.path,
            correctedYaw: classified.correctedYawDegrees,
            tempoRatio: tempoRatio,
            wrist: wrist,
            scorer: .watchLive
        )
    }

    /// **stroke-score-shot-chain** entry: Watch is always the live scorer; pass
    /// optional delayed WHOOP yaw to refine. Compose with
    /// `GolfImprover.strokeScore(path:correctedYawDegrees:tempoRatio:wrist:)`
    /// for drills/miss tips without inventing a second path classifier.
    static func scoreForShotChain(
        watchDownswingYawDegrees: Double?,
        tempoRatio: Double? = nil,
        wrist: WatchWristMount = .golferDefault,
        whoopDownswingYawDegrees: Double? = nil,
        whoopWrist: WatchWristMount = .leadLeft
    ) -> SwingPathStrokeScore {
        let live = scoreStroke(
            downswingYawDegrees: watchDownswingYawDegrees,
            tempoRatio: tempoRatio,
            wrist: wrist
        )
        return refineWithWhoop(
            live: live,
            whoopDownswingYawDegrees: whoopDownswingYawDegrees,
            whoopWrist: whoopWrist
        )
    }

    /// Optional delayed WHOOP refine. Watch remains the live shot clock; WHOOP
    /// may nudge path score when a comparable downswing yaw is present.
    /// Pass `whoopWrist` for the band mount (often lead-left while Watch is
    /// trail-right). Nil/non-finite WHOOP yaw returns `live` unchanged.
    static func refineWithWhoop(
        live: SwingPathStrokeScore,
        whoopDownswingYawDegrees: Double?,
        whoopWrist: WatchWristMount = .leadLeft
    ) -> SwingPathStrokeScore {
        guard let whoopRaw = whoopDownswingYawDegrees, whoopRaw.isFinite,
              let liveYaw = live.correctedYawDegrees
        else {
            return live
        }
        let whoopCorrected = whoopRaw * whoopWrist.pathSign
        let blended = liveBlendWeight * liveYaw + (1 - liveBlendWeight) * whoopCorrected
        let path: SwingPathClass
        if abs(blended) < onPlaneDegrees {
            path = .onPlane
        } else if blended > 0 {
            path = .inToOut
        } else {
            path = .outToIn
        }
        return makeScore(
            path: path,
            correctedYaw: round1(blended),
            tempoRatio: live.tempoRatio,
            wrist: live.wrist,
            scorer: .whoopRefined
        )
    }

    static func coachingLabel(_ path: SwingPathClass) -> String {
        switch path {
        case .inToOut: return "in-to-out"
        case .onPlane: return "on-plane"
        case .outToIn: return "out-to-in"
        case .unknown: return "no path yet"
        }
    }

    static func provenanceCaption(wrist: WatchWristMount) -> String {
        "\(wrist.coachingName) path cue · not clubhead path"
    }

    // MARK: - Internals

    private static func makeScore(
        path: SwingPathClass,
        correctedYaw: Double?,
        tempoRatio: Double?,
        wrist: WatchWristMount,
        scorer: SwingPathScorer
    ) -> SwingPathStrokeScore {
        let score: Int?
        if let yaw = correctedYaw, yaw.isFinite, path != .unknown {
            let gaussian = exp(-pow(abs(yaw) / scoreSigmaDegrees, 2))
            score = max(5, min(100, Int((100 * gaussian).rounded(.toNearestOrEven))))
        } else {
            score = nil
        }
        return SwingPathStrokeScore(
            score: score,
            pathClass: path,
            correctedYawDegrees: correctedYaw,
            explanation: explanation(
                path: path,
                correctedYaw: correctedYaw,
                tempoRatio: tempoRatio,
                wrist: wrist,
                scorer: scorer,
                score: score
            ),
            wrist: wrist,
            scorer: scorer,
            tempoRatio: tempoRatio
        )
    }

    private static func explanation(
        path: SwingPathClass,
        correctedYaw: Double?,
        tempoRatio: Double?,
        wrist: WatchWristMount,
        scorer: SwingPathScorer,
        score: Int?
    ) -> String {
        let mount = wrist.coachingName
        let source: String
        switch scorer {
        case .watchLive:
            source = "Live Watch"
        case .whoopRefined:
            source = "Watch live + WHOOP refine"
        }
        let pathLine: String
        switch path {
        case .unknown:
            pathLine = "No body-relative path yet on the \(mount) — pause at address so yaw can read."
        case .onPlane:
            if let yaw = correctedYaw, let score {
                pathLine = "On-plane \(mount) cue (\(fmt(yaw))°). Score \(score)/100 · \(source)."
            } else {
                pathLine = "On-plane \(mount) cue · \(source)."
            }
        case .inToOut:
            if let yaw = correctedYaw, let score {
                pathLine = "In-to-out \(mount) path (+\(fmt(abs(yaw)))°). Score \(score)/100 · \(source). Not clubhead path."
            } else {
                pathLine = "In-to-out \(mount) path cue · \(source)."
            }
        case .outToIn:
            if let yaw = correctedYaw, let score {
                pathLine = "Out-to-in \(mount) path (−\(fmt(abs(yaw)))°). Score \(score)/100 · \(source). Not clubhead path."
            } else {
                pathLine = "Out-to-in \(mount) path cue · \(source)."
            }
        }
        if let tempoRatio, tempoRatio.isFinite {
            let delta = tempoRatio - 3.0
            if abs(delta) > 0.6 {
                let tempoNote = delta < 0
                    ? " Tempo quick vs 3:1."
                    : " Tempo slow vs 3:1."
                return pathLine + tempoNote
            }
        }
        return pathLine
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded(.toNearestOrEven) / 10
    }
}

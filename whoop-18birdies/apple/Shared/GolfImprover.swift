import Foundation

// MARK: - Models (Watch + phone UI agents)

/// What the improver wants the golfer to feel on the next swing.
enum ImproverFocus: String, Codable, Hashable, Sendable {
    case tempoRush
    case tempoSlow
    case pathOutToIn
    case pathInToOut
    case pathOnPlane
    case unknown
}

/// Severity of the mount-corrected path miss (wrist yaw, not clubhead).
enum PathMissSeverity: String, Codable, Hashable, Sendable {
    case none
    case mild
    case moderate
    case severe
    case unknown
}

/// One short range drill the IMPROVE page can show under the cue.
struct ImproverDrill: Codable, Hashable, Sendable {
    let title: String
    let instruction: String

    /// Watch-ready single string (`Drill: …`).
    var displayLine: String { "Drill: \(instruction)" }
}

/// Coaching packet for Watch IMPROVE / phone stroke detail.
struct ImproverTip: Codable, Hashable, Sendable {
    let focus: ImproverFocus
    let cue: String
    let drill: ImproverDrill
    /// Alternate drill if the first feels stale.
    let alternateDrill: ImproverDrill
    let wristFeel: String
    /// Likely ball-flight tendency language — framed as a *hint*, not a launch monitor.
    let missAdvice: String
    /// One-line post-swing strip (haptic / session status).
    let postSwing: String
}

/// Path score + explanation paired with one stroke for Watch and phone.
///
/// Score is derived from mount-corrected downswing yaw (`SwingPathGuidance`).
/// Positive yaw ⇒ in-to-out after trail-right correction. This is **not**
/// clubhead path, face angle, or measured ball flight.
struct SwingStrokeScore: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let path: SwingPathClass
    /// Mount-corrected yaw degrees (positive = in-to-out).
    let correctedYawDegrees: Double?
    /// 0…100 when path is known; `nil` when unknown / no yaw.
    let pathScore: Int?
    let severity: PathMissSeverity
    let pathLabel: String
    /// Why this score (plain language for the stroke row).
    let explanation: String
    /// Short Watch headline (`on-plane · 92`).
    let scoreHeadline: String
    let tempoRatio: Double?
    let tip: ImproverTip

    var cue: String { tip.cue }
    var drillLine: String { tip.drill.displayLine }
    var missAdvice: String { tip.missAdvice }
}

/// On-wrist / phone practice loop: path score, tempo vs Tour 3:1, miss advice, drills.
///
/// Copy assumes Watch mount in `wrist` (shipped default: **trail-right**).
/// Keep `cue` / `drill` / `consistencyCaption` signatures stable for existing
/// Watch face + WhoopGolfTests call sites.
enum GolfImprover {
    static let tourTempo = 3.0
    /// Absolute deviation from `tourTempo` that triggers tempo-first coaching.
    static let tempoSlack = 0.6

    // MARK: - Stroke score + tip (primary API for UI agents)

    /// Full stroke coaching: path score, explanation, cue, drills, miss advice.
    static func strokeScore(
        path: SwingPathClass,
        correctedYawDegrees: Double?,
        tempoRatio: Double? = nil,
        wrist: WatchWristMount = .golferDefault,
        tempoCV: Double? = nil,
        id: UUID = UUID()
    ) -> SwingStrokeScore {
        let scored = scorePath(path: path, correctedYawDegrees: correctedYawDegrees)
        let tip = tip(
            path: path,
            tempoRatio: tempoRatio,
            wrist: wrist,
            tempoCV: tempoCV,
            correctedYawDegrees: correctedYawDegrees,
            severity: scored.severity
        )
        let headline: String
        if let score = scored.score {
            headline = "\(scored.label) · \(score)"
        } else {
            headline = scored.label
        }
        return SwingStrokeScore(
            id: id,
            path: path,
            correctedYawDegrees: correctedYawDegrees,
            pathScore: scored.score,
            severity: scored.severity,
            pathLabel: scored.label,
            explanation: scored.explanation,
            scoreHeadline: headline,
            tempoRatio: tempoRatio,
            tip: tip
        )
    }

    /// Structured tip without requiring a score id (Watch IMPROVE page).
    static func tip(
        path: SwingPathClass,
        tempoRatio: Double?,
        wrist: WatchWristMount = .golferDefault,
        tempoCV: Double? = nil,
        correctedYawDegrees: Double? = nil,
        severity: PathMissSeverity? = nil
    ) -> ImproverTip {
        let focus = resolveFocus(path: path, tempoRatio: tempoRatio)
        let sev = severity ?? scorePath(path: path, correctedYawDegrees: correctedYawDegrees).severity
        return ImproverTip(
            focus: focus,
            cue: cueText(focus: focus, wrist: wrist),
            drill: primaryDrill(focus: focus, wrist: wrist),
            alternateDrill: alternateDrill(focus: focus, wrist: wrist),
            wristFeel: wrist.coachingName,
            missAdvice: missAdvice(path: path, severity: sev, wrist: wrist),
            postSwing: postSwingText(
                focus: focus,
                path: path,
                tempoRatio: tempoRatio,
                tempoCV: tempoCV,
                severity: sev
            )
        )
    }

    // MARK: - Stable string API (WatchRoundFaceView / tests)

    static func cue(
        path: SwingPathClass,
        tempoRatio: Double?,
        wrist: WatchWristMount = .golferDefault
    ) -> String {
        tip(path: path, tempoRatio: tempoRatio, wrist: wrist).cue
    }

    static func drill(
        path: SwingPathClass,
        tempoRatio: Double?,
        wrist: WatchWristMount = .golferDefault
    ) -> String {
        tip(path: path, tempoRatio: tempoRatio, wrist: wrist).drill.displayLine
    }

    static func consistencyCaption(tempoCV: Double?) -> String {
        guard let tempoCV, tempoCV.isFinite else { return "Need 2+ timed swings for consistency" }
        if tempoCV < 0.12 { return "Tempo is tight — keep the same feel" }
        if tempoCV < 0.22 { return "Tempo is usable — shrink the spread" }
        return "Tempo is scattered — one rehearsal cue per swing"
    }

    /// Phone stroke-list blurb: score + one sentence explanation.
    static func phoneStrokeSummary(_ stroke: SwingStrokeScore) -> String {
        if let score = stroke.pathScore {
            return "\(stroke.scoreHeadline) — \(stroke.explanation)"
        }
        return stroke.explanation
    }

    // MARK: - Path scoring

    private struct ScoredPath {
        let score: Int?
        let severity: PathMissSeverity
        let label: String
        let explanation: String
    }

    /// Maps corrected yaw → 0…100. On-plane band matches `SwingPathGuidance.onPlaneDegrees` (8°).
    private static func scorePath(
        path: SwingPathClass,
        correctedYawDegrees: Double?
    ) -> ScoredPath {
        let label = SwingPathGuidance.coachingLabel(path)
        guard path != .unknown, let yaw = correctedYawDegrees, yaw.isFinite else {
            return ScoredPath(
                score: nil,
                severity: .unknown,
                label: label,
                explanation: "No usable wrist path yet — pause still at address so yaw can settle before the takeaway."
            )
        }

        let absYaw = abs(yaw)
        let onPlane = SwingPathGuidance.onPlaneDegrees

        switch path {
        case .onPlane:
            // 0° → 98, edge of band (~8°) → ~78
            let t = min(1, absYaw / onPlane)
            let score = Int((98.0 - t * 20.0).rounded(.toNearestOrEven))
            let explanation: String
            if absYaw < 3 {
                explanation = "Wrist path stayed nearly neutral through the downswing — repeatable on-plane feel."
            } else {
                explanation = String(
                    format: "On-plane band (within ±%.0f°). Corrected yaw %+.1f° — slight drift but still in the fairway of the wrist path.",
                    onPlane,
                    yaw
                )
            }
            return ScoredPath(score: score, severity: .none, label: label, explanation: explanation)

        case .outToIn, .inToOut:
            let severity: PathMissSeverity
            let score: Int
            if absYaw < 14 {
                severity = .mild
                score = Int((72.0 - (absYaw - onPlane) * 1.5).rounded(.toNearestOrEven))
            } else if absYaw < 22 {
                severity = .moderate
                score = Int((58.0 - (absYaw - 14) * 2.0).rounded(.toNearestOrEven))
            } else {
                severity = .severe
                score = Int(max(18, 42.0 - (absYaw - 22) * 1.2).rounded(.toNearestOrEven))
            }
            let clamped = max(12, min(78, score))
            let direction = path == .outToIn ? "out-to-in" : "in-to-out"
            let explanation = String(
                format: "Mount-corrected yaw %+.1f° reads %@ (%@). Score drops as the trail-wrist arc leaves the ±%.0f° on-plane corridor.",
                yaw,
                direction,
                severity.rawValue,
                onPlane
            )
            return ScoredPath(score: clamped, severity: severity, label: label, explanation: explanation)

        case .unknown:
            return ScoredPath(
                score: nil,
                severity: .unknown,
                label: label,
                explanation: "No usable wrist path yet — pause still at address so yaw can settle before the takeaway."
            )
        }
    }

    // MARK: - Focus / copy

    private static func resolveFocus(path: SwingPathClass, tempoRatio: Double?) -> ImproverFocus {
        if let band = tempoBand(tempoRatio) {
            switch band {
            case .rushing: return .tempoRush
            case .slow: return .tempoSlow
            }
        }
        switch path {
        case .outToIn: return .pathOutToIn
        case .inToOut: return .pathInToOut
        case .onPlane: return .pathOnPlane
        case .unknown: return .unknown
        }
    }

    private enum TempoBand {
        case rushing
        case slow
    }

    private static func tempoBand(_ tempoRatio: Double?) -> TempoBand? {
        guard let tempoRatio, tempoRatio.isFinite else { return nil }
        if tempoRatio < tourTempo - tempoSlack { return .rushing }
        if tempoRatio > tourTempo + tempoSlack { return .slow }
        return nil
    }

    private static func cueText(focus: ImproverFocus, wrist: WatchWristMount) -> String {
        switch focus {
        case .tempoRush:
            return "Rushing the takeaway — pause at the top"
        case .tempoSlow:
            return "Slow takeaway relative to the downswing — start down sooner"
        case .pathOutToIn:
            return wrist == .trailRight
                ? "Out-to-in · keep the trail elbow in, start down from inside"
                : "Out-to-in · feel the lead arm drop inside before you unwind"
        case .pathInToOut:
            return wrist == .trailRight
                ? "In-to-out · quiet the trail hand through impact"
                : "In-to-out · don't stall the lead wrist through the ball"
        case .pathOnPlane:
            return "On-plane · repeat that \(wrist.coachingName) feel"
        case .unknown:
            return "Pause at address so tempo and path can read"
        }
    }

    private static func primaryDrill(focus: ImproverFocus, wrist: WatchWristMount) -> ImproverDrill {
        // Tempo overrides path for the primary drill (matches prior Watch copy).
        switch focus {
        case .tempoRush:
            return ImproverDrill(
                title: "Pause at top",
                instruction: "three slow rehearsals, 1-second pause at the top, then swing"
            )
        case .tempoSlow:
            return ImproverDrill(
                title: "Count through",
                instruction: "count 1-2 back, 3 through — no extra pause at the top"
            )
        case .pathOutToIn:
            return wrist == .trailRight
                ? ImproverDrill(
                    title: "Trail armpit",
                    instruction: "half-swings, headcover under the trail armpit"
                )
                : ImproverDrill(
                    title: "Lead armpit",
                    instruction: "half-swings, headcover under the lead armpit"
                )
        case .pathInToOut:
            return wrist == .trailRight
                ? ImproverDrill(
                    title: "Quiet trail hand",
                    instruction: "9-to-3 swings, soft trail hand, hold finish 2 beats"
                )
                : ImproverDrill(
                    title: "Soft lead wrist",
                    instruction: "9-to-3 swings, soft lead wrist, hold finish 2 beats"
                )
        case .pathOnPlane:
            return ImproverDrill(
                title: "¾ tempo",
                instruction: "five identical ¾ swings; chase tempo 3:1"
            )
        case .unknown:
            return ImproverDrill(
                title: "Rehearse",
                instruction: "three rehearsal swings, then one committed motion"
            )
        }
    }

    private static func alternateDrill(focus: ImproverFocus, wrist: WatchWristMount) -> ImproverDrill {
        let arm = wrist == .trailRight ? "trail" : "lead"
        switch focus {
        case .tempoRush:
            return ImproverDrill(
                title: "Feet together",
                instruction: "feet-together swings; if balance fails, you are still yanking the club"
            )
        case .tempoSlow:
            return ImproverDrill(
                title: "Pump then go",
                instruction: "two soft pumps to the top, then one continuous move through"
            )
        case .pathOutToIn:
            return ImproverDrill(
                title: "Gate start",
                instruction: "two tees as a gate just inside the ball — start the \(arm) hand through the gate"
            )
        case .pathInToOut:
            return ImproverDrill(
                title: "Towel under arm",
                instruction: "towel under the \(arm) armpit through waist-high finish — no early release"
            )
        case .pathOnPlane:
            return ImproverDrill(
                title: "Eyes closed",
                instruction: "three eyes-closed ½ swings matching the last good \(arm) wrist feel"
            )
        case .unknown:
            return ImproverDrill(
                title: "Still start",
                instruction: "hold still three full breaths, then one smooth rehearsal"
            )
        }
    }

    private static func missAdvice(
        path: SwingPathClass,
        severity: PathMissSeverity,
        wrist: WatchWristMount
    ) -> String {
        let feel = wrist.coachingName
        switch path {
        case .outToIn:
            switch severity {
            case .mild:
                return "Mild out-to-in on the \(feel) — watch for a soft pull or fade start; start the downswing more from inside."
            case .moderate:
                return "Moderate out-to-in — classic pull / pull-slice pattern if the face doesn't catch up. Trail elbow stays closer to the ribs."
            case .severe:
                return "Severe out-to-in arc — expect left misses (RH) or big cuts. Shorten the backswing and rehearse an inside drop before speed."
            case .none, .unknown:
                return "Out-to-in wrist path — bias toward leftward starts; prioritize an inside move before you add speed."
            }
        case .inToOut:
            switch severity {
            case .mild:
                return "Mild in-to-out on the \(feel) — can push or draw; quiet the hands so the face doesn't stay open."
            case .moderate:
                return "Moderate in-to-out — push / push-hook risk. Soften the \(feel) through impact; don't flip to save it."
            case .severe:
                return "Severe in-to-out — blocks and hooks show up here. Slow the transition and feel the \(feel) exit left of the target line (RH)."
            case .none, .unknown:
                return "In-to-out wrist path — bias toward rightward starts; quiet hands, hold the finish."
            }
        case .onPlane:
            return "On-plane \(feel) path — miss pattern should be small. If the ball still curves, it's face or aim, not this wrist arc."
        case .unknown:
            return "No path miss to call yet — get one clean timed swing with a still address."
        }
    }

    private static func postSwingText(
        focus: ImproverFocus,
        path: SwingPathClass,
        tempoRatio: Double?,
        tempoCV: Double?,
        severity: PathMissSeverity
    ) -> String {
        let tempoBit: String
        if let tempoRatio, tempoRatio.isFinite {
            tempoBit = String(format: "%.1f:1", tempoRatio)
        } else {
            tempoBit = "no tempo"
        }
        let pathBit = SwingPathGuidance.coachingLabel(path)
        let focusBit: String
        switch focus {
        case .tempoRush: focusBit = "next: pause at top"
        case .tempoSlow: focusBit = "next: start down sooner"
        case .pathOutToIn: focusBit = "next: inside start"
        case .pathInToOut: focusBit = "next: quiet hands"
        case .pathOnPlane: focusBit = "next: repeat feel"
        case .unknown: focusBit = "next: still address"
        }
        let sevBit = severity == .none || severity == .unknown ? "" : " · \(severity.rawValue)"
        if let tempoCV {
            return "\(pathBit)\(sevBit) · \(tempoBit) · \(focusBit) · \(consistencyCaption(tempoCV: tempoCV))"
        }
        return "\(pathBit)\(sevBit) · \(tempoBit) · \(focusBit)"
    }
}

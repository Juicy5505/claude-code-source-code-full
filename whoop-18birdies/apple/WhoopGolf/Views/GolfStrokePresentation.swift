import Foundation
import CoreLocation

/// Phone/Watch UI adapter over Shared stroke-score models.
/// Does not invent path math — calls `SwingPathGuidance` / `GolfImprover`.
enum GolfStrokePresentation {
    /// One row for the live/post-round stroke board.
    struct Row: Identifiable {
        let id: UUID
        let sequence: Int
        let hole: Int?
        let capturedAt: Date
        let score: SwingStrokeScore
        let shotYards: Double?
        let yardsUncertainty: Double?
        let yardsStatus: SwingShotDistanceStatus?
        let peakG: Double
        let heartRateBPM: Int?
        let latitude: Double?
        let longitude: Double?
        let provenanceLabel: String
        let clubLabel: String?
        let ballStartLabel: String?
        let ballStartDetail: String?
        let attackFeelLabel: String?

        var coordinate: CLLocationCoordinate2D? {
            guard let latitude, let longitude,
                  latitude.isFinite, longitude.isFinite else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var yardsLine: String {
            guard let shotYards, shotYards.isFinite else {
                if yardsStatus == nil {
                    return "Yards pending · waiting for next swing"
                }
                return "No swing-to-swing yards"
            }
            if let yardsUncertainty, yardsUncertainty.isFinite {
                return String(format: "%.0f yd ±%.0f · GPS displacement", shotYards, yardsUncertainty)
            }
            return String(format: "%.0f yd · GPS displacement", shotYards)
        }

        var scoreLine: String {
            GolfImprover.phoneStrokeSummary(score)
        }
    }

    /// Session-level patterns for Trends (miss / tempo / consistency).
    struct PatternSummary: Hashable {
        let missHeadline: String
        let missDetail: String
        let tempoHeadline: String
        let tempoDetail: String
        let consistencyHeadline: String
        let consistencyDetail: String
        let sampleCount: Int
    }

    static func row(
        for swing: GolfSwingMetrics,
        sequence: Int,
        hole: Int? = nil,
        wrist: WatchWristMount = .golferDefault
    ) -> Row {
        let yaw = inferredDownswingYawDegrees(from: swing)
        // Stored path_yaw_deg is already mount-corrected — classify with leadLeft
        // (pathSign +1) so trail-right polarity is not flipped twice.
        let path = swing.resolvedPathClass != .unknown
            ? swing.resolvedPathClass
            : (yaw.map {
                SwingPathGuidance.classify(downswingYawDegrees: $0, wrist: .leadLeft).path
            } ?? .unknown)
        let live = GolfImprover.strokeScore(
            path: path,
            correctedYawDegrees: yaw,
            tempoRatio: swing.tempoRatio,
            wrist: wrist,
            id: swing.id
        )
        let score: SwingStrokeScore
        if let persisted = swing.pathScore {
            let explanation = swing.pathExplanation ?? live.explanation
            let tip: ImproverTip
            if let improverTip = swing.improverTip, improverTip != live.tip.postSwing {
                tip = ImproverTip(
                    focus: live.tip.focus,
                    cue: live.tip.cue,
                    drill: live.tip.drill,
                    alternateDrill: live.tip.alternateDrill,
                    wristFeel: live.tip.wristFeel,
                    missAdvice: live.tip.missAdvice,
                    postSwing: improverTip
                )
            } else {
                tip = live.tip
            }
            let label = live.pathLabel
            score = SwingStrokeScore(
                id: live.id,
                path: live.path,
                correctedYawDegrees: yaw ?? live.correctedYawDegrees,
                pathScore: persisted,
                severity: live.severity,
                pathLabel: label,
                explanation: explanation,
                scoreHeadline: "\(label) · \(persisted)",
                tempoRatio: live.tempoRatio,
                tip: tip
            )
        } else {
            score = live
        }
        let interval = swing.shotInterval
        let latitude = swing.location?.hasValidCoordinate == true ? swing.location?.latitude : nil
        let longitude = swing.location?.hasValidCoordinate == true ? swing.location?.longitude : nil
        let dossier = ComprehensiveShotIntelligence.dossier(
            for: swing,
            sequence: sequence,
            wrist: wrist
        )
        return Row(
            id: swing.id,
            sequence: sequence,
            hole: hole,
            capturedAt: swing.capturedAt,
            score: score,
            shotYards: swing.shotYards ?? interval?.straightLineDisplacementYards,
            yardsUncertainty: interval?.distanceUncertaintyYards,
            yardsStatus: interval?.distanceStatus,
            peakG: swing.peakG,
            heartRateBPM: swing.heartRateBPM,
            latitude: latitude,
            longitude: longitude,
            provenanceLabel: swing.provenance.source.title,
            clubLabel: dossier.club?.displayName,
            ballStartLabel: dossier.ballStartBias.shortLabel,
            ballStartDetail: swing.ballStartDetail ?? dossier.ballStartDetail,
            attackFeelLabel: dossier.attackFeel.title
        )
    }

    static func rows(
        for round: GolfRound,
        wrist: WatchWristMount = .golferDefault
    ) -> [Row] {
        let ordered = round.swings.sorted { $0.capturedAt < $1.capturedAt }
        return ordered.enumerated().map { index, swing in
            row(for: swing, sequence: index + 1, hole: nil, wrist: wrist)
        }
    }

    static func patternSummary(
        for rounds: [GolfRound],
        wrist: WatchWristMount = .golferDefault
    ) -> PatternSummary {
        let allRows = rounds.flatMap { rows(for: $0, wrist: wrist) }
        let scored = allRows.filter { $0.score.path != .unknown }
        let tempos = allRows.compactMap(\.score.tempoRatio).filter { $0.isFinite && $0 > 0 }

        let missHeadline: String
        let missDetail: String
        if scored.isEmpty {
            missHeadline = "No path miss pattern yet"
            missDetail = "Need Watch or WHOOP strokes with a readable wrist path (trail-right default)."
        } else {
            let counts = Dictionary(grouping: scored, by: \.score.path).mapValues(\.count)
            let dominant = counts.max(by: { $0.value < $1.value })?.key ?? .unknown
            let total = scored.count
            let share = Int((Double(counts[dominant, default: 0]) / Double(total) * 100).rounded())
            missHeadline = "\(SwingPathGuidance.coachingLabel(dominant)) · \(share)% of \(total)"
            missDetail = missCopy(dominant: dominant, share: share, wrist: wrist)
        }

        let tempoHeadline: String
        let tempoDetail: String
        if tempos.count < 2 {
            tempoHeadline = tempos.first.map { String(format: "Tempo %.1f:1", $0) } ?? "No tempo samples"
            tempoDetail = "Need 2+ timed swings for a session tempo read (Tour reference 3:1)."
        } else {
            let mean = tempos.reduce(0, +) / Double(tempos.count)
            tempoHeadline = String(format: "Mean tempo %.2f:1 · n=%d", mean, tempos.count)
            let delta = mean - GolfImprover.tourTempo
            if abs(delta) <= GolfImprover.tempoSlack {
                tempoDetail = "Close to Tour 3:1 — keep the same takeaway feel."
            } else if delta < 0 {
                tempoDetail = "Quicker than 3:1 on average — bias toward a pause at the top."
            } else {
                tempoDetail = "Slower than 3:1 on average — start the downswing a beat sooner."
            }
        }

        let consistencyHeadline: String
        let consistencyDetail: String
        if tempos.count < 2 {
            consistencyHeadline = "Consistency pending"
            consistencyDetail = GolfImprover.consistencyCaption(tempoCV: nil)
        } else {
            let mean = tempos.reduce(0, +) / Double(tempos.count)
            let variance = tempos.reduce(0) { $0 + pow($1 - mean, 2) } / Double(tempos.count)
            let cv = mean > 0 ? sqrt(variance) / mean : nil
            consistencyHeadline = cv.map { String(format: "Tempo CV %.2f", $0) } ?? "Tempo CV —"
            consistencyDetail = GolfImprover.consistencyCaption(tempoCV: cv)
        }

        return PatternSummary(
            missHeadline: missHeadline,
            missDetail: missDetail,
            tempoHeadline: tempoHeadline,
            tempoDetail: tempoDetail,
            consistencyHeadline: consistencyHeadline,
            consistencyDetail: consistencyDetail,
            sampleCount: allRows.count
        )
    }

    /// Prefer explicit Watch mount-corrected yaw when present.
    /// Does not invent signed path from WHOOP travel magnitude alone.
    private static func inferredDownswingYawDegrees(from swing: GolfSwingMetrics) -> Double? {
        if let yaw = swing.pathYawDegrees, yaw.isFinite {
            return yaw
        }
        _ = swing.wristAnalysis
        return nil
    }

    private static func missCopy(dominant: SwingPathClass, share: Int, wrist: WatchWristMount) -> String {
        let feel = wrist.coachingName
        switch dominant {
        case .outToIn:
            return "Most scored strokes lean out-to-in on the \(feel) (\(share)%). Watch for pull / cut starts; prioritize an inside downswing."
        case .inToOut:
            return "Most scored strokes lean in-to-out on the \(feel) (\(share)%). Watch for push / hook; quiet the hands through impact."
        case .onPlane:
            return "Most scored strokes stayed on-plane (\(share)%). Curve that remains is more face/aim than this wrist arc."
        case .unknown:
            return "Path samples are still thin — keep swinging with a still address on the \(feel)."
        }
    }
}

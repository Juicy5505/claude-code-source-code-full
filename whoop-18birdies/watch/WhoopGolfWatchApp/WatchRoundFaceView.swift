import SwiftUI

/// On-wrist face: path score, improver, yardage, HR, next tip.
///
/// Consumes Shared `SwingPathGuidance` / `GolfImprover` / `WatchLiveFace` v3.
/// Default copy assumes trail-right (`WatchWristMount.golferDefault`).
@MainActor
struct WatchRoundFaceView: View {
    let path: SwingPathClass
    let pathYawDegrees: Double?
    let tempoRatio: Double?
    let tempoFrames: String?
    let liveFace: WatchLiveFace
    let lastWatchYards: Double?
    let swingCount: Int
    let heartRateBPM: Int?
    var averageHeartRateBPM: Int? = nil
    var tempoCV: Double? = nil
    /// Local Settings fallback; phone-published `liveFace.wristMount` wins.
    var wrist: WatchWristMount = WatchWristMount.load()
    /// Phone / durable coaching overlays (optional; local stroke fills gaps).
    var phoneImproverTip: String? = nil
    var phoneImproverDrill: String? = nil

    private var effectiveWrist: WatchWristMount {
        liveFace.wristMount
    }

    private var effectivePath: SwingPathClass {
        if path != .unknown { return path }
        return Self.pathClass(fromLabel: liveFace.lastPathLabel) ?? .unknown
    }

    private var stroke: SwingStrokeScore {
        GolfImprover.strokeScore(
            path: effectivePath,
            correctedYawDegrees: pathYawDegrees,
            tempoRatio: tempoRatio,
            wrist: effectiveWrist,
            tempoCV: tempoCV
        )
    }

    var body: some View {
        TabView {
            pathScreen
            improverScreen
            yardageScreen
            vitalsScreen
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(minHeight: 132)
    }

    private var pathScreen: some View {
        VStack(spacing: 4) {
            Text("PATH")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(displayScoreHeadline)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(effectivePath == .unknown && liveFace.lastPathScore == nil
                    ? Color.secondary
                    : Color.green)
                .multilineTextAlignment(.center)
            if let phoneScore = liveFace.lastPathScore {
                Text("\(phoneScore)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 6) {
                if let club = liveFace.activeClubCode {
                    Text(club)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.25), in: Capsule())
                }
                if let ball = liveFace.lastBallStartLabel {
                    Text(ball)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            Text(stroke.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let tempoRatio {
                Text(tempoLine(tempoRatio))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Text(wristFeelLine)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var displayScoreHeadline: String {
        if let label = liveFace.lastPathLabel, let score = liveFace.lastPathScore {
            return "\(label) · \(score)"
        }
        if let score = liveFace.lastPathScore {
            return "\(stroke.scoreHeadline) · \(score)"
        }
        return stroke.scoreHeadline
    }

    private var improverScreen: some View {
        VStack(spacing: 4) {
            Text("IMPROVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(phoneImproverTip ?? stroke.cue)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(phoneImproverDrill ?? stroke.drillLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(stroke.missAdvice)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(wristFeelLine)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var yardageScreen: some View {
        VStack(spacing: 4) {
            Text("YARDAGE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            if let course = liveFace.courseName, !course.isEmpty {
                Text(course)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let hole = liveFace.holeNumber {
                Text("HOLE \(hole)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            if liveFace.hasHoleMap {
                HStack(spacing: 6) {
                    yardTile("FRONT", liveFace.frontYards)
                    yardTile("MID", liveFace.middleYards)
                    yardTile("BACK", liveFace.backYards)
                }
            } else {
                Text("No hole map · shot yards from Watch GPS")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(lastYardsLine)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(strokeCountLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var vitalsScreen: some View {
        VStack(spacing: 4) {
            Text("HR · NEXT")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(heartRateBPM.map { "\($0)" } ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(heartRateBPM == nil ? Color.secondary : Color.red)
            Text("bpm")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let avg = averageHeartRateBPM {
                Text("avg \(avg)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(stroke.tip.postSwing)
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.green)
                .lineLimit(4)
            Text(wristFeelLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    /// Trail-right is the product default; label the feel so polarity is obvious on-wrist.
    private var wristFeelLine: String {
        switch effectiveWrist {
        case .trailRight:
            return "Feel · trail-right wrist"
        case .leadLeft:
            return "Feel · lead-left wrist"
        }
    }

    private func tempoLine(_ ratio: Double) -> String {
        let frames = tempoFrames.map { " · \($0)" } ?? ""
        return String(format: "%.1f:1%@", ratio, frames)
    }

    private var lastYardsLine: String {
        let yards = liveFace.lastShotYards.map(Double.init) ?? lastWatchYards
        return yards.map { String(format: "LAST %.0f yd", $0) } ?? "LAST — yd"
    }

    private var strokeCountLine: String {
        let count = liveFace.strokeCount ?? swingCount
        return count == 1 ? "1 stroke" : "\(count) strokes"
    }

    private func yardTile(_ caption: String, _ yards: Int?) -> some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(yards.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Maps phone-published path labels (`on-plane`, …) back to a class for local coaching.
    private static func pathClass(fromLabel label: String?) -> SwingPathClass? {
        guard let raw = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        switch raw {
        case "on-plane", "onplane", "on plane": return .onPlane
        case "out-to-in", "outtoin", "out to in": return .outToIn
        case "in-to-out", "intoout", "in to out": return .inToOut
        case "no path yet", "unknown": return .unknown
        default:
            return SwingPathClass(rawValue: raw)
        }
    }
}

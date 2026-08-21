import SwiftUI

/// On-wrist face: path score, improver, yardage, HR, next tip.
///
/// Consumes Shared `SwingPathGuidance` / `GolfImprover` / `WatchLiveFace`.
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
    var tempoCV: Double? = nil
    var wrist: WatchWristMount = WatchWristMount.load()

    private var stroke: SwingStrokeScore {
        GolfImprover.strokeScore(
            path: path,
            correctedYawDegrees: pathYawDegrees,
            tempoRatio: tempoRatio,
            wrist: wrist,
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
            Text(stroke.scoreHeadline)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(path == .unknown ? Color.secondary : Color.green)
                .multilineTextAlignment(.center)
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
        }
        .padding(.horizontal, 4)
    }

    private var improverScreen: some View {
        VStack(spacing: 4) {
            Text("IMPROVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(stroke.cue)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(stroke.drillLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(stroke.missAdvice)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 4)
    }

    private var yardageScreen: some View {
        VStack(spacing: 4) {
            Text("YARDAGE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
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
            Text(stroke.tip.postSwing)
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.green)
                .lineLimit(4)
            Text("Feel: \(wrist.coachingName)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func tempoLine(_ ratio: Double) -> String {
        let frames = tempoFrames.map { " · \($0)" } ?? ""
        return String(format: "%.1f:1%@", ratio, frames)
    }

    private var lastYardsLine: String {
        let yards = liveFace.lastShotYards.map(Double.init) ?? lastWatchYards
        return yards.map { String(format: "LAST %.0f yd", $0) } ?? "LAST — yd"
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
}

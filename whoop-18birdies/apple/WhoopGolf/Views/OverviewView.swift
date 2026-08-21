import SwiftUI
import UIKit

/// D19 glass of “you + the app”: readiness, last-round stroke stats,
/// Watch + WHOOP fusion pills, vault overview affordance (no secrets).
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                GolfBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        readinessHero
                        lastRoundCard
                        fusionBoard
                        consistencyCard
                        vaultLinkCard
                        Button {
                            model.selectedTab = .round
                        } label: {
                            Label("Open Round", systemImage: "flag.checkered")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.golfLime)
                        .foregroundStyle(Color.golfInk)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(18)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHOOP GOLF · D19")
                .font(.caption.weight(.black))
                .tracking(1.6)
                .foregroundStyle(Color.golfLime)
            Text("Health + round,\none snapshot.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(board.modeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.golfMist)
            Text(DualWearableRequirement.title(for: model.dualWearableAdmission))
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    model.canStartDualWearableRound ? Color.golfLime : Color.golfSand
                )
            Text(DualWearableRequirement.detail(for: model.dualWearableAdmission))
                .font(.caption2)
                .foregroundStyle(Color.golfMist)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var readinessHero: some View {
        if let snapshot = model.readiness {
            GolfCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("GOLF READINESS")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.golfMist)
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.score.map { String(Int($0.rounded())) } ?? "—")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text("/ 100")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.golfMist)
                        Spacer()
                        SourceBadge(provenance: snapshot.provenance)
                    }
                    Text(snapshot.verdict)
                        .font(.title3.bold())
                    Text(snapshot.advice)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(board.readinessBeforeRoundDetail)
                        .font(.caption)
                        .foregroundStyle(Color.golfMist)
                    HStack(spacing: 8) {
                        MetricTile(
                            label: "Recovery",
                            value: snapshot.recoveryPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                            detail: "Cached WHOOP",
                            symbol: "heart.fill"
                        )
                        MetricTile(
                            label: "Day strain",
                            value: snapshot.dayStrain.map { String(format: "%.1f", $0) } ?? "—",
                            detail: "Not live IMU",
                            symbol: "bolt.fill"
                        )
                    }
                }
            }
        } else {
            GolfCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Pre-round readiness", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.headline)
                    Text(board.readinessBeforeRoundDetail)
                        .font(.subheadline)
                        .foregroundStyle(Color.golfMist)
                    Button("Pull Today readiness") {
                        model.selectedTab = .today
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.golfLime)
                }
            }
        }
    }

    private var lastRoundCard: some View {
        let stats = RoundOverviewStats.make(
            from: lastFinishedRound,
            wrist: model.watchWristMount
        )
        return GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("LAST ROUND")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                if let round = lastFinishedRound {
                    Text(round.courseName)
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricTile(
                            label: "Strokes",
                            value: "\(stats.strokeCount)",
                            detail: "Verified journal",
                            symbol: "figure.golf"
                        )
                        MetricTile(
                            label: "Avg path",
                            value: stats.averagePathScore.map { "\($0)" } ?? "—",
                            detail: "Body-relative",
                            symbol: "arrow.triangle.branch"
                        )
                        MetricTile(
                            label: "Shot yards",
                            value: stats.totalShotYards.map { String(format: "%.0f" , $0) } ?? "—",
                            detail: "Swing-to-swing GPS",
                            symbol: "ruler"
                        )
                        MetricTile(
                            label: "Longest",
                            value: stats.longestShotYards.map { String(format: "%.0f yd", $0) } ?? "—",
                            detail: "Measured segment",
                            symbol: "arrow.up.right"
                        )
                    }
                } else {
                    Text("Finish a tracked round to populate stroke count, avg path score, and swing-to-swing yards here.")
                        .font(.subheadline)
                        .foregroundStyle(Color.golfMist)
                }
            }
        }
    }

    private var fusionBoard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Wearable fusion", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.headline)
                Text(board.roundFusion.liveScoringCaption)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                Text(board.roundFusion.delayedMergeCaption)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(board.lines) { line in
                            ConnectionPill(
                                title: "\(line.title.split(separator: "·").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? line.title) · \(line.status)",
                                systemImage: pillSymbol(for: line.id),
                                active: line.available
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(board.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(line.title)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(line.status)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(line.available ? Color.golfLime : Color.golfSand)
                            }
                            Text(line.detail)
                                .font(.caption2)
                                .foregroundStyle(Color.golfMist)
                        }
                    }
                }

                Text("HR owner · \(board.heartRateOwner.title)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.golfLime)
                Text(board.heartRateDetail)
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }
        }
    }

    private var consistencyCard: some View {
        let pattern = GolfStrokePresentation.patternSummary(
            for: finishedRounds.prefix(5).map { $0 },
            wrist: model.watchWristMount
        )
        return GolfCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONSISTENCY STREAK")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                Text(pattern.consistencyHeadline)
                    .font(.title3.bold())
                Text(pattern.consistencyDetail)
                    .font(.subheadline)
                    .foregroundStyle(Color.golfMist)
                Text(pattern.missHeadline)
                    .font(.caption.weight(.semibold))
                Text("Across \(min(finishedRounds.count, 5)) recent finished round(s).")
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }
        }
    }

    private var vaultLinkCard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Vault App Overview", systemImage: "books.vertical")
                    .font(.headline)
                Text("Sanitized health + round snapshot for Obsidian / graphify. No tokens, UDIDs, or raw HR streams.")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                Text(VaultOverviewExport.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.golfSand)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = VaultOverviewExport.relativePath
                    model.notice = "Copied vault overview path."
                } label: {
                    Label("Copy vault path", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.golfLime)
            }
        }
    }

    private var board: DualWearableFusion.ContributionBoard {
        model.wearableContributionBoard
    }

    private var finishedRounds: [GolfRound] {
        model.rounds.filter(\.isFinished).sorted { $0.startedAt > $1.startedAt }
    }

    private var lastFinishedRound: GolfRound? {
        finishedRounds.first
    }

    private func pillSymbol(for id: String) -> String {
        switch id {
        case "watch-live": return "applewatch"
        case "whoop-delayed", "journal-merge": return "wave.3.right"
        case "whoop-physio": return "heart.text.square"
        case "hr": return "heart.fill"
        case "phone-gps": return "location.fill"
        default: return "circle"
        }
    }
}

enum RoundOverviewStats {
    struct Snapshot {
        let strokeCount: Int
        let averagePathScore: Int?
        let totalShotYards: Double?
        let longestShotYards: Double?
    }

    static func make(from round: GolfRound?, wrist: WatchWristMount) -> Snapshot {
        guard let round else {
            return Snapshot(
                strokeCount: 0,
                averagePathScore: nil,
                totalShotYards: nil,
                longestShotYards: nil
            )
        }
        let rows = GolfStrokePresentation.rows(for: round, wrist: wrist)
        let scores = rows.compactMap(\.score.pathScore)
        let yards = rows.compactMap(\.shotYards).filter { $0.isFinite && $0 >= 0 }
        let avg: Int?
        if scores.isEmpty {
            avg = nil
        } else {
            avg = Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        }
        return Snapshot(
            strokeCount: rows.count,
            averagePathScore: avg,
            totalShotYards: yards.isEmpty ? nil : yards.reduce(0, +),
            longestShotYards: yards.max()
        )
    }
}

enum VaultOverviewExport {
    static let relativePath =
        "10 Projects/Whoop Golf Companion/App Overview.md"
}

import SwiftUI

/// Today / Round companion panel: Watch reachability, wrist mount, delayed WHOOP import.
struct WatchCompanionStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("WATCH + WHOOP", systemImage: "applewatch")
                        .font(.caption.weight(.black))
                        .tracking(1)
                        .foregroundStyle(Color.golfMist)
                    Spacer()
                    Text(model.watchWristMount.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.golfLime)
                }

                Text(watchStatusTitle)
                    .font(.subheadline.weight(.bold))
                Text(watchStatusDetail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)

                HStack(spacing: 8) {
                    statusChip(
                        "Watch",
                        WatchSessionReceiver.shared.isReachable ? "Live link" : "Not reachable",
                        ok: WatchSessionReceiver.shared.isReachable
                    )
                    statusChip(
                        "App",
                        WatchSessionReceiver.shared.isWatchAppInstalled ? "Installed" : "Pending OS",
                        ok: WatchSessionReceiver.shared.isWatchAppInstalled
                    )
                    statusChip(
                        "Sessions",
                        model.pendingWatchSessions.isEmpty
                            ? "Clear"
                            : "\(model.pendingWatchSessions.count) pending",
                        ok: model.pendingWatchSessions.isEmpty
                    )
                }

                Divider().overlay(.white.opacity(0.08))

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(Color.golfSand)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delayed WHOOP import")
                            .font(.caption.weight(.semibold))
                        Text(whoopImportLine)
                            .font(.caption2)
                            .foregroundStyle(Color.golfMist)
                    }
                }

                if let last = model.lastWatchSession {
                    Text("Last Watch import · \(last.mode.rawValue) · \(last.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Color.golfMist)
                }
            }
        }
    }

    private var watchStatusTitle: String {
        if WatchSessionReceiver.shared.isReachable {
            return "Watch companion linked"
        }
        if WatchSessionReceiver.shared.isWatchAppInstalled {
            return "Watch app present · link idle"
        }
        if WatchSessionReceiver.shared.isPaired {
            return "Watch paired · install gated on OS update"
        }
        return "No Apple Watch paired yet"
    }

    private var watchStatusDetail: String {
        "Live path, improver, yards, and HR run on-wrist (\(model.watchWristMount.coachingName)). Phone owns readiness, stroke board, delayed WHOOP fuse, and trends."
    }

    private var whoopImportLine: String {
        let review = model.pendingWhoopMotionReviewBatches.count
        let pending = model.pendingWhoopMotionBatches.count
        if review > 0 {
            return "\(review) batch(es) ready for review in Settings · Check for WHOOP swings."
        }
        if pending > 0 {
            return "\(pending) historical batch(es) waiting · not live Arming."
        }
        return "No delayed WHOOP motion queued. Live IMU is not the WHOOP 5 golf path."
    }

    private func statusChip(_ title: String, _ value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.golfMist)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ok ? Color.golfLime : Color.golfSand)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Compact session summary for Round + Trends.
struct GolfSessionSummaryCard: View {
    let round: GolfRound
    let wrist: WatchWristMount

    var body: some View {
        let rows = GolfStrokePresentation.rows(for: round, wrist: wrist)
        let pattern = GolfStrokePresentation.patternSummary(for: [round], wrist: wrist)
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("SESSION SUMMARY")
                    .font(.caption.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                Text(round.courseName)
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(
                        label: "Strokes scored",
                        value: "\(rows.count)",
                        detail: "Watch / WHOOP / hybrid",
                        symbol: "figure.golf"
                    )
                    MetricTile(
                        label: "Measured yards",
                        value: "\(rows.filter { $0.shotYards != nil }.count)",
                        detail: "Swing-to-swing GPS",
                        symbol: "ruler"
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    summaryLine("Miss", pattern.missHeadline, pattern.missDetail)
                    summaryLine("Tempo", pattern.tempoHeadline, pattern.tempoDetail)
                    summaryLine("Consistency", pattern.consistencyHeadline, pattern.consistencyDetail)
                }
            }
        }
    }

    private func summaryLine(_ label: String, _ headline: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.golfMist)
            Text(headline)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.golfMist)
        }
    }
}

/// Trends strip: miss pattern, tempo, consistency across finished rounds.
struct GolfPatternTrendsCard: View {
    let rounds: [GolfRound]
    let wrist: WatchWristMount

    var body: some View {
        let pattern = GolfStrokePresentation.patternSummary(for: rounds, wrist: wrist)
        GolfCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("STROKE PATTERNS", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Text("\(pattern.sampleCount) stroke sample\(pattern.sampleCount == 1 ? "" : "s") · wrist \(wrist.coachingName)")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)

                patternBlock(
                    title: "Miss pattern",
                    headline: pattern.missHeadline,
                    detail: pattern.missDetail,
                    symbol: "arrow.triangle.branch"
                )
                patternBlock(
                    title: "Tempo",
                    headline: pattern.tempoHeadline,
                    detail: pattern.tempoDetail,
                    symbol: "metronome.fill"
                )
                patternBlock(
                    title: "Consistency",
                    headline: pattern.consistencyHeadline,
                    detail: pattern.consistencyDetail,
                    symbol: "equal.circle.fill"
                )
            }
        }
    }

    private func patternBlock(title: String, headline: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.golfLime)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.golfMist)
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }
        }
    }
}

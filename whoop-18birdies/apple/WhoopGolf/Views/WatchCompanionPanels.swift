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
                        label: "Avg path score",
                        value: averagePathScore(from: rows),
                        detail: "Body-relative",
                        symbol: "arrow.triangle.branch"
                    )
                    MetricTile(
                        label: "Measured yards",
                        value: "\(rows.filter { $0.shotYards != nil }.count)",
                        detail: "Swing-to-swing GPS",
                        symbol: "ruler"
                    )
                    MetricTile(
                        label: "Longest shot",
                        value: longestYards(from: rows),
                        detail: "GPS displacement",
                        symbol: "arrow.up.right"
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

    private func averagePathScore(from rows: [GolfStrokePresentation.Row]) -> String {
        let scores = rows.compactMap(\.score.pathScore)
        guard !scores.isEmpty else { return "—" }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        return "\(Int(avg.rounded()))"
    }

    private func longestYards(from rows: [GolfStrokePresentation.Row]) -> String {
        guard let yards = rows.compactMap(\.shotYards).filter({ $0.isFinite }).max() else {
            return "—"
        }
        return String(format: "%.0f yd", yards)
    }
}

/// Trends strip: miss pattern, tempo sparkline, consistency across finished rounds.
struct GolfPatternTrendsCard: View {
    let rounds: [GolfRound]
    let wrist: WatchWristMount

    var body: some View {
        let pattern = GolfStrokePresentation.patternSummary(for: rounds, wrist: wrist)
        let tempos = rounds
            .flatMap { GolfStrokePresentation.rows(for: $0, wrist: wrist) }
            .compactMap(\.score.tempoRatio)
            .filter { $0.isFinite && $0 > 0 }
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
                if tempos.count >= 2 {
                    TempoSparklineView(values: Array(tempos.suffix(24)))
                        .frame(height: 44)
                        .accessibilityLabel("Tempo sparkline")
                        .accessibilityValue("\(tempos.count) samples")
                }
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

/// Simple tempo sparkline (Tour 3:1 reference as a faint midline).
struct TempoSparklineView: View {
    let values: [Double]
    private let reference = GolfImprover.tourTempo

    var body: some View {
        GeometryReader { geo in
            let minY = min(values.min() ?? 0, reference - 0.5)
            let maxY = max(values.max() ?? reference, reference + 0.5)
            let span = max(maxY - minY, 0.1)
            ZStack {
                Path { path in
                    let y = geo.size.height * (1 - CGFloat((reference - minY) / span))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.golfMist.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                        let y = geo.size.height * (1 - CGFloat((value - minY) / span))
                        let point = CGPoint(x: x, y: y)
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(Color.golfLime, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .padding(.vertical, 4)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Live dual-wearable tracking board: club, path, ball-start, attack, fusion.
struct ComprehensiveTrackingBoard: View {
    let round: GolfRound
    let wrist: WatchWristMount

    var body: some View {
        let dossiers = ComprehensiveShotIntelligence.dossiers(for: round, wrist: wrist)
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("COMPREHENSIVE TRACKING")
                    .font(.caption.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                Text("Watch path + WHOOP enrich + club + ball-start tendency + GPS yards")
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)

                if dossiers.isEmpty {
                    Text("Swing once with Watch live. WHOOP delayed enrich merges without double-counting. Tag club before each shot.")
                        .font(.subheadline)
                        .foregroundStyle(Color.golfMist)
                } else {
                    ForEach(dossiers.suffix(6).reversed()) { shot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("#\(shot.sequence)")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(Color.golfLime)
                                if let club = shot.club {
                                    Text(club.shortCode)
                                        .font(.caption2.weight(.bold))
                                }
                                Text(shot.pathClass == .unknown
                                      ? "path —"
                                      : SwingPathGuidance.coachingLabel(shot.pathClass))
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(shot.ballStartBias.shortLabel)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(Color.golfSand)
                            }
                            Text(shot.pathExplanation)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.88))
                            Text(shot.ballStartDetail)
                                .font(.caption2)
                                .foregroundStyle(Color.golfMist)
                            HStack(spacing: 8) {
                                Text(shot.attackFeel.title)
                                if let yards = shot.shotYards {
                                    Text(String(format: "%.0f yd", yards))
                                }
                                if let score = shot.pathScore {
                                    Text("score \(score)")
                                }
                                Text(shot.watchLive && shot.whoopEnriched ? "Hybrid" : (shot.watchLive ? "Watch" : "WHOOP"))
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.golfLime.opacity(0.9))
                        }
                        if shot.id != dossiers.suffix(6).reversed().last?.id {
                            Divider().overlay(.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }
}

/// Post-round sheet: avg path score, longest swing-to-swing yards, source mix.
struct PostRoundPathSummaryCard: View {
    let round: GolfRound
    let wrist: WatchWristMount

    var body: some View {
        let stats = RoundOverviewStats.make(from: round, wrist: wrist)
        let pattern = GolfStrokePresentation.patternSummary(for: [round], wrist: wrist)
        let sources = Set(round.swings.map(\.provenance.source.title)).sorted()
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("PATH + YARDS")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                Text("Post-round stroke sheet")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(
                        label: "Avg path score",
                        value: stats.averagePathScore.map(String.init) ?? "—",
                        detail: pattern.missHeadline,
                        symbol: "arrow.triangle.branch"
                    )
                    MetricTile(
                        label: "Longest shot",
                        value: stats.longestShotYards.map { String(format: "%.0f yd", $0) } ?? "—",
                        detail: "Phone GPS segments",
                        symbol: "ruler"
                    )
                    MetricTile(
                        label: "Total yards",
                        value: stats.totalShotYards.map { String(format: "%.0f", $0) } ?? "—",
                        detail: "Sum of measured shots",
                        symbol: "sum"
                    )
                    MetricTile(
                        label: "Sources",
                        value: sources.isEmpty ? "—" : "\(sources.count)",
                        detail: sources.joined(separator: " · "),
                        symbol: "sensor.tag.radiowaves.forward"
                    )
                }
                Text(pattern.tempoHeadline)
                    .font(.caption.weight(.semibold))
                Text(pattern.consistencyDetail)
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }
        }
    }
}

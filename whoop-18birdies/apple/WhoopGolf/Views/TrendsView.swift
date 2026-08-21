import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                GolfBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        GolfPatternTrendsCard(
                            rounds: finishedRounds,
                            wrist: model.watchWristMount
                        )
                        roundTotals
                        readinessCorrelationCard
                        recentRoundsCard
                    }
                    .padding(18)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("EVIDENCE, NOT VIBES")
                .font(.caption.weight(.black))
                .tracking(1.6)
                .foregroundStyle(Color.golfLime)
            Text("Your golf pattern,\nwith sample size attached.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
        .accessibilityElement(children: .combine)
    }

    private var roundTotals: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            MetricTile(
                label: "Finished rounds",
                value: "\(finishedRounds.count)",
                detail: "Drafts excluded",
                symbol: "flag.checkered"
            )
            MetricTile(
                label: "Accepted observations",
                value: "\(finishedRounds.reduce(0) { $0 + $1.swings.count })",
                detail: "WHOOP, Watch, or manual provenance",
                symbol: "gyroscope"
            )
        }
    }

    private var readinessCorrelationCard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Readiness → score", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                if scoreCompleteRounds.count < 3 {
                    Text("Correlation needs at least 3 finished rounds with complete scorecards and matching same-local-day physiology. This iPhone currently has \(scoreCompleteRounds.count) score-complete round(s).")
                        .font(.subheadline)
                        .foregroundStyle(Color.golfMist)
                } else {
                    Text("Complete scorecards are queued to the private bridge. Correlation appears only after the Mac has acknowledged enough same-local-day round and physiology pairs.")
                        .font(.subheadline)
                        .foregroundStyle(Color.golfMist)
                }
                ProgressView(value: min(Double(scoreCompleteRounds.count) / 8, 1))
                    .tint(.golfLime)
                    .accessibilityLabel("Score-complete round progress")
                    .accessibilityValue("\(min(scoreCompleteRounds.count, 8)) of 8")
                Text("\(min(scoreCompleteRounds.count, 8)) / 8 score-complete local rounds · \(bridgeProgressLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.golfMist)
            }
        }
    }

    private var recentRoundsCard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT FINISHED ROUNDS")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)

                if recentRounds.isEmpty {
                    PostRoundEmptyState(
                        symbol: "flag.checkered",
                        title: "No finished rounds yet",
                        detail: "Finish a tracked round to create an honest scorecard and post-round timeline. Drafts never appear here."
                    )
                } else {
                    ForEach(Array(recentRounds.enumerated()), id: \.element.id) { index, round in
                        NavigationLink {
                            PostRoundDetailView(round: round)
                        } label: {
                            PostRoundHistoryRow(round: round)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the hole-by-hole post-round review")

                        if index < recentRounds.count - 1 {
                            Divider().overlay(.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private var finishedRounds: [GolfRound] {
        model.rounds
            .filter(\.isFinished)
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var recentRounds: [GolfRound] {
        Array(finishedRounds.prefix(6))
    }

    private var scoreCompleteRounds: [GolfRound] {
        finishedRounds.filter(\.isScoreComplete)
    }

    private var bridgeProgressLabel: String {
        switch model.bridgeSyncState {
        case .synced: "bridge acknowledged"
        case .queued(let count, _): "\(count) queued"
        case .syncing: "syncing"
        case .unconfigured: "bridge not configured"
        case .failed: "bridge needs attention"
        case .idle: "ready to sync"
        }
    }
}

private struct PostRoundHistoryRow: View {
    let round: GolfRound

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.golfLime.opacity(0.12))
                Image(systemName: "flag.checkered")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.golfLime)
                    .accessibilityHidden(true)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(round.courseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(PostRoundFormat.roundDate(round))
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                Text("\(round.holeCount.rawValue) holes · \(round.swings.count) swing observation\(round.swings.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(PostRoundFormat.scoreLabel(round))
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("\(round.scoredHoleCount)/\(round.holeCount.rawValue) scored")
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.golfMist)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(round.courseName), \(PostRoundFormat.roundDate(round)), "
                + "\(round.holeCount.rawValue) holes, score \(PostRoundFormat.accessibleScore(round)), "
                + "\(round.swings.count) swing observations"
        )
    }
}

private struct PostRoundDetailView: View {
    @EnvironmentObject private var model: AppModel
    let round: GolfRound

    private var reviewedRound: GolfRound {
        model.rounds.first(where: { $0.id == round.id }) ?? round
    }

    private var presentation: PostRoundPresentation {
        PostRoundPresentation(round: reviewedRound)
    }

    var body: some View {
        ZStack {
            GolfBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    sourceStatus
                    roundSummary
                    scorecard
                    unassignedSwings
                    PostRoundFirstLateCard(analysis: presentation.firstLateAnalysis)
                    measurementBoundary
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Round review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("FINAL", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(Color.golfLime)
                Spacer()
                Text("\(reviewedRound.holeCount.rawValue) HOLES")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfSand)
            }

            Text(reviewedRound.courseName)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label(PostRoundFormat.roundDate(reviewedRound), systemImage: "calendar")
                if let duration = PostRoundFormat.roundDuration(reviewedRound) {
                    Label(duration, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(Color.golfMist)
            .labelStyle(.titleAndIcon)

            Text("Recorded with \(reviewedRound.recordingDevice.displayName).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sourceStatus: some View {
        if presentation.sources.isEmpty {
            GolfCard {
                PostRoundEmptyState(
                    symbol: "sensor.tag.radiowaves.forward",
                    title: "No swing source attached",
                    detail: "The scorecard is preserved, but this round has no WHOOP, Apple Watch, or manual swing observations yet."
                )
            }
        } else {
            GolfCard {
                VStack(alignment: .leading, spacing: 12) {
                    PostRoundSectionHeader(
                        eyebrow: "SENSOR PROVENANCE",
                        title: "What built this review"
                    )

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(presentation.sources, id: \.rawValue) { source in
                            PostRoundSourceChip(source: source)
                        }
                    }

                    if presentation.sources.contains(.whoopMotion) {
                        PostRoundNotice(
                            symbol: "clock.arrow.circlepath",
                            title: "WHOOP 5 is historical",
                            detail: "Motion was reconstructed after the band offloaded it. It was not a live shot feed."
                        )
                    }
                    if presentation.sources.contains(.appleWatch) {
                        PostRoundNotice(
                            symbol: "applewatch",
                            title: "Legacy Watch motion",
                            detail: "Apple Watch observations remain available as an optional legacy source and are never relabeled as WHOOP motion."
                        )
                    }
                }
            }
        }
    }

    private var roundSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostRoundSectionHeader(eyebrow: "ROUND TOTALS", title: "\(reviewedRound.holeCount.rawValue)-hole summary")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                PostRoundStatTile(
                    label: reviewedRound.grossScore == nil ? "Entered strokes" : "Gross score",
                    value: reviewedRound.grossScore.map(String.init)
                        ?? reviewedRound.enteredStrokes.map(String.init)
                        ?? "—",
                    detail: "\(reviewedRound.scoredHoleCount)/\(reviewedRound.holeCount.rawValue) holes scored",
                    symbol: "number"
                )
                PostRoundStatTile(
                    label: "To par",
                    value: PostRoundFormat.scoreLabel(reviewedRound),
                    detail: reviewedRound.scoreToPar == nil ? "Complete score + par required" : "Complete scorecard",
                    symbol: "plus.forwardslash.minus"
                )
                PostRoundStatTile(
                    label: "GPS shot marks",
                    value: "\(reviewedRound.shots.count)",
                    detail: "Manual iPhone origins",
                    symbol: "location.fill"
                )
                PostRoundStatTile(
                    label: "Accepted observations",
                    value: "\(reviewedRound.swings.count)",
                    detail: "\(presentation.measuredIntervalCount) measured GPS interval\(presentation.measuredIntervalCount == 1 ? "" : "s")",
                    symbol: "gyroscope"
                )
            }
        }
    }

    private var scorecard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 14) {
                PostRoundSectionHeader(
                    eyebrow: "SCORECARD",
                    title: "Hole by hole",
                    detail: "Strokes, manual GPS marks, and accepted swing observations remain separate counts."
                )

                ForEach(Array(presentation.holes.enumerated()), id: \.element.id) { index, hole in
                    NavigationLink {
                        PostRoundHoleDetailView(
                            roundID: reviewedRound.id,
                            fallbackRound: reviewedRound,
                            holeNumber: hole.number
                        )
                    } label: {
                        PostRoundScorecardRow(hole: hole)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the swing timeline for hole \(hole.number)")

                    if index < presentation.holes.count - 1 {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unassignedSwings: some View {
        if !presentation.unassignedSwings.isEmpty {
            NavigationLink {
                PostRoundUnassignedSwingsView(
                    roundID: reviewedRound.id,
                    fallbackRound: reviewedRound
                )
            } label: {
                GolfCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.golfSand)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(presentation.unassignedSwings.count) swing\(presentation.unassignedSwings.count == 1 ? "" : "s") need a hole")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                CorrectionNeededBadge(label: "Correction needed")
                            }
                            Text("These accepted observations are explicitly unassigned or fall outside the persisted round timeline. They remain visible instead of being guessed into the scorecard.")
                                .font(.caption)
                                .foregroundStyle(Color.golfMist)
                                .multilineTextAlignment(.leading)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.golfMist)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens unassigned swing observations")
        }
    }

    private var measurementBoundary: some View {
        PostRoundNotice(
            symbol: "scope",
            title: "Measurement boundary",
            detail: "Distances are straight-line GPS displacement between golfer or phone positions at consecutive swings. They are not ball tracking, carry distance, or a calibrated club path."
        )
        .padding(.top, 2)
    }
}

private struct PostRoundScorecardRow: View {
    let hole: PostRoundHoleSummary

    var body: some View {
        HStack(spacing: 12) {
            Text("\(hole.number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.golfInk)
                .frame(width: 38, height: 38)
                .background(Color.golfSand, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Hole \(hole.number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let reviewLabel = hole.reviewLabel {
                        CorrectionNeededBadge(label: reviewLabel)
                    }
                }

                Text("\(hole.swingCount) swing\(hole.swingCount == 1 ? "" : "s") · \(hole.gpsMarkCount) GPS mark\(hole.gpsMarkCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                PostRoundCompactValue(label: "PAR", value: hole.par.map(String.init) ?? "—")
                PostRoundCompactValue(label: "STROKES", value: hole.strokes.map(String.init) ?? "—")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.golfMist)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hole.accessibilitySummary)
    }
}

private struct PostRoundHoleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let roundID: UUID
    let fallbackRound: GolfRound
    let holeNumber: Int

    private var round: GolfRound {
        model.rounds.first(where: { $0.id == roundID }) ?? fallbackRound
    }

    private var presentation: PostRoundPresentation {
        PostRoundPresentation(round: round)
    }

    private var hole: PostRoundHoleSummary {
        let index = max(0, min(round.holeCount.rawValue - 1, holeNumber - 1))
        return presentation.holes[index]
    }

    var body: some View {
        ZStack {
            GolfBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    holeHeader
                    assignmentNotice
                    swingTimeline
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Hole \(hole.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var holeHeader: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Text("\(hole.number)")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Color.golfInk)
                        .frame(width: 64, height: 64)
                        .background(Color.golfSand, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(round.courseName)
                            .font(.headline)
                        Text("\(hole.swingCount) accepted swing observation\(hole.swingCount == 1 ? "" : "s") · \(hole.gpsMarkCount) manual GPS mark\(hole.gpsMarkCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color.golfMist)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], spacing: 8) {
                    PostRoundStatTile(
                        label: "Par",
                        value: hole.par.map(String.init) ?? "—",
                        detail: hole.par == nil ? "Not entered" : "Scorecard",
                        symbol: "flag.fill"
                    )
                    PostRoundStatTile(
                        label: "Strokes",
                        value: hole.strokes.map(String.init) ?? "—",
                        detail: PostRoundFormat.holeScoreDetail(hole),
                        symbol: "number"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var assignmentNotice: some View {
        if !hole.swings.isEmpty {
            PostRoundNotice(
                symbol: "arrow.triangle.branch",
                title: "Persisted hole assignment",
                detail: "Accepted observations use a manual correction when present; otherwise they use the latest selected-hole transition at or before the sensor timestamp. GPS geometry and swing counts are never used to guess a hole."
            )
        } else if hole.gpsMarkCount > 0 {
            PostRoundNotice(
                symbol: "location.fill",
                title: "GPS marks only",
                detail: "This hole has manual phone positions but no WHOOP or Watch swing observations assigned to it."
            )
        }
    }

    private var swingTimeline: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 16) {
                PostRoundSectionHeader(
                    eyebrow: "SWING TIMELINE",
                    title: "Hole \(hole.number) observations",
                    detail: "Intervals end at the next accepted swing observation. A final observation remains pending."
                )

                if hole.swings.isEmpty {
                    PostRoundEmptyState(
                        symbol: "gyroscope",
                        title: "No swings assigned",
                        detail: "The scorecard can still be valid. This hole simply has no sensor swing observation with a defensible timeline assignment."
                    )
                } else {
                    ForEach(Array(hole.swings.enumerated()), id: \.element.id) { index, swing in
                        PostRoundSwingTimelineRow(
                            swingNumber: index + 1,
                            swing: swing,
                            isLastVisibleRow: index == hole.swings.count - 1,
                            isGlobalLastSwing: swing.id == presentation.lastSwingID,
                            roundID: round.id,
                            holeCount: round.holeCount.rawValue,
                            assignment: presentation.assignmentBySwingID[swing.id]
                                ?? SwingHoleAssignment(hole: nil, method: .unavailable, auditedAt: nil),
                            assignedHoleBySwingID: presentation.assignedHoleBySwingID
                        )
                    }
                }
            }
        }
    }
}

private struct PostRoundUnassignedSwingsView: View {
    @EnvironmentObject private var model: AppModel
    let roundID: UUID
    let fallbackRound: GolfRound

    private var round: GolfRound {
        model.rounds.first(where: { $0.id == roundID }) ?? fallbackRound
    }

    private var presentation: PostRoundPresentation {
        PostRoundPresentation(round: round)
    }

    var body: some View {
        ZStack {
            GolfBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    PostRoundNotice(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Correction needed",
                        detail: "These accepted observations were manually unassigned or fall outside the round's timestamp boundaries. Choose a hole below only when you can verify it."
                    )

                    GolfCard {
                        VStack(alignment: .leading, spacing: 16) {
                            PostRoundSectionHeader(
                                eyebrow: "UNASSIGNED",
                                title: "\(presentation.unassignedSwings.count) accepted observation\(presentation.unassignedSwings.count == 1 ? "" : "s")"
                            )

                            ForEach(Array(presentation.unassignedSwings.enumerated()), id: \.element.id) { index, swing in
                                PostRoundSwingTimelineRow(
                                    swingNumber: index + 1,
                                    swing: swing,
                                    isLastVisibleRow: index == presentation.unassignedSwings.count - 1,
                                    isGlobalLastSwing: swing.id == presentation.lastSwingID,
                                    roundID: round.id,
                                    holeCount: round.holeCount.rawValue,
                                    assignment: presentation.assignmentBySwingID[swing.id]
                                        ?? SwingHoleAssignment(hole: nil, method: .unavailable, auditedAt: nil),
                                    assignedHoleBySwingID: presentation.assignedHoleBySwingID
                                )
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Needs a hole")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PostRoundSwingTimelineRow: View {
    @EnvironmentObject private var model: AppModel
    let swingNumber: Int
    let swing: GolfSwingMetrics
    let isLastVisibleRow: Bool
    let isGlobalLastSwing: Bool
    let roundID: UUID
    let holeCount: Int
    let assignment: SwingHoleAssignment
    let assignedHoleBySwingID: [UUID: Int]

    private var assignedHole: Int? { assignment.hole }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(swingNumber)")
                    .font(.caption.weight(.black).monospacedDigit())
                    .foregroundStyle(Color.golfInk)
                    .frame(width: 30, height: 30)
                    .background(Color.golfLime, in: Circle())
                if !isLastVisibleRow {
                    Rectangle()
                        .fill(Color.golfLime.opacity(0.24))
                        .frame(width: 2, height: 210)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Swing \(swingNumber)")
                            .font(.headline)
                        Text(PostRoundFormat.swingTime(swing.capturedAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.golfMist)
                    }
                    Spacer()
                    if assignedHole == nil {
                        CorrectionNeededBadge(label: "Needs hole")
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: assignment.method == .manualCorrection || assignment.method == .manualUnassignment
                        ? "hand.tap.fill"
                        : "clock.arrow.circlepath")
                        .accessibilityHidden(true)
                    Text(assignment.method.displayName)
                        .font(.caption2.weight(.bold))
                    if let hole = assignedHole {
                        Text("· Hole \(hole)")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(assignment.method == .roundTimeline ? Color.golfMist : Color.golfSand)

                swingAssignmentControls

                PostRoundProvenanceBadge(provenance: swing.provenance)

                if let sourceContext = PostRoundFormat.sourceContext(swing.provenance) {
                    Text(sourceContext)
                        .font(.caption2)
                        .foregroundStyle(Color.golfMist)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 8)], spacing: 8) {
                    if swing.peakG.isFinite, swing.peakG > 0 {
                        PostRoundMetricCapsule(
                            label: "Wrist peak",
                            value: swing.peakG.formatted(.number.precision(.fractionLength(1))),
                            unit: "g"
                        )
                    }
                    if let tempo = swing.tempoRatio, tempo.isFinite, tempo > 0 {
                        PostRoundMetricCapsule(
                            label: "Tempo",
                            value: tempo.formatted(.number.precision(.fractionLength(2))),
                            unit: "ratio"
                        )
                    }
                    if let heartRate = swing.heartRateBPM, heartRate > 0 {
                        PostRoundMetricCapsule(
                            label: "Heart rate",
                            value: "\(heartRate)",
                            unit: "bpm"
                        )
                    }
                }

                if let wristAnalysis = swing.wristAnalysis {
                    PostRoundWristRotationCard(analysis: wristAnalysis)
                }

                intervalView

                if !isLastVisibleRow {
                    Divider().overlay(.white.opacity(0.08))
                }
            }
            .padding(.bottom, isLastVisibleRow ? 0 : 4)
        }
        .accessibilityElement(children: .contain)
    }

    private var swingAssignmentControls: some View {
        Menu {
            ForEach(1...holeCount, id: \.self) { hole in
                Button {
                    Task {
                        await model.setSwingHoleCorrection(
                            roundID: roundID,
                            swingID: swing.id,
                            hole: hole
                        )
                    }
                } label: {
                    Label(
                        assignedHole == hole ? "Keep on hole \(hole)" : "Move to hole \(hole)",
                        systemImage: assignedHole == hole ? "checkmark" : "flag.fill"
                    )
                }
            }
            Divider()
            Button(role: .destructive) {
                Task {
                    await model.setSwingHoleCorrection(
                        roundID: roundID,
                        swingID: swing.id,
                        hole: nil
                    )
                }
            } label: {
                Label("Leave unassigned", systemImage: "flag.slash")
            }
        } label: {
            Label(
                assignedHole.map { "Assign or move from hole \($0)" } ?? "Assign to a hole",
                systemImage: "arrow.left.arrow.right.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.golfLime)
        }
        .accessibilityLabel(
            assignedHole.map { "Change accepted swing observation from hole \($0)" }
                ?? "Assign accepted swing observation to a hole"
        )
        .accessibilityHint("Opens manual hole assignment and unassignment controls")
    }

    @ViewBuilder
    private var intervalView: some View {
        if let interval = swing.shotInterval {
            let destinationHole = assignedHoleBySwingID[interval.finalizedBySwingID]
            let crossesHole = assignedHole != nil && destinationHole != nil && assignedHole != destinationHole

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: interval.distanceStatus == .measured ? "point.topleft.down.to.point.bottomright.curvepath" : "exclamationmark.triangle.fill")
                        .foregroundStyle(interval.distanceStatus == .measured ? Color.golfLime : Color.golfSand)
                        .accessibilityHidden(true)
                    Text("SHOT INTERVAL")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Color.golfMist)
                    Spacer()
                    if crossesHole {
                        CorrectionNeededBadge(label: "Cross-hole review")
                    } else if interval.distanceStatus != .measured {
                        CorrectionNeededBadge(label: "Review GPS")
                    }
                }

                Text("\(PostRoundFormat.elapsed(interval.elapsedSeconds)) to the next accepted swing observation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let yards = interval.straightLineDisplacementYards {
                    Text("\(yards.formatted(.number.precision(.fractionLength(0)))) yd GPS displacement")
                        .font(.title3.bold())
                        .monospacedDigit()
                        .foregroundStyle(Color.golfLime)
                    if let uncertainty = interval.distanceUncertaintyYards {
                        Text("± \(uncertainty.formatted(.number.precision(.fractionLength(0)))) yd GPS uncertainty")
                            .font(.caption)
                            .foregroundStyle(Color.golfMist)
                    }
                } else {
                    Text("GPS displacement unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.golfSand)
                }

                Text(PostRoundFormat.distanceStatus(interval.distanceStatus))
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                    .fixedSize(horizontal: false, vertical: true)

                if crossesHole {
                    Text("The next swing is grouped into another hole. Keep this elapsed interval for review, but do not treat its displacement as a shot result without correction.")
                        .font(.caption)
                        .foregroundStyle(Color.golfSand)
                }

                PostRoundProvenanceBadge(provenance: interval.provenance, compact: true)
            }
            .padding(12)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: isGlobalLastSwing ? "hourglass" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isGlobalLastSwing ? Color.golfLime : Color.golfSand)
                        .accessibilityHidden(true)
                    Text(isGlobalLastSwing ? "LAST SWING PENDING" : "INTERVAL UNAVAILABLE")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(isGlobalLastSwing ? Color.golfLime : Color.golfSand)
                }
                Text(
                    isGlobalLastSwing
                        ? "No later swing has finalized elapsed time or GPS displacement."
                        : "This swing has no finalized next-swing interval and needs review."
                )
                .font(.caption)
                .foregroundStyle(Color.golfMist)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct PostRoundWristRotationCard: View {
    let analysis: WhoopMotionWristAnalysis

    private var points: [WhoopWristTracePoint] {
        analysis.orientationTrace?.points ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("WHOOP WRIST ROTATION", systemImage: "gyroscope")
                    .font(.caption2.weight(.black))
                    .tracking(0.7)
                    .foregroundStyle(Color.golfLime)
                Spacer()
                Text(analysis.quality.status.rawValue.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(analysis.quality.status == .usable ? Color.golfLime : Color.golfSand)
            }

            if points.count >= 2 {
                GeometryReader { geometry in
                    Canvas { context, size in
                        let earliest = points.first?.offsetMilliseconds ?? -1
                        let duration = max(1, -earliest)
                        let angles = points.map { Self.rotationAngleDegrees($0.orientation) }
                        let maximumAngle = max(1, angles.max() ?? 1)
                        var path = Path()
                        for (index, point) in points.enumerated() {
                            let x = size.width * CGFloat((point.offsetMilliseconds - earliest) / duration)
                            let y = size.height * CGFloat(1 - (angles[index] / maximumAngle))
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        context.stroke(path, with: .color(Color.golfLime), lineWidth: 3)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(height: 86)
                .accessibilityHidden(true)

                HStack {
                    Text("ADDRESS")
                    Spacer()
                    Text("IMPACT")
                }
                .font(.caption2.weight(.black))
                .foregroundStyle(Color.golfMist)
            } else {
                Text("A quality-gated orientation trace was unavailable; phase metrics remain preserved.")
                    .font(.caption)
                    .foregroundStyle(Color.golfSand)
            }

            HStack(spacing: 12) {
                if let travel = analysis.features.totalAngularTravelToImpactDegrees {
                    Text("\(travel.formatted(.number.precision(.fractionLength(0))))° wrist travel")
                }
                Text("\(analysis.sampling.sampleCount) samples")
            }
            .font(.caption.weight(.semibold))

            Text("Address-relative WHOOP sensor orientation. This is a wrist-motion signature—not clubhead path, face angle, ball flight, or translation.")
                .font(.caption2)
                .foregroundStyle(Color.golfMist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let trace = points.isEmpty ? "orientation trace unavailable" : "\(points.count) orientation points"
        return "WHOOP wrist rotation, \(analysis.quality.status.rawValue), \(trace). Not clubhead or ball path."
    }

    private static func rotationAngleDegrees(_ quaternion: WhoopMotionUnitQuaternion) -> Double {
        let normalizedScalar = min(1, max(-1, abs(quaternion.w)))
        return 2 * acos(normalizedScalar) * 180 / .pi
    }
}

private struct PostRoundFirstLateCard: View {
    let analysis: PostRoundFirstLateAnalysis

    var body: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 14) {
                PostRoundSectionHeader(
                    eyebrow: "FIRST VS LATE",
                    title: "Tempo & fatigue context",
                    detail: "Chronological halves are descriptive only. Differences do not establish fatigue or explain score."
                )

                if analysis.totalSwingCount < 2 {
                    PostRoundEmptyState(
                        symbol: "chart.xyaxis.line",
                        title: "Not enough swings to compare",
                        detail: "At least two ordered swing observations are needed to form first and late segments."
                    )
                } else {
                    PostRoundComparisonRow(
                        title: "Tempo ratio",
                        unit: "",
                        comparison: analysis.tempo,
                        fractionDigits: 2
                    )
                    Divider().overlay(.white.opacity(0.08))
                    PostRoundComparisonRow(
                        title: "Wrist peak",
                        unit: "g",
                        comparison: analysis.peakG,
                        fractionDigits: 1
                    )
                    Divider().overlay(.white.opacity(0.08))
                    PostRoundComparisonRow(
                        title: "Heart rate",
                        unit: "bpm",
                        comparison: analysis.heartRate,
                        fractionDigits: 0
                    )

                    Text("Each metric has its own sample count because tempo and heart rate may be absent from some swings. Two samples per segment are required before a descriptive difference is shown.")
                        .font(.caption2)
                        .foregroundStyle(Color.golfMist)
                }
            }
        }
    }
}

private struct PostRoundComparisonRow: View {
    let title: String
    let unit: String
    let comparison: PostRoundMetricComparison
    let fractionDigits: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    segment(label: "FIRST", average: comparison.firstAverage, count: comparison.firstCount)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.golfMist)
                        .accessibilityHidden(true)
                    segment(label: "LATE", average: comparison.lateAverage, count: comparison.lateCount)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    segment(label: "FIRST", average: comparison.firstAverage, count: comparison.firstCount)
                    segment(label: "LATE", average: comparison.lateAverage, count: comparison.lateCount)
                }
            }

            if let delta = comparison.descriptiveDelta {
                Text("Descriptive late − first: \(PostRoundFormat.signed(delta, fractionDigits: fractionDigits))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.golfLime)
            } else {
                Text("Insufficient samples for a descriptive difference.")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func segment(label: String, average: Double?, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.black))
                .tracking(0.7)
                .foregroundStyle(Color.golfMist)
            Text(average.map { PostRoundFormat.number($0, fractionDigits: fractionDigits) } ?? "—")
                .font(.headline.monospacedDigit())
            if !unit.isEmpty, average != nil {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }
            Text("n=\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.golfMist)
        }
    }
}

private struct PostRoundSectionHeader: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.black))
                .tracking(1.1)
                .foregroundStyle(Color.golfLime)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PostRoundStatTile: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.golfMist)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.golfMist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PostRoundMetricCapsule: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.golfMist)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PostRoundCompactValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.golfMist)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

private struct PostRoundSourceChip: View {
    let source: MetricSource

    var body: some View {
        Label(PostRoundFormat.sourceLabel(source), systemImage: source.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(source == .whoopMotion ? Color.golfLime : Color.golfSand)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.25), in: Capsule())
            .accessibilityLabel("Source: \(PostRoundFormat.sourceLabel(source))")
    }
}

private struct PostRoundProvenanceBadge: View {
    let provenance: DataProvenance
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                sourceLabel
                confidenceLabel
            }
            VStack(alignment: .leading, spacing: 6) {
                sourceLabel
                confidenceLabel
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceLabel: some View {
        Label(PostRoundFormat.sourceLabel(provenance.source), systemImage: provenance.source.symbol)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(provenance.source == .whoopMotion ? Color.golfLime : Color.golfSand)
    }

    private var confidenceLabel: some View {
        Label(
            "\(PostRoundFormat.qualityLabel(provenance.quality)) confidence",
            systemImage: PostRoundFormat.qualitySymbol(provenance.quality)
        )
        .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
        .foregroundStyle(PostRoundFormat.qualityColor(provenance.quality))
    }
}

private struct CorrectionNeededBadge: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .black))
            .tracking(0.45)
            .foregroundStyle(Color.golfSand)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.golfSand.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color.golfSand.opacity(0.26), lineWidth: 1))
    }
}

private struct PostRoundNotice: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.golfLime)
                .frame(width: 28, height: 28)
                .background(Color.golfLime.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct PostRoundEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.golfMist)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PostRoundPresentation {
    let holes: [PostRoundHoleSummary]
    let unassignedSwings: [GolfSwingMetrics]
    let assignedHoleBySwingID: [UUID: Int]
    let assignmentBySwingID: [UUID: SwingHoleAssignment]
    let lastSwingID: UUID?
    let sources: [MetricSource]
    let measuredIntervalCount: Int
    let firstLateAnalysis: PostRoundFirstLateAnalysis

    init(round: GolfRound) {
        let orderedShots = round.shots.sorted {
            if $0.capturedAt == $1.capturedAt { return $0.sequence < $1.sequence }
            return $0.capturedAt < $1.capturedAt
        }
        let orderedSwings = round.swings.sorted {
            if $0.capturedAt == $1.capturedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.capturedAt < $1.capturedAt
        }

        var assignments: [UUID: Int] = [:]
        var assignmentDetails: [UUID: SwingHoleAssignment] = [:]
        var unassigned: [GolfSwingMetrics] = []
        for swing in orderedSwings {
            let assignment = round.holeAssignment(for: swing.id)
                ?? SwingHoleAssignment(hole: nil, method: .unavailable, auditedAt: nil)
            assignmentDetails[swing.id] = assignment
            guard let hole = assignment.hole else {
                unassigned.append(swing)
                continue
            }
            assignments[swing.id] = hole
        }

        holes = round.holes.map { result in
            PostRoundHoleSummary(
                result: result,
                gpsMarks: orderedShots.filter { $0.hole == result.number },
                swings: orderedSwings.filter { assignments[$0.id] == result.number }
            )
        }
        unassignedSwings = unassigned
        assignedHoleBySwingID = assignments
        assignmentBySwingID = assignmentDetails
        lastSwingID = orderedSwings.last?.id
        sources = Self.uniqueSources(orderedSwings.map(\.provenance.source))
        measuredIntervalCount = orderedSwings.lazy.filter {
            $0.shotInterval?.distanceStatus == .measured
                && $0.shotInterval?.straightLineDisplacementYards != nil
        }.count
        firstLateAnalysis = PostRoundFirstLateAnalysis(swings: orderedSwings)
    }

    private static func uniqueSources(_ sources: [MetricSource]) -> [MetricSource] {
        let order: [MetricSource] = [
            .whoopMotion, .appleWatch, .manual, .iphoneGPS,
            .whoopBroadcast, .whoopCloud, .healthKit, .derived, .demo,
        ]
        let values = Set(sources)
        return order.filter(values.contains)
    }
}

private struct PostRoundHoleSummary: Identifiable {
    let result: HoleResult
    let gpsMarks: [ShotRecord]
    let swings: [GolfSwingMetrics]

    var id: Int { result.number }
    var number: Int { result.number }
    var par: Int? { result.par }
    var strokes: Int? { result.strokes }
    var gpsMarkCount: Int { gpsMarks.count }
    var swingCount: Int { swings.count }

    var reviewLabel: String? {
        if par == nil || strokes == nil { return "Score needed" }
        return nil
    }

    var accessibilitySummary: String {
        let parText = par.map(String.init) ?? "not entered"
        let strokeText = strokes.map(String.init) ?? "not entered"
        let review = reviewLabel.map { ", \($0)" } ?? ""
        return "Hole \(number), par \(parText), strokes \(strokeText), "
            + "\(swingCount) accepted swing observations, \(gpsMarkCount) GPS marks\(review)"
    }
}

private struct PostRoundFirstLateAnalysis {
    let totalSwingCount: Int
    let tempo: PostRoundMetricComparison
    let peakG: PostRoundMetricComparison
    let heartRate: PostRoundMetricComparison

    init(swings: [GolfSwingMetrics]) {
        totalSwingCount = swings.count
        let split = (swings.count + 1) / 2
        let first = Array(swings.prefix(split))
        let late = Array(swings.dropFirst(split))

        tempo = PostRoundMetricComparison(
            firstValues: first.compactMap { swing in
                guard let value = swing.tempoRatio, value.isFinite, value > 0 else { return nil }
                return value
            },
            lateValues: late.compactMap { swing in
                guard let value = swing.tempoRatio, value.isFinite, value > 0 else { return nil }
                return value
            }
        )
        peakG = PostRoundMetricComparison(
            firstValues: first.compactMap { $0.peakG.isFinite && $0.peakG > 0 ? $0.peakG : nil },
            lateValues: late.compactMap { $0.peakG.isFinite && $0.peakG > 0 ? $0.peakG : nil }
        )
        heartRate = PostRoundMetricComparison(
            firstValues: first.compactMap { value in
                guard let heartRate = value.heartRateBPM, heartRate > 0 else { return nil }
                return Double(heartRate)
            },
            lateValues: late.compactMap { value in
                guard let heartRate = value.heartRateBPM, heartRate > 0 else { return nil }
                return Double(heartRate)
            }
        )
    }
}

private struct PostRoundMetricComparison {
    let firstAverage: Double?
    let lateAverage: Double?
    let firstCount: Int
    let lateCount: Int

    init(firstValues: [Double], lateValues: [Double]) {
        firstCount = firstValues.count
        lateCount = lateValues.count
        firstAverage = Self.average(firstValues)
        lateAverage = Self.average(lateValues)
    }

    var descriptiveDelta: Double? {
        guard firstCount >= 2, lateCount >= 2, let firstAverage, let lateAverage else { return nil }
        return lateAverage - firstAverage
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum PostRoundFormat {
    static func scoreLabel(_ round: GolfRound) -> String {
        if let score = round.scoreToPar {
            return score == 0 ? "E" : String(format: "%+d", score)
        }
        if round.legacyScoreToPar != nil { return "Legacy" }
        if round.enteredStrokes != nil { return "Partial" }
        return "—"
    }

    static func accessibleScore(_ round: GolfRound) -> String {
        if let score = round.scoreToPar {
            if score == 0 { return "even par" }
            return score > 0 ? "plus \(score)" : "minus \(abs(score))"
        }
        if round.legacyScoreToPar != nil { return "legacy unverified" }
        if round.enteredStrokes != nil { return "partial" }
        return "not entered"
    }

    static func roundDate(_ round: GolfRound) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: round.timeZoneIdentifier) ?? .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: round.startedAt)
    }

    static func roundDuration(_ round: GolfRound) -> String? {
        guard let endedAt = round.endedAt, endedAt >= round.startedAt else { return nil }
        return elapsed(endedAt.timeIntervalSince(round.startedAt))
    }

    static func swingTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Time unavailable" }
        let rounded = Int(seconds.rounded())
        if rounded < 60 { return "\(rounded)s" }
        let minutes = rounded / 60
        let remainder = rounded % 60
        if minutes < 60 { return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s" }
        let hours = minutes / 60
        let minuteRemainder = minutes % 60
        return minuteRemainder == 0 ? "\(hours)h" : "\(hours)h \(minuteRemainder)m"
    }

    static func holeScoreDetail(_ hole: PostRoundHoleSummary) -> String {
        guard let strokes = hole.strokes, let par = hole.par else { return "Incomplete score" }
        let difference = strokes - par
        if difference == 0 { return "Even on hole" }
        return difference > 0 ? "+\(difference) on hole" : "\(difference) on hole"
    }

    static func sourceLabel(_ source: MetricSource) -> String {
        switch source {
        case .whoopMotion: "WHOOP 5 · historical"
        case .appleWatch: "Apple Watch · legacy"
        case .manual: "Manual observation"
        case .iphoneGPS: "iPhone GPS"
        case .whoopBroadcast: "WHOOP HR Broadcast"
        case .whoopCloud: "WHOOP Cloud"
        case .healthKit: "Apple Health"
        case .derived: "In-house derivation"
        case .demo: "Demo"
        }
    }

    static func sourceContext(_ provenance: DataProvenance) -> String? {
        let algorithm = provenance.algorithmVersion.map { " · algorithm \($0)" } ?? ""
        switch provenance.source {
        case .whoopMotion:
            let delay = max(0, provenance.receivedAt.timeIntervalSince(provenance.observedAt))
            let delayText = delay >= 1
                ? " · received \(elapsed(delay)) after observation"
                : " · delayed offload source"
            return "Historical WHOOP 5 motion\(delayText)\(algorithm)"
        case .appleWatch:
            return "Legacy Apple Watch motion import\(algorithm)"
        case .manual:
            return "Manual observation\(algorithm)"
        default:
            return provenance.algorithmVersion.map { "Algorithm \($0)" }
        }
    }

    static func qualityLabel(_ quality: DataQuality) -> String {
        switch quality {
        case .verified: "Verified"
        case .estimated: "Estimated"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        }
    }

    static func qualitySymbol(_ quality: DataQuality) -> String {
        switch quality {
        case .verified: "checkmark.seal.fill"
        case .estimated: "approximately"
        case .stale: "clock.badge.exclamationmark"
        case .unavailable: "xmark.circle"
        }
    }

    static func qualityColor(_ quality: DataQuality) -> Color {
        switch quality {
        case .verified: .golfLime
        case .estimated: .golfSand
        case .stale, .unavailable: .golfMist
        }
    }

    static func distanceStatus(_ status: SwingShotDistanceStatus) -> String {
        switch status {
        case .measured:
            "Measured from quality-gated GPS fixes; still a phone-position estimate."
        case .missingLocation:
            "One or both swing locations are missing."
        case .missingHorizontalAccuracy:
            "GPS accuracy metadata is missing, so distance was withheld."
        case .staleLocation:
            "A location fix was too far from its swing timestamp."
        case .lowHorizontalAccuracy:
            "GPS accuracy did not meet the 25 m quality gate."
        case .nonIncreasingTimestamps:
            "Swing timestamps were not in increasing order."
        }
    }

    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    static func signed(_ value: Double, fractionDigits: Int) -> String {
        let magnitude = number(abs(value), fractionDigits: fractionDigits)
        if value > 0 { return "+\(magnitude)" }
        if value < 0 { return "−\(magnitude)" }
        return number(0, fractionDigits: fractionDigits)
    }
}

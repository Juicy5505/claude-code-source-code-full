import SwiftUI

struct RoundView: View {
    @EnvironmentObject private var model: AppModel
    @State private var courseName = ""
    @State private var holeCount: GolfHoleCount = .eighteen
    @State private var showFinishConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                GolfBackground()
                if let round = model.activeRound {
                    LiveRoundView(
                        round: round,
                        location: model.location,
                        heartRate: model.heartRate,
                        sensorPlan: model.sensorPlan(for: round.recordingDevice),
                        trackingActive: model.roundTrackingActive,
                        isFinishing: model.isFinishingRound,
                        onRecordShot: { Task { await model.recordShot() } },
                        onStrokes: { delta in Task { await model.changeStrokes(by: delta) } },
                        onPar: { delta in Task { await model.changePar(by: delta) } },
                        onHole: { delta in Task { await model.moveHole(by: delta) } },
                        onResume: { Task { await model.resumeRoundTracking() } },
                        onFinish: { showFinishConfirmation = true }
                    )
                } else {
                    preflight
                }
            }
            .navigationTitle(
                model.activeRound == nil
                    ? "Start Round"
                    : (model.roundTrackingActive ? "Live Round" : "Round Draft")
            )
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Finish this round?",
                isPresented: $showFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish and save", role: .destructive) {
                    Task { await model.finishRound() }
                }
                Button("Keep playing", role: .cancel) {}
            } message: {
                if let round = model.activeRound, !round.isScoreComplete {
                    Text("The protected round will finish with an incomplete scorecard and will not count in score analysis. Local save does not depend on any Apple service.")
                } else {
                    Text("The protected round is finalized locally first. Optional exports run only when configured.")
                }
            }
            .task {
                if model.activeRound == nil {
                    await model.requestCourseSuggestion()
                }
            }
        }
    }

    private var preflight: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ROUND PREFLIGHT")
                        .font(.caption.weight(.black))
                        .tracking(1.6)
                        .foregroundStyle(Color.golfLime)
                    Text("Know what's ready\nbefore the first tee.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                }

                GolfCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Course or session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.golfMist)
                        TextField("e.g. Range session", text: $courseName)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                        courseSuggestion
                        Picker("Round length", selection: $holeCount) {
                            ForEach(GolfHoleCount.allCases) { count in
                                Text("\(count.rawValue) holes").tag(count)
                            }
                        }
                        .pickerStyle(.segmented)
                        Label(sensorModeTitle, systemImage: sensorModeSymbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.golfLime)
                        Text(sensorModeDetail)
                            .font(.caption)
                            .foregroundStyle(Color.golfMist)
                    }
                }

                SensorModeSummaryCard(plan: model.adaptiveSensorPlan)

                if let snapshot = model.readiness {
                    GolfCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("READINESS BEFORE ROUND")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(Color.golfMist)
                                Spacer()
                                SourceBadge(provenance: snapshot.provenance)
                            }
                            Text(snapshot.verdict)
                                .font(.title3.weight(.bold))
                            HStack(spacing: 14) {
                                Text(snapshot.score.map { "\(Int($0.rounded()))" } ?? "—")
                                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snapshot.advice)
                                        .font(.caption)
                                        .foregroundStyle(Color.golfMist)
                                        .lineLimit(3)
                                    Text(model.wearableContributionBoard.readinessBeforeRoundDetail)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            Text(model.wearableContributionBoard.roundFusion.delayedMergeCaption)
                                .font(.caption2)
                                .foregroundStyle(Color.golfMist)
                        }
                    }
                }

                EighteenBirdiesCompanionCard()

                GolfCard {
                    VStack(spacing: 0) {
                        PreflightRow(
                            title: "Apple Watch capture",
                            detail: model.sensorCapabilities.appleWatch.canCaptureLive
                                ? "Paired app · live wrist motion, GPS, haptic, durable transfer"
                                : "Pair and install WhoopGolfWatch for the live sensor path",
                            symbol: "applewatch",
                            state: model.sensorCapabilities.appleWatch.canCaptureLive ? .ready : .optional
                        )
                        Divider().overlay(.white.opacity(0.08))
                        PreflightRow(
                            title: "WHOOP 5 motion",
                            detail: model.sensorCapabilities.whoop.hasSwingSource
                                ? "Post-round six-axis wrist analysis · no band GPS"
                                : "Private bridge/offload setup is not yet proven",
                            symbol: "gyroscope",
                            state: model.sensorCapabilities.whoop.hasSwingSource ? .ready : .blocked
                        )
                        Divider().overlay(.white.opacity(0.08))
                        PreflightRow(
                            title: model.adaptiveSensorPlan.spatialProvider == .appleWatchGPS
                                ? "Apple Watch GPS"
                                : "iPhone GPS",
                            detail: spatialPreflightDetail,
                            symbol: "location.fill",
                            state: locationPreflightState
                        )
                        Divider().overlay(.white.opacity(0.08))
                        PreflightRow(
                            title: "Direct WHOOP HR",
                            detail: "Standard HR Broadcast · optional physiology channel",
                            symbol: "wave.3.right",
                            state: whoopPreflightState
                        )
                    }
                }

                Text("Swing motion always comes from the selected wearable. GPS supplies only the A→B position estimate. The next accepted swing closes the previous shot; a hole boundary withholds the walk to the next tee. Distances are displacement estimates—not carry or ball telemetry.")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                    .padding(.horizontal, 3)

                Button {
                    Task {
                        await model.startRound(
                            courseName: courseName,
                            holeCount: holeCount
                        )
                    }
                } label: {
                    Label(startButtonTitle, systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
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

    @ViewBuilder
    private var courseSuggestion: some View {
        switch model.courseLookupState {
        case .idle:
            Button("Find nearby course") {
                Task { await model.requestCourseSuggestion() }
            }
            .font(.caption.weight(.semibold))
        case .locating:
            Label("Getting a precise location…", systemImage: "location.magnifyingglass")
                .font(.caption)
                .foregroundStyle(Color.golfMist)
        case .searching:
            HStack(spacing: 8) {
                ProgressView().tint(.golfLime)
                Text("Searching Apple Maps for nearby golf facilities")
            }
            .font(.caption)
            .foregroundStyle(Color.golfMist)
        case .suggested(let candidate):
            CourseCandidateButton(candidate: candidate) {
                courseName = candidate.name
                model.confirmCourse(candidate)
            }
        case .ambiguous(let candidates):
            VStack(alignment: .leading, spacing: 8) {
                Text("Several courses are nearby. Choose the facility—hole geometry is not inferred.")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                ForEach(candidates) { candidate in
                    CourseCandidateButton(candidate: candidate) {
                        courseName = candidate.name
                        model.confirmCourse(candidate)
                    }
                }
            }
        case .confirmed(let candidate):
            Label(
                "Confirmed · \(candidate.name) · \(Int(candidate.distanceMeters.rounded())) m away",
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.golfLime)
        case .noneNearby:
            HStack {
                Text("No nearby course was found. Enter it manually.")
                Spacer()
                Button("Retry") { Task { await model.retryCourseSuggestion() } }
            }
            .font(.caption)
            .foregroundStyle(Color.golfMist)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .lineLimit(2)
                Button("Try course lookup again") {
                    Task { await model.retryCourseSuggestion() }
                }
            }
            .font(.caption)
            .foregroundStyle(Color.golfSand)
        }
    }

    private var locationPreflightState: PreflightRow.State {
        if model.adaptiveSensorPlan.spatialProvider == .appleWatchGPS {
            return model.sensorCapabilities.appleWatch.canCaptureLive ? .ready : .blocked
        }
        return switch model.location.state {
        case .ready: .ready
        case .denied: .optional
        default: .willRequest
        }
    }

    private var whoopPreflightState: PreflightRow.State {
        if model.heartRate.hasFreshReading { return .ready }
        return switch model.heartRate.state {
        case .scanning, .connecting: .willRequest
        default: .optional
        }
    }

    private var sensorModeTitle: String {
        switch model.adaptiveSensorPlan.mode {
        case .whoopOnly: "WHOOP-only · delayed wrist reconstruction"
        case .appleWatchOnly: "Apple Watch-only · live shot automation"
        case .hybrid: "Hybrid · Watch live + WHOOP enrichment"
        case .unavailable: "Wearable sensor not ready · manual fallback"
        }
    }

    private var sensorModeSymbol: String {
        switch model.adaptiveSensorPlan.mode {
        case .appleWatchOnly, .hybrid: "applewatch"
        case .whoopOnly: "gyroscope"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var sensorModeDetail: String {
        switch model.adaptiveSensorPlan.mode {
        case .whoopOnly:
            "WHOOP owns swing timing and wrist analytics. The iPhone contributes GPS only because WHOOP 5 has no GPS."
        case .appleWatchOnly:
            "The Watch owns live motion, synchronized GPS, shot haptic, and the durable session. Apple Health export is not required."
        case .hybrid:
            "Apple Watch owns each counted live shot; a unique delayed WHOOP match enriches that shot without double-counting."
        case .unavailable:
            "No wearable motion source is currently proven. You can still save the scorecard and GPS checkpoints without pretending they are automatic swings."
        }
    }

    private var spatialPreflightDetail: String {
        switch model.adaptiveSensorPlan.spatialProvider {
        case .appleWatchGPS: "Synchronized at each Watch swing · quality checked on import"
        case .iphoneGPS: "Protected background timeline · accepts ≤25 m accuracy"
        case .unavailable: "No geographic source · swing analytics work, yardage does not"
        }
    }

    private var startButtonTitle: String {
        switch model.adaptiveSensorPlan.mode {
        case .whoopOnly: "Start WHOOP round"
        case .appleWatchOnly: "Start linked Watch round"
        case .hybrid: "Start hybrid round"
        case .unavailable: "Start manual fallback"
        }
    }
}

private struct SensorModeSummaryCard: View {
    let plan: AdaptiveSensorPlan

    var body: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ADAPTIVE SENSOR PLAN", systemImage: "sensor.tag.radiowaves.forward")
                        .font(.caption.weight(.black))
                        .tracking(1)
                        .foregroundStyle(Color.golfMist)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(stateColor)
                }
                Text(modeLabel)
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    planPill(captureLabel, symbol: "gyroscope")
                    planPill(spatialLabel, symbol: "location.fill")
                    planPill(hapticLabel, symbol: "waveform")
                }
                .accessibilityElement(children: .combine)
                if !plan.constraints.isEmpty {
                    Text(constraintSummary)
                        .font(.caption)
                        .foregroundStyle(Color.golfMist)
                }
            }
        }
    }

    private func planPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private var modeLabel: String {
        switch plan.mode {
        case .whoopOnly: "WHOOP only"
        case .appleWatchOnly: "Apple Watch only"
        case .hybrid: "WHOOP + Apple Watch"
        case .unavailable: "Manual fallback"
        }
    }

    private var stateLabel: String {
        switch plan.operationalState {
        case .ready: "READY"
        case .liveCaptureWithDelayedEnrichment: "LIVE + LATER"
        case .delayedPostRoundCapture: "POST-ROUND"
        case .distanceUnavailable: "NO YARDAGE"
        case .unavailable: "ACTION"
        }
    }

    private var stateColor: Color {
        plan.operationalState == .ready ||
            plan.operationalState == .liveCaptureWithDelayedEnrichment
            ? .golfLime
            : .golfSand
    }

    private var captureLabel: String {
        plan.canCaptureSwingLive ? "Live swing" :
            (plan.canReconstructSwingPostRound ? "Post-round" : "No swing")
    }

    private var spatialLabel: String {
        switch plan.spatialProvider {
        case .appleWatchGPS: "Watch GPS"
        case .iphoneGPS: "iPhone GPS"
        case .unavailable: "No GPS"
        }
    }

    private var hapticLabel: String {
        switch plan.hapticRoute {
        case .appleWatchLocal: "Watch haptic"
        case .iphone: "Phone notice"
        case .whoopBandAuthorizedProvider: "WHOOP haptic"
        case .unavailable: "No haptic"
        }
    }

    private var constraintSummary: String {
        plan.constraints.map { constraint in
            switch constraint {
            case .whoopHasNoBuiltInGPS: "WHOOP has no built-in GPS"
            case .whoopHistoricalMotionPending: "WHOOP history not imported yet"
            case .whoopLiveRawMotionUnavailable: "WHOOP motion is delayed"
            case .whoopBandHapticUnavailable: "WHOOP band haptic unavailable"
            case .watchNotReachable: "Watch messages are not reachable"
            case .watchSynchronizedLocationUnavailable: "Watch GPS not proven"
            case .iphoneLocationUnavailable: "iPhone location unavailable"
            case .approximateIPhoneLocation: "Precise Location is off"
            case .noSwingSensorAvailable: "No wearable swing source is ready"
            }
        }.joined(separator: " · ")
    }
}

private struct CourseCandidateButton: View {
    let candidate: GolfCourseCandidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.golfLime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(Int(candidate.distanceMeters.rounded())) m away · \(candidate.confidence.rawValue) confidence · Apple Maps")
                        .font(.caption2)
                        .foregroundStyle(Color.golfMist)
                }
                Spacer()
                Text("USE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color.golfLime)
            }
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct LiveRoundView: View {
    let round: GolfRound
    @ObservedObject var location: LocationRoundService
    @ObservedObject var heartRate: WhoopHeartRateProvider
    let sensorPlan: AdaptiveSensorPlan
    let trackingActive: Bool
    let isFinishing: Bool
    let onRecordShot: () -> Void
    let onStrokes: (Int) -> Void
    let onPar: (Int) -> Void
    let onHole: (Int) -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(round.courseName)
                            .font(.headline)
                        Text("Started \(round.startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Color.golfMist)
                        Text(recordingSourceLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.golfMist)
                    }
                    Spacer()
                    if trackingActive {
                        Label("GPS TRACKING", systemImage: "circle.fill")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color.golfLime)
                            .symbolEffect(.pulse)
                    } else {
                        Label("DRAFT PAUSED", systemImage: "pause.circle.fill")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color.golfSand)
                    }
                }

                GolfCard {
                    VStack(spacing: 13) {
                        HStack(spacing: 14) {
                            RoundStepper(
                                label: "HOLE",
                                value: "\(round.currentHole)/\(round.holeCount.rawValue)",
                                decrement: { onHole(-1) },
                                increment: { onHole(1) }
                            )
                            Divider().frame(height: 90).overlay(.white.opacity(0.1))
                            RoundStepper(
                                label: "PAR",
                                value: round.currentPar.map(String.init) ?? "—",
                                decrement: { onPar(-1) },
                                increment: { onPar(1) }
                            )
                            Divider().frame(height: 90).overlay(.white.opacity(0.1))
                            RoundStepper(
                                label: "STROKES",
                                value: round.currentStrokes.map { "\($0)" } ?? "—",
                                decrement: { onStrokes(-1) },
                                increment: { onStrokes(1) }
                            )
                        }
                        Divider().overlay(.white.opacity(0.1))
                        Text(scorecardSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(round.isScoreComplete ? Color.golfLime : Color.golfMist)
                    }
                }

                if !trackingActive {
                    Button(action: onResume) {
                        Label("Resume round sensors", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.golfSand)
                    .foregroundStyle(Color.golfInk)
                }

                HStack(spacing: 10) {
                    MetricTile(
                        label: "GPS",
                        value: gpsValue,
                        detail: gpsDetail,
                        symbol: "location.fill"
                    )
                    MetricTile(
                        label: "Live HR",
                        value: heartRate.hasFreshReading
                            ? heartRate.heartRateBPM.map { "\($0)" } ?? "—"
                            : "—",
                        detail: heartRate.hasFreshReading ? "bpm · direct WHOOP HR Broadcast" : heartRateDetail,
                        symbol: "heart.fill"
                    )
                }

                GolfCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("TRACKING SOURCES", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption.weight(.black))
                            .tracking(1)
                            .foregroundStyle(Color.golfMist)
                        Text(trackingSourceDetail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Accepted wearable observations: \(round.swings.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.golfLime)
                    }
                }

                GolfCard {
                    GolfStrokeBoardView(
                        rows: GolfStrokePresentation.rows(for: round, wrist: WatchWristMount.load()),
                        title: "STROKE BOARD",
                        emptyDetail: "Live Watch swings and fused WHOOP enrichments land here with path score, explanation, and swing-to-swing GPS yards."
                    )
                }

                GolfSessionSummaryCard(round: round, wrist: WatchWristMount.load())

                EighteenBirdiesCompanionCard()

                Button(action: onRecordShot) {
                    VStack(spacing: 5) {
                        Label("Manual GPS checkpoint", systemImage: "scope")
                            .font(.title3.bold())
                        Text(shotMarkingDetail)
                            .font(.caption)
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(.golfLime)
                .foregroundStyle(Color.golfInk)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .disabled(!trackingActive || isFinishing)

                GolfCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("SHOT TIMELINE")
                                .font(.caption.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(Color.golfMist)
                            Spacer()
                            Text("\(round.shots.count) marked")
                                .font(.caption)
                        }
                        if round.shots.isEmpty {
                            Text("No manually marked positions yet. Wait for an accurate GPS state, then tap the button at the ball position before each shot.")
                                .font(.subheadline)
                                .foregroundStyle(Color.golfMist)
                        } else {
                            ForEach(round.shots.suffix(4).reversed()) { shot in
                                ShotTimelineRow(shot: shot)
                            }
                        }
                    }
                }

                Button("Finish round", role: .destructive, action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                    .disabled(isFinishing)
            }
            .padding(18)
            .padding(.bottom, 28)
        }
    }

    private var scorecardSummary: String {
        guard round.enteredStrokes != nil else {
            return "No strokes entered · score remains unset"
        }
        guard let running = round.runningScoreToPar else {
            return "Strokes entered · add each hole's par for score-to-par"
        }
        let score = running == 0 ? "E" : String(format: "%+d", running)
        if round.isScoreComplete, let gross = round.grossScore {
            return "Complete · \(gross) strokes · \(score)"
        }
        return "\(round.scoredHoleCount)/\(round.holeCount.rawValue) strokes · \(round.parredHoleCount)/\(round.holeCount.rawValue) pars · \(score) running"
    }

    private var recordingSourceLabel: String {
        switch round.recordingDevice {
        case .whoop5:
            "WHOOP import pending · iPhone GPS"
        case .iphone:
            "Local round · iPhone"
        case .appleWatch:
            "Apple Watch live motion · synchronized GPS"
        case .hybrid:
            "Hybrid · Watch live shot + WHOOP wrist enrichment"
        }
    }

    private var trackingSourceDetail: String {
        switch round.recordingDevice {
        case .whoop5:
            "WHOOP owns swing motion. The iPhone records GPS only for later A→B correlation; HR Broadcast is a separate optional channel."
        case .appleWatch:
            "The Apple Watch records live wrist motion, GPS, HR, and immediate shot haptics into a durable linked session."
        case .hybrid:
            "The Apple Watch records each live shot and GPS point. Delayed WHOOP wrist analysis may enrich a unique timestamp match, never add another shot."
        case .iphone:
            "No wearable swing source is active. Manual checkpoints and scorecard changes remain protected locally."
        }
    }

    private var heartRateDetail: String {
        switch heartRate.state {
        case .scanning:
            "Scanning for direct WHOOP HR"
        case .connecting:
            "Connecting to WHOOP broadcast"
        case .stale:
            "WHOOP signal stale"
        case .bluetoothOff:
            "Bluetooth is off"
        case .unauthorised:
            "Bluetooth permission denied"
        case .failed:
            "WHOOP broadcast unavailable"
        default:
            "Direct WHOOP HR optional"
        }
    }

    private var shotMarkingDetail: String {
        guard let latest = round.shots.last else {
            return "Manually creates the first origin on hole \(round.currentHole)"
        }
        guard latest.hole == round.currentHole else {
            return "Manually creates the first origin on hole \(round.currentHole)"
        }
        return "Manual mark finalizes shot \(latest.sequence)'s GPS displacement"
    }

    private var gpsValue: String {
        switch location.state {
        case .ready(let accuracy): "±\(Int(accuracy.rounded())) m"
        case .acquiring: "…"
        case .reducedAccuracy: "Reduced"
        case .denied: "Blocked"
        default: "—"
        }
    }

    private var gpsDetail: String {
        switch location.state {
        case .ready: "Ready for shot marking"
        case .acquiring: "Acquiring accurate fix"
        case .reducedAccuracy: "Enable Precise Location"
        case .denied: "Allow in Settings"
        default: "Not active"
        }
    }
}

private struct RoundStepper: View {
    let label: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(Color.golfMist)
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            HStack(spacing: 13) {
                Button(action: decrement) { Image(systemName: "minus.circle.fill") }
                Button(action: increment) { Image(systemName: "plus.circle.fill") }
            }
            .font(.title3)
            .foregroundStyle(Color.golfLime)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShotTimelineRow: View {
    let shot: ShotRecord

    var body: some View {
        HStack(spacing: 12) {
            Text("\(shot.sequence)")
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(Color.golfLime.opacity(0.16), in: Circle())
                .foregroundStyle(Color.golfLime)
            VStack(alignment: .leading, spacing: 3) {
                Text(shot.distanceToNextYards.map { "\(Int($0.rounded())) yd to next marked position" } ?? "Origin marked · outcome pending")
                    .font(.subheadline.weight(.semibold))
                Text("Hole \(shot.hole) · \(shot.capturedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }
            Spacer()
            if let uncertainty = shot.distanceUncertaintyYards {
                Text("±\(Int(uncertainty.rounded())) yd")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(uncertainty <= 15 ? Color.golfLime : Color.golfSand)
            }
        }
    }
}

private struct PreflightRow: View {
    enum State: Equatable {
        case ready
        case willRequest
        case optional
        case blocked
    }

    let title: String
    let detail: String
    let symbol: String
    let state: State

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(state == .blocked ? Color.golfSand : Color.golfLime)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Color.golfMist)
            }
            Spacer()
            Text(stateText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(state == .blocked ? Color.golfSand : Color.golfMist)
        }
        .padding(.vertical, 13)
    }

    private var stateText: String {
        switch state {
        case .ready: "READY"
        case .willRequest: "ON START"
        case .optional: "OPTIONAL"
        case .blocked: "ACTION"
        }
    }
}

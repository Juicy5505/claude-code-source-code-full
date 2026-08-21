import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                GolfBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if case .error(let message) = model.dataMode {
                            refreshErrorCard(message)
                        }
                        if let snapshot = model.readiness {
                            readinessHero(snapshot)
                            physiologyGrid(snapshot)
                        } else {
                            unavailableCard
                        }
                        connectionCard
                        WatchCompanionStatusCard()
                        Button {
                            model.selectedTab = .round
                        } label: {
                            Label("Start a round", systemImage: "flag.checkered")
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
                .refreshable { await model.refreshReadiness() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHOOP GOLF")
                    .font(.caption.weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(Color.golfLime)
                Text("Play the day\nyou actually have.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if let badge = dataBadge {
                Text(badge)
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Color.golfInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.golfSand, in: Capsule())
                    .accessibilityLabel(dataBadgeAccessibilityLabel)
            }
        }
        .padding(.top, 8)
    }

    private func readinessHero(_ snapshot: ReadinessSnapshot) -> some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GOLF READINESS · DERIVED")
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(Color.golfMist)
                        Text(snapshot.verdict)
                            .font(.title2.bold())
                    }
                    Spacer()
                    SourceBadge(provenance: snapshot.provenance)
                }

                HStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 11)
                        Circle()
                            .trim(from: 0, to: min(max((snapshot.score ?? 0) / 100, 0), 1))
                            .stroke(
                                AngularGradient(colors: [.golfLime, .golfSand, .golfLime], center: .center),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8), value: snapshot.score)
                        VStack(spacing: -2) {
                            Text(snapshot.score.map { String(Int($0.rounded())) } ?? "—")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .monospacedDigit()
                            Text("/ 100")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.golfMist)
                        }
                    }
                    .frame(width: 132, height: 132)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Derived golf readiness")
                    .accessibilityValue(snapshot.score.map { "\(Int($0.rounded())) out of 100" } ?? "Unavailable")

                    VStack(alignment: .leading, spacing: 12) {
                        Text(snapshot.advice)
                            .font(.subheadline.weight(.medium))
                            .lineSpacing(3)
                        Divider().overlay(.white.opacity(0.1))
                        Label(
                            snapshot.personalised ? "Personalised model" : "Baseline model · needs 8 rounds",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.golfMist)
                    }
                }

                HStack {
                    Image(systemName: snapshot.isStale ? "exclamationmark.arrow.circlepath" : "checkmark.circle.fill")
                    Text(freshnessText(snapshot.syncedAt, stale: snapshot.isStale))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(snapshot.isStale ? Color.golfSand : Color.golfLime)

                Text("In-house estimate derived from cached WHOOP metrics. It is not a WHOOP score or medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private func physiologyGrid(_ snapshot: ReadinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY'S INPUTS")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.golfMist)
            HStack(spacing: 10) {
                MetricTile(
                    label: "Recovery",
                    value: snapshot.recoveryPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                    detail: physiologySourceDetail(snapshot),
                    symbol: "heart.text.square.fill"
                )
                MetricTile(
                    label: "Sleep",
                    value: snapshot.sleepHours.map { String(format: "%.1f h", $0) } ?? "—",
                    detail: physiologySourceDetail(snapshot),
                    symbol: "moon.stars.fill"
                )
                MetricTile(
                    label: "Day strain",
                    value: snapshot.dayStrain.map { String(format: "%.1f", $0) } ?? "—",
                    detail: snapshot.provenance.source == .demo
                        ? "Preview fixture"
                        : "WHOOP cloud · not live",
                    symbol: "bolt.heart.fill"
                )
            }
        }
    }

    private var unavailableCard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Connect the private WHOOP bridge", systemImage: "lock.shield")
                    .font(.headline)
                Text("Your WHOOP OAuth secret stays on this Mac. The iPhone receives only the day-level physiology and clearly labeled in-house golf analysis.")
                    .font(.subheadline)
                    .foregroundStyle(Color.golfMist)
                Button("Open Connections") { model.selectedTab = .settings }
                    .buttonStyle(.bordered)
                    .tint(.golfLime)
            }
        }
    }

    private func refreshErrorCard(_ message: String) -> some View {
        GolfCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.golfSand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest refresh failed")
                        .font(.subheadline.weight(.semibold))
                    Text(readinessRetainedText + " " + message)
                        .font(.caption)
                        .foregroundStyle(Color.golfMist)
                }
            }
        }
    }

    private var dataBadge: String? {
        if model.readiness?.provenance.source == .demo {
            return model.dataMode.isError ? "DEMO · REFRESH FAILED" : "DEMO DATA"
        }
        if model.dataMode.isError, model.readiness != nil {
            return "CACHED · REFRESH FAILED"
        }
        return nil
    }

    private var dataBadgeAccessibilityLabel: String {
        if model.readiness?.provenance.source == .demo {
            return "Preview data. Not your health data."
        }
        return "Previously cached data. The latest refresh failed."
    }

    private var readinessRetainedText: String {
        guard let snapshot = model.readiness else { return "No prior snapshot is displayed." }
        return snapshot.provenance.source == .demo
            ? "The visible values remain an explicitly labeled preview fixture."
            : "The visible values are the last acknowledged cached snapshot, not a successful new sync."
    }

    private func physiologySourceDetail(_ snapshot: ReadinessSnapshot) -> String {
        snapshot.provenance.source == .demo ? "Preview fixture" : "WHOOP cloud · cached"
    }

    private var connectionCard: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("WEARABLE FUSION")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.golfMist)
                    Spacer()
                    Button("Details") { model.selectedTab = .settings }
                        .font(.caption.weight(.semibold))
                }
                Text(model.adaptiveSensorPlan.fusedStatusTitle)
                    .font(.subheadline.weight(.bold))
                Text(model.adaptiveSensorPlan.fusedStatusDetail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ConnectionPill(
                            title: "Apple Watch",
                            systemImage: "applewatch",
                            active: WatchSessionReceiver.shared.isPaired
                                || WatchSessionReceiver.shared.isWatchAppInstalled
                                || model.adaptiveSensorPlan.mode == .hybrid
                                || model.adaptiveSensorPlan.mode == .appleWatchOnly
                        )
                        ConnectionPill(
                            title: "WHOOP Motion",
                            systemImage: "gyroscope",
                            active: model.sensorCapabilities.whoop.hasSwingSource
                                || model.adaptiveSensorPlan.mode == .hybrid
                                || model.adaptiveSensorPlan.mode == .whoopOnly
                        )
                        ConnectionPill(title: "iPhone GPS", systemImage: "location.fill", active: isLocationReady)
                        ConnectionPill(title: "WHOOP Cloud", systemImage: "cloud.fill", active: model.dataMode == .live)
                        ConnectionPill(title: "Apple Health", systemImage: "heart.fill", active: model.health.state == .ready)
                        ConnectionPill(title: "WHOOP HR", systemImage: "wave.3.right", active: model.heartRate.hasFreshReading)
                    }
                }
            }
        }
    }

    private var isLocationReady: Bool {
        if case .ready = model.location.state { return true }
        return false
    }

    private func freshnessText(_ date: Date?, stale: Bool) -> String {
        guard let date else { return stale ? "Sync status unavailable" : "Cached sync time unavailable" }
        let prefix = stale ? "Stale · " : "Synced "
        return prefix + date.formatted(.relative(presentation: .named))
    }
}

private extension AppModel.DataMode {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

import Foundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var baseURL = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GolfBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Adaptive wearable mode", systemImage: "point.3.connected.trianglepath.dotted")
                                        .font(.headline)
                                    Spacer()
                                    Text(adaptiveModeBadge)
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(adaptiveModeColor)
                                }
                                Text(model.adaptiveSensorPlan.fusedStatusTitle)
                                    .font(.title3.weight(.bold))
                                Text(model.adaptiveSensorPlan.fusedStatusDetail)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                CapabilityRow(
                                    title: "Apple Watch",
                                    status: model.adaptiveSensorPlan.mode == .hybrid
                                        || model.adaptiveSensorPlan.mode == .appleWatchOnly
                                        ? model.adaptiveSensorPlan.watchContributorStatus
                                        : watchWearableStatus,
                                    detail: model.adaptiveSensorPlan.watchContributorDetail,
                                    symbol: "applewatch",
                                    available: WatchSessionReceiver.shared.isPaired
                                        || WatchSessionReceiver.shared.isWatchAppInstalled
                                        || model.adaptiveSensorPlan.mode == .hybrid
                                        || model.adaptiveSensorPlan.mode == .appleWatchOnly
                                )
                                Picker("Watch wrist", selection: Binding(
                                    get: { model.watchWristMount },
                                    set: { model.setWatchWrist($0) }
                                )) {
                                    ForEach(WatchWristMount.allCases) { mount in
                                        Text(mount.displayName).tag(mount)
                                    }
                                }
                                .pickerStyle(.segmented)
                                Text(model.watchWristMount.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                CapabilityRow(
                                    title: "WHOOP 5",
                                    status: model.adaptiveSensorPlan.whoopContributorStatus,
                                    detail: model.adaptiveSensorPlan.whoopContributorDetail,
                                    symbol: "gyroscope",
                                    available: model.sensorCapabilities.whoop.hasSwingSource
                                        || model.adaptiveSensorPlan.mode == .hybrid
                                        || model.adaptiveSensorPlan.mode == .whoopOnly
                                )
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Today's contributions", systemImage: "square.split.2x1.fill")
                                    .font(.headline)
                                Text(model.wearableContributionBoard.roundFusion.liveScoringCaption)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                Text(model.wearableContributionBoard.roundFusion.delayedMergeCaption)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                ForEach(model.wearableContributionBoard.lines) { line in
                                    CapabilityRow(
                                        title: line.title,
                                        status: line.status,
                                        detail: line.detail,
                                        symbol: contributionSymbol(for: line.id),
                                        available: line.available
                                    )
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Direct WHOOP", systemImage: "wave.3.right.circle.fill")
                                        .font(.headline)
                                    Spacer()
                                    Text(directWhoopBadge)
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(directWhoopColor)
                                }
                                Text(heartRateDetail)
                                    .font(.subheadline.weight(.semibold))
                                Text(model.wearableContributionBoard.heartRateDetail)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                HStack {
                                    Button {
                                        model.heartRate.start()
                                    } label: {
                                        Label("Scan for WHOOP", systemImage: "dot.radiowaves.left.and.right")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.golfLime)
                                    .foregroundStyle(Color.golfInk)
                                    .disabled(
                                        !DualWearableFusion.shouldAllowWhoopBroadcastScan(
                                            for: model.heartRateFusionContext
                                        )
                                    )

                                    if model.heartRate.hasFreshReading {
                                        Button("Disconnect") {
                                            model.heartRate.stop()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Live WHOOP wrist IMU", systemImage: "waveform.path.ecg")
                                        .font(.headline)
                                    Spacer()
                                    Text(model.whoopLiveIMU.imuActive ? "LIVE" : "OFF")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(model.whoopLiveIMU.imuActive ? Color.golfLime : Color.golfMist)
                                }
                                Text(model.whoopLiveIMU.status)
                                    .font(.subheadline.weight(.semibold))
                                Text("WHOOP 5.0 firmware refuses a live IMU flood — Golf will not hang on Arming or treat strap IMU as the primary golf path. Dual maximize uses delayed historical import (Check for WHOOP swings) fused with Watch live swings. HR Broadcast and live IMU cannot share the strap. Close the official WHOOP app first. iPhone GPS remains spatial only.")
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                HStack {
                                    Button {
                                        model.connectWhoopLiveIMU()
                                    } label: {
                                        Label("Connect strap", systemImage: "dot.radiowaves.left.and.right")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.golfLime)
                                    .foregroundStyle(Color.golfInk)
                                    .disabled(model.whoopLiveIMU.sessionBusy || model.whoopLiveIMU.imuActive)

                                    if model.whoopLiveIMU.sessionBusy || model.whoopLiveIMU.bonded || model.whoopLiveIMU.imuActive {
                                        Button("Disconnect") {
                                            model.disconnectWhoopLiveIMU()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("WHOOP 5 motion inbox", systemImage: "tray.and.arrow.down.fill")
                                        .font(.headline)
                                    Spacer()
                                    Text(model.pendingWhoopMotionBatches.isEmpty ? "READY" : "REVIEW")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(model.pendingWhoopMotionBatches.isEmpty ? Color.golfLime : Color.golfSand)
                                }
                                Text(model.pendingWhoopMotionBatches.isEmpty
                                    ? "No protected motion batches are waiting for review."
                                    : "\(model.pendingWhoopMotionBatches.count) protected batch(es) are staged for review or source reconciliation.")
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                if !model.pendingWhoopMotionReviewBatches.isEmpty {
                                    NavigationLink {
                                        WhoopMotionReviewView()
                                    } label: {
                                        Label(
                                            "Review \(model.pendingWhoopMotionReviewBatches.reduce(0) { $0 + $1.undecidedCount }) swing candidates",
                                            systemImage: "checklist"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.golfSand)
                                    .foregroundStyle(Color.golfInk)
                                }
                                Button("Check for WHOOP swings") {
                                    Task { await model.refreshWhoopMotion() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.golfLime)
                                .disabled(!model.hasBridgeToken || model.bridgeBaseURL.isEmpty)
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("WHOOP capability map", systemImage: "list.bullet.rectangle.portrait.fill")
                                    .font(.headline)
                                CapabilityRow(
                                    title: "Live heart rate",
                                    status: model.wearableContributionBoard.heartRateOwner == .none
                                        ? "OFF"
                                        : model.wearableContributionBoard.heartRateOwner.title.uppercased(),
                                    detail: model.wearableContributionBoard.heartRateDetail,
                                    symbol: "heart.fill",
                                    available: model.wearableContributionBoard.heartRateOwner != .none
                                )
                                CapabilityRow(
                                    title: "Recovery · sleep · strain",
                                    status: "CLOUD",
                                    detail: "Available from the official WHOOP API through the private bridge.",
                                    symbol: "cloud.fill",
                                    available: true
                                )
                                CapabilityRow(
                                    title: "Live wrist IMU",
                                    status: model.whoopLiveIMU.imuActive ? "EXPERIMENTAL" : "NOT PRIMARY",
                                    detail: "Unofficial strap IMU is not the WHOOP 5 golf path (firmware refuses Arming flood). Dual maximize uses delayed historical import below. Mutually exclusive with HR Broadcast.",
                                    symbol: "waveform.path.ecg",
                                    available: false
                                )
                                CapabilityRow(
                                    title: "Historical swing motion",
                                    status: model.sensorCapabilities.whoop.hasSwingSource ? "CONFIGURED" : "PILOT SETUP",
                                    detail: "The app can import reviewed WHOOP 5 historical motion after a complete explicit offload. Physical acquisition is not configured by this connection screen, is delayed, and is separate from the public API.",
                                    symbol: "gyroscope",
                                    available: model.sensorCapabilities.whoop.hasSwingSource
                                )
                                CapabilityRow(
                                    title: "WHOOP location",
                                    status: "NO BAND GPS",
                                    detail: "WHOOP 5.0 has no GPS radio. WHOOP swing timestamps can anchor a shot, but geographic A→B yardage requires an explicitly labeled mobile GPS coordinate.",
                                    symbol: "location.slash.fill",
                                    available: false
                                )
                                CapabilityRow(
                                    title: "Post-shot band vibration",
                                    status: "SDK NEEDED",
                                    detail: "The band supports WHOOP-controlled haptics, but the public Developer API does not provide a third-party vibration command. This remains gated on authorized device access.",
                                    symbol: "wave.3.right",
                                    available: false
                                )
                                Divider().overlay(.white.opacity(0.08))
                                HStack(spacing: 16) {
                                    Link("WHOOP API", destination: URL(string: "https://developer.whoop.com/api/")!)
                                    Link(
                                        "HR Broadcast help",
                                        destination: URL(string: "https://support.whoop.com/s/article/Navigating-the-WHOOP-Mobile-App?language=en_US")!
                                    )
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.golfLime)
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("WHOOP 5 sensor", systemImage: "gyroscope")
                                        .font(.headline)
                                    Spacer()
                                    Text(whoop5DiscoveryBadge)
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(whoop5DiscoveryColor)
                                }
                                Text(whoop5DiscoveryDetail)
                                    .font(.subheadline.weight(.semibold))
                                Text("Safe discovery only: the app listens for the WHOOP 5 service but does not connect, write commands, alter its encrypted bond, or interrupt the official WHOOP app.")
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                Button {
                                    model.whoop5Discovery.discover()
                                } label: {
                                    Label("Discover WHOOP 5", systemImage: "dot.radiowaves.left.and.right")
                                }
                                .buttonStyle(.bordered)
                                .tint(.golfLime)
                                .disabled(model.whoop5Discovery.state == .scanning)
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("WHOOP Cloud bridge", systemImage: "lock.shield.fill")
                                        .font(.headline)
                                    Spacer()
                                    statusBadge
                                }
                                Text("WHOOP OAuth credentials and the health database stay on your Mac. This app uses a separate device token over private HTTPS.")
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                TextField("https://mac-name.tailnet.ts.net", text: $baseURL)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .padding(13)
                                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 13))
                                SecureField(model.hasBridgeToken ? "Token saved — leave blank to keep" : "Device token", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .privacySensitive()
                                    .padding(13)
                                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 13))
                                HStack {
                                    Button("Save & test") {
                                        Task {
                                            await model.saveBridge(baseURL: baseURL, token: token)
                                            token = ""
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.golfLime)
                                    .foregroundStyle(Color.golfInk)
                                    Button("Refresh") { Task { await model.refreshReadiness() } }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Round bridge sync", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.headline)
                                    Spacer()
                                    Text(bridgeSyncBadge)
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(bridgeSyncColor)
                                }
                                Text(bridgeSyncDetail)
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                Button("Retry queued rounds") {
                                    Task { await model.retryBridgeUploads() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.golfLime)
                                .disabled(!model.hasBridgeToken || model.bridgeBaseURL.isEmpty)
                            }
                        }

                        if !model.pendingWatchSessions.isEmpty {
                            GolfCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Watch sessions awaiting a round", systemImage: "applewatch.radiowaves.left.and.right")
                                        .font(.headline)
                                    Text("These transfers are protected and intentionally unlinked. Choose the correct round; the app never guesses by date or proximity.")
                                        .font(.caption)
                                        .foregroundStyle(Color.golfMist)
                                    ForEach(model.pendingWatchSessions, id: \.sessionID) { session in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("\(session.swingCount) swings · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.subheadline.weight(.semibold))
                                            if model.rounds.isEmpty {
                                                Text("Finish a round before linking this session.")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.golfSand)
                                            } else {
                                                Menu("Choose round") {
                                                    ForEach(model.rounds) { round in
                                                        Button("\(round.courseName) · \(round.startedAt.formatted(date: .abbreviated, time: .omitted))") {
                                                            Task {
                                                                await model.linkPendingWatchSession(
                                                                    session.sessionID,
                                                                    to: round.id
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .tint(.golfLime)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Optional iPhone services", systemImage: "iphone.gen3")
                                    .font(.headline)
                                Text("Apple Health remains optional. Apple Watch is a first-class live sensor when paired; without it the app uses the best honestly available WHOOP/manual plan.")
                                    .font(.caption)
                                    .foregroundStyle(Color.golfMist)
                                SettingsConnectionRow(
                                    title: "Apple Health export",
                                    detail: healthDetail,
                                    symbol: "heart.fill",
                                    active: model.health.state == .ready,
                                    button: "Enable"
                                ) {
                                    Task { await model.health.requestAuthorization() }
                                }
                                Divider().overlay(.white.opacity(0.08))
                                SettingsConnectionRow(
                                    title: "Background round location",
                                    detail: locationDetail,
                                    symbol: "location.fill",
                                    active: isLocationReady,
                                    button: locationActionLabel
                                ) {
                                    performLocationAction()
                                }
                            }
                        }

                        GolfCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Data promises", systemImage: "checkmark.seal.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.golfLime)
                                PromiseRow(text: "Recovery, sleep and strain: cached WHOOP cloud data")
                                PromiseRow(text: "Live heart rate: direct WHOOP HR Broadcast; the advertised device name is not treated as cryptographic verification")
                                PromiseRow(text: "WHOOP swing motion: live wrist IMU when the strap is connected here, otherwise delayed reviewed historical import; GPS tracking alone is never presented as WHOOP motion")
                                PromiseRow(text: "Shot distance: WHOOP-triggered A→B anchors + explicitly attributed iPhone GPS displacement with uncertainty, not WHOOP GPS or claimed carry")
                                PromiseRow(text: "WHOOP 5 has no built-in GPS; distance is unavailable when the phone coordinate timeline is off")
                                PromiseRow(text: "Apple Watch: first-class live swing/GPS/haptic source; WHOOP-only and Hybrid remain separate persisted modes")
                                PromiseRow(text: "18Birdies: no private scraping or fake two-way sync")
                            }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if baseURL.isEmpty { baseURL = model.bridgeBaseURL }
                model.location.refreshPermissionState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                model.location.refreshPermissionState()
            }
        }
    }

    private var watchWearableStatus: String {
        let receiver = WatchSessionReceiver.shared
        if receiver.isReachable { return "REACHABLE" }
        if receiver.isWatchAppInstalled { return "INSTALLED" }
        if receiver.isPaired { return "PAIRED" }
        return "NOT PAIRED"
    }

    private func contributionSymbol(for id: String) -> String {
        switch id {
        case "watch-live": "applewatch"
        case "whoop-delayed": "gyroscope"
        case "whoop-physio": "cloud.fill"
        case "hr": "heart.fill"
        case "phone-gps": "location.fill"
        case "journal-merge": "book.pages.fill"
        default: "circle.fill"
        }
    }

    private var adaptiveModeBadge: String {
        switch model.adaptiveSensorPlan.operationalState {
        case .ready: "READY"
        case .liveCaptureWithDelayedEnrichment: "DUAL · LIVE+LATER"
        case .delayedPostRoundCapture: "POST-ROUND"
        case .distanceUnavailable: "NO YARDAGE"
        case .unavailable: "ACTION"
        }
    }

    private var adaptiveModeColor: Color {
        model.adaptiveSensorPlan.canCaptureSwingLive ||
            model.adaptiveSensorPlan.canReconstructSwingPostRound
            ? .golfLime
            : .golfSand
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.dataMode {
        case .live:
            Text("LIVE CACHE").foregroundStyle(Color.golfLime)
        case .demo:
            Text("DEMO").foregroundStyle(Color.golfSand)
        case .loading:
            ProgressView().tint(.golfLime)
        case .error:
            Text("ACTION").foregroundStyle(Color.golfSand)
        case .unconfigured:
            Text("NOT SET").foregroundStyle(Color.golfMist)
        }
    }

    private var healthDetail: String {
        switch model.health.state {
        case .notRequested: "Optional workout export is off"
        case .requesting: "Waiting for optional export permission"
        case .ready: "Optional golf-workout export is enabled"
        case .denied: "Export is off; local rounds still work"
        case .unavailable: "Unavailable; local rounds still work"
        case .failed(let message): "Export unavailable: \(message)"
        }
    }

    private var whoop5DiscoveryBadge: String {
        switch model.whoop5Discovery.state {
        case .scanning, .waitingForBluetooth: "SCANNING"
        case .found: "FOUND"
        case .noBandFound: "NOT SEEN"
        case .bluetoothOff: "BLUETOOTH OFF"
        case .unauthorised: "PERMISSION"
        case .unavailable: "UNAVAILABLE"
        case .idle: "NOT CHECKED"
        }
    }

    private var whoop5DiscoveryColor: Color {
        switch model.whoop5Discovery.state {
        case .found: .golfLime
        case .noBandFound, .bluetoothOff, .unauthorised, .unavailable: .golfSand
        default: .golfMist
        }
    }

    private var whoop5DiscoveryDetail: String {
        switch model.whoop5Discovery.state {
        case .found:
            guard let band = model.whoop5Discovery.bands.first else {
                return "WHOOP 5 advertisement observed"
            }
            return "\(band.displayName) · \(band.signalLabel) · \(band.signalStrengthDBM) dBm"
        case .scanning:
            return "Listening passively for a nearby WHOOP 5 advertisement"
        case .waitingForBluetooth:
            return "Waiting for Bluetooth to become ready"
        case .noBandFound:
            return "No WHOOP 5 advertisement was observed in this scan"
        case .bluetoothOff:
            return "Turn Bluetooth on to discover the band"
        case .unauthorised:
            return "Bluetooth permission is required for discovery"
        case .unavailable:
            return "Bluetooth discovery is unavailable on this device"
        case .idle:
            return "Not checked yet · official WHOOP sync remains untouched"
        }
    }

    private var locationDetail: String {
        let precision = model.location.accuracyAuthorization == .reducedAccuracy
            ? " Precise Location is off."
            : ""
        return switch model.location.permissionState {
        case .notRequested:
            "Off. First allow While Using; the app will ask for Always only after a separate tap."
        case .requestingWhenInUse:
            "Waiting for your While Using choice in the iOS permission sheet."
        case .whenInUse:
            "While Using is allowed. Tap Allow Always separately for reliable screen-locked and background rounds.\(precision)"
        case .requestingAlways:
            "Waiting for your separate Always Location choice in the iOS permission sheet."
        case .whenInUseNeedsSettings:
            "While Using only. The in-app Always request was already made; use iOS Settings to repair background access.\(precision)"
        case .always:
            if model.location.accuracyAuthorization == .reducedAccuracy {
                "Always is allowed, but Precise Location is off. Use iOS Settings for usable shot displacement."
            } else if case .ready(let accuracy) = model.location.state {
                "Always + Precise ready · current active-round accuracy ±\(Int(accuracy.rounded())) m."
            } else {
                "Always + Precise ready. GPS starts only while a saved round is active."
            }
        case .denied:
            "Location is denied. Open iOS Settings to enable it; the scorecard still works without GPS."
        case .restricted:
            "Location is restricted by this device or Screen Time and cannot be requested in the app."
        }
    }

    private var isLocationReady: Bool {
        model.location.permissionState == .always
            && model.location.accuracyAuthorization == .fullAccuracy
    }

    private var locationActionLabel: String? {
        if model.location.accuracyAuthorization == .reducedAccuracy,
           model.location.permissionState != .notRequested,
           model.location.permissionState != .requestingWhenInUse {
            return "Open Settings"
        }
        return switch model.location.permissionState {
        case .notRequested: "Allow"
        case .whenInUse: "Allow Always"
        case .whenInUseNeedsSettings, .denied, .restricted: "Open Settings"
        case .requestingWhenInUse, .requestingAlways, .always: nil
        }
    }

    private func performLocationAction() {
        if model.location.accuracyAuthorization == .reducedAccuracy,
           model.location.permissionState != .notRequested,
           model.location.permissionState != .requestingWhenInUse {
            openLocationSettings()
            return
        }
        switch model.location.permissionState {
        case .notRequested:
            model.location.requestWhenInUsePermission()
        case .whenInUse:
            model.location.requestAlwaysPermission()
        case .whenInUseNeedsSettings, .denied, .restricted:
            openLocationSettings()
        case .requestingWhenInUse, .requestingAlways, .always:
            break
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var heartRateDetail: String {
        if model.heartRate.hasFreshReading, let bpm = model.heartRate.heartRateBPM {
            let name = model.heartRate.broadcastName ?? "WHOOP HR Broadcast"
            return "\(bpm) bpm live from \(name)"
        }
        return switch model.heartRate.state {
        case .scanning: "Scanning for a WHOOP Heart Rate broadcast"
        case .connecting(let name): "Connecting to \(name)"
        case .stale:
            model.heartRate.lastObservedAt.map {
                "Signal stale · last sample \($0.formatted(.relative(presentation: .named)))"
            } ?? "Signal stale · waiting for a new sample"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorised: "Bluetooth permission denied"
        case .failed(let message): message
        default: "Not connected · enable HR Broadcast in the WHOOP app"
        }
    }

    private var directWhoopBadge: String {
        if model.heartRate.hasFreshReading { return "LIVE" }
        switch model.heartRate.state {
        case .scanning: return "SCANNING"
        case .connecting: return "CONNECTING"
        case .stale: return "STALE"
        case .failed, .bluetoothOff, .unauthorised: return "ACTION"
        default: return "OFF"
        }
    }

    private var directWhoopColor: Color {
        if model.heartRate.hasFreshReading { return .golfLime }
        switch model.heartRate.state {
        case .stale, .failed, .bluetoothOff, .unauthorised: return .golfSand
        default: return .golfMist
        }
    }

    private var bridgeSyncBadge: String {
        switch model.bridgeSyncState {
        case .unconfigured: "NOT SET"
        case .idle: "READY"
        case .syncing: "SYNCING"
        case .synced: "SYNCED"
        case .queued(let count, _): "QUEUED \(count)"
        case .failed: "ACTION"
        }
    }

    private var bridgeSyncColor: Color {
        switch model.bridgeSyncState {
        case .synced, .idle: .golfLime
        case .syncing: .golfMist
        case .queued, .failed: .golfSand
        case .unconfigured: .golfMist
        }
    }

    private var bridgeSyncDetail: String {
        switch model.bridgeSyncState {
        case .unconfigured:
            "Configure the private HTTPS bridge above."
        case .idle:
            "Complete scorecards will queue locally before upload."
        case .syncing:
            "Uploading queued complete rounds over private HTTPS."
        case .synced(let date):
            "Last acknowledged \(date.formatted(.relative(presentation: .named)))."
        case .queued(let count, let reason):
            "\(count) complete round(s) remain protected on this iPhone. \(reason)"
        case .failed(let reason):
            reason
        }
    }
}

private struct WhoopMotionReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mergeApprovedBatchIDs: Set<String> = []

    var body: some View {
        ZStack {
            GolfBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    GolfCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Human-confirmed WHOOP import", systemImage: "person.badge.shield.checkmark.fill")
                                .font(.headline)
                                .foregroundStyle(Color.golfLime)
                            Text("These are delayed candidates derived from WHOOP 5 historical wrist motion. Accept only real golf shots; reject practice motions and false positives. Your choices are stored separately from the immutable sensor batch.")
                                .font(.caption)
                                .foregroundStyle(Color.golfMist)
                            Text("Wrist rotation is not clubhead path, face angle, ball flight, or carry.")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.golfSand)
                        }
                    }

                    if model.pendingWhoopMotionReviewBatches.isEmpty {
                        ContentUnavailableView(
                            "Review complete",
                            systemImage: "checkmark.seal.fill",
                            description: Text("No protected WHOOP swing candidates need a decision.")
                        )
                        .foregroundStyle(Color.golfMist)
                    } else {
                        ForEach(model.pendingWhoopMotionReviewBatches) { batch in
                            reviewBatch(batch)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("WHOOP swing review")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func reviewBatch(_ batch: PendingWhoopMotionReviewBatch) -> some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(batch.coverage.roundStartedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("\(batch.events.count) candidates · \(batch.undecidedCount) undecided")
                            .font(.caption)
                            .foregroundStyle(Color.golfMist)
                    }
                    Spacer()
                    Text(reviewReasonLabel(batch.reason))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(batch.reason == .crossSourceConflict ? Color.golfSand : Color.golfLime)
                }

                if batch.reason == .crossSourceConflict {
                    Toggle(
                        "Allow explicit merge with existing swing source",
                        isOn: mergeBinding(for: batch.batchID)
                    )
                    .font(.caption.weight(.semibold))
                    .tint(.golfLime)
                    Text("Keep this off unless both sources belong to the same round. Timestamp-near observations can otherwise create false short shot intervals.")
                        .font(.caption2)
                        .foregroundStyle(Color.golfSand)
                }

                ForEach(batch.events) { detail in
                    Divider().overlay(.white.opacity(0.08))
                    reviewEvent(detail, batch: batch)
                }

                if batch.undecidedCount == 0,
                   let decided = batch.events.first(where: { $0.userDecision != nil }),
                   let decision = decided.userDecision {
                    Button(batch.reason == .crossSourceConflict ? "Resolve with both sources" : "Retry protected resolution") {
                        Task {
                            await model.recordWhoopMotionReviewDecision(
                                batchID: batch.batchID,
                                eventID: decided.event.eventID,
                                decision: decision,
                                allowingCrossSourceMerge: mergeApprovedBatchIDs.contains(batch.batchID)
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.golfLime)
                    .foregroundStyle(Color.golfInk)
                    .disabled(
                        batch.reason == .crossSourceConflict
                            && !mergeApprovedBatchIDs.contains(batch.batchID)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func reviewEvent(
        _ detail: PendingWhoopMotionEventDetail,
        batch: PendingWhoopMotionReviewBatch
    ) -> some View {
        let event = detail.event
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(event.observedAt.formatted(date: .omitted, time: .standard))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(Int((event.classification.confidence * 100).rounded()))% detector rank")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.golfMist)
            }

            HStack(spacing: 14) {
                Label(String(format: "%.1f g", event.metrics.peakG), systemImage: "waveform.path.ecg")
                if let tempo = event.metrics.tempoRatio {
                    Label(String(format: "%.2f:1", tempo), systemImage: "metronome.fill")
                }
            }
            .font(.caption.weight(.semibold))

            if let analysis = event.wristAnalysis {
                let pointCount = analysis.orientationTrace?.points.count ?? 0
                Text("WHOOP wrist rotation · \(analysis.quality.status.rawValue) · \(pointCount) trace points")
                    .font(.caption)
                    .foregroundStyle(Color.golfLime)
            } else {
                Text("Phase metrics only · no wrist-rotation trace in this legacy batch")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }

            if !event.classification.reasons.isEmpty {
                Text(event.classification.reasons.map(reviewReasonText).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Color.golfSand)
            }

            if let decision = detail.userDecision {
                Label(
                    decision == .accept ? "Accepted as a golf shot" : "Rejected as not a shot",
                    systemImage: decision == .accept ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(decision == .accept ? Color.golfLime : Color.golfSand)
                .accessibilityLabel(
                    decision == .accept ? "Decision saved: accepted" : "Decision saved: rejected"
                )
            } else {
                HStack {
                    Button {
                        submit(.reject, detail: detail, batch: batch)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.golfSand)

                    Button {
                        submit(.accept, detail: detail, batch: batch)
                    } label: {
                        Label("Accept shot", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.golfLime)
                    .foregroundStyle(Color.golfInk)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func submit(
        _ decision: WhoopMotionUserReviewDecision,
        detail: PendingWhoopMotionEventDetail,
        batch: PendingWhoopMotionReviewBatch
    ) {
        Task {
            await model.recordWhoopMotionReviewDecision(
                batchID: batch.batchID,
                eventID: detail.event.eventID,
                decision: decision,
                allowingCrossSourceMerge: mergeApprovedBatchIDs.contains(batch.batchID)
            )
        }
    }

    private func mergeBinding(for batchID: String) -> Binding<Bool> {
        Binding(
            get: { mergeApprovedBatchIDs.contains(batchID) },
            set: { enabled in
                if enabled { mergeApprovedBatchIDs.insert(batchID) }
                else { mergeApprovedBatchIDs.remove(batchID) }
            }
        )
    }

    private func reviewReasonLabel(_ reason: WhoopMotionReviewPendingReason) -> String {
        switch reason {
        case .crossSourceConflict: "SOURCE CHECK"
        case .needsReview: "REVIEW"
        case .roundUnavailable: "ROUND NEEDED"
        case .locationUnavailable: "GPS NEEDED"
        }
    }

    private func reviewReasonText(_ reason: WhoopMotionReviewReason) -> String {
        switch reason {
        case .lowDetectorConfidence: "Low detector rank"
        case .coverageGapNearEvent: "Sensor coverage gap nearby"
        case .duplicateCandidate: "Possible duplicate motion"
        case .roundBoundary: "Near round boundary"
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let status: String
    let detail: String
    let symbol: String
    let available: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(available ? Color.golfLime : Color.golfSand)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(status)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(available ? Color.golfLime : Color.golfSand)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsConnectionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let active: Bool
    let button: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Color.golfLime : Color.golfMist)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Color.golfMist)
            }
            Spacer()
            if let button {
                Button(button, action: action)
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(.golfLime)
            }
        }
        .padding(.vertical, 13)
    }
}

private struct PromiseRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.golfLime)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}

import Combine
import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable {
        case overview
        case today
        case round
        case trends
        case settings
    }

    enum DataMode: Equatable {
        case unconfigured
        case loading
        case live
        case demo
        case error(String)
    }

    enum BridgeSyncState: Equatable {
        case unconfigured
        case idle
        case syncing
        case synced(Date)
        case queued(Int, String)
        case failed(String)
    }

    enum CourseLookupState: Equatable {
        case idle
        case locating
        case searching
        case suggested(GolfCourseCandidate)
        case ambiguous([GolfCourseCandidate])
        case confirmed(GolfCourseCandidate)
        case noneNearby
        case failed(String)
    }

    @Published var selectedTab: Tab = .overview
    @Published private(set) var dataMode: DataMode = .unconfigured
    @Published private(set) var readiness: ReadinessSnapshot?
    @Published private(set) var rounds: [GolfRound] = []
    @Published private(set) var activeRound: GolfRound?
    @Published private(set) var roundTrackingActive = false
    @Published private(set) var isFinishingRound = false
    @Published var notice: String?
    @Published private(set) var bridgeBaseURL = ""
    @Published private(set) var hasBridgeToken = false
    @Published private(set) var lastWatchSession: ReceivedWatchSession?
    @Published private(set) var bridgeSyncState: BridgeSyncState = .unconfigured
    @Published private(set) var pendingWatchSessions: [PendingWatchSession] = []
    @Published private(set) var pendingWhoopMotionBatches: [PendingWhoopMotionBatch] = []
    @Published private(set) var pendingWhoopMotionReviewBatches: [PendingWhoopMotionReviewBatch] = []
    @Published private(set) var courseLookupState: CourseLookupState = .idle
    @Published var watchWristMount: WatchWristMount = WatchWristMount.load()
    /// Active club for the next verified swing (golfer-selected).
    @Published var activeClub: GolfClubKind = GolfClubKind.load()
    /// Authorized F/M/B green targets for the active hole. Facility search
    /// (`GolfCourseLocator`) never sets this — it identifies a course only.
    @Published private(set) var activeHoleGreenTargets: GolfHoleGreenTargets?

    let location = LocationRoundService()
    let heartRate = WhoopHeartRateProvider()
    let whoop5Discovery = Whoop5DiscoveryScanner()
    let whoopLiveIMU = WhoopBLEManager()
    let imuMotion = IMUMotionManager()
    let health = HealthAuthorizationService()

    private let roundStore: RoundFileStore
    private let bridgeOutbox: BridgeRoundOutbox
    private let watchSessionImporter: WatchSessionImporter
    private let whoopMotionImporter: WhoopMotionImportService
    private let courseLocator: GolfCourseLocator
    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private var bootstrapped = false
    private var swingAssignmentUpdateInFlight = false
    private var cancellables: Set<AnyCancellable> = []

    var sensorCapabilities: SensorCapabilitySnapshot {
        let receiver = WatchSessionReceiver.shared
        let currentRoundID = activeRound?.id
        let hasActiveWatchSession = currentRoundID.map { roundID in
            receiver.recoveredSessions.contains { $0.roundID == roundID }
        } ?? false
        let hasWHOOPMotionEvidence = !pendingWhoopMotionBatches.isEmpty ||
            !pendingWhoopMotionReviewBatches.isEmpty ||
            rounds.contains { round in
                round.swings.contains { $0.provenance.source == .whoopMotion }
            }
        let iphoneLocation: IPhoneLocationCapability
        switch location.permissionState {
        case .whenInUse, .whenInUseNeedsSettings, .always, .requestingAlways:
            iphoneLocation = location.accuracyAuthorization == .fullAccuracy
                ? .precise
                : .approximate
        case .notRequested, .requestingWhenInUse, .denied, .restricted:
            iphoneLocation = .unavailable
        }
        return SensorCapabilitySnapshot(
            whoop: WhoopSensorCapabilities(
                historicalCaptureConfigured: !bridgeBaseURL.isEmpty && hasBridgeToken,
                historicalMotionAvailable: hasWHOOPMotionEvidence,
                authorizedLiveMotionProviderAvailable: whoopLiveIMU.imuActive,
                authorizedBandHapticProviderAvailable: false
            ),
            appleWatch: AppleWatchSensorCapabilities(
                isPaired: receiver.isPaired,
                isAppInstalled: receiver.isWatchAppInstalled,
                isReachable: receiver.isReachable,
                activeSessionSourceAvailable: hasActiveWatchSession,
                // The target is configured to request synchronized Watch GPS.
                // Individual fixes still fail closed during import when
                // permission, freshness, or accuracy is insufficient.
                synchronizedLocationAvailable: receiver.isPaired && receiver.isWatchAppInstalled
            ),
            iphoneLocation: iphoneLocation
        )
    }

    var adaptiveSensorPlan: AdaptiveSensorPlan {
        SensorModeCoordinator.plan(for: sensorCapabilities)
    }

    /// Dual-wearable admission: both Apple Watch and WHOOP must be proven.
    var dualWearableAdmission: DualWearableRequirement.Outcome {
        DualWearableRequirement.evaluate(
            capabilities: sensorCapabilities,
            hasReadinessSnapshot: readiness != nil
        )
    }

    var canStartDualWearableRound: Bool {
        dualWearableAdmission.allowsStart
    }

    var recommendedRoundRecorder: RoundRecorder {
        // Product rule: new rounds are Hybrid only when both wearables admit.
        if canStartDualWearableRound {
            return .hybrid
        }
        // Diagnostics still expose the adaptive recommendation, but startRound
        // refuses anything other than a satisfied dual gate.
        let watchReady = WatchSessionReceiver.shared.isPaired
            || WatchSessionReceiver.shared.isWatchAppInstalled
        if watchReady {
            return adaptiveSensorPlan.mode == .hybrid ? .hybrid : .appleWatch
        }
        switch adaptiveSensorPlan.mode {
        case .whoopOnly: return .whoop5
        case .appleWatchOnly: return .appleWatch
        case .hybrid: return .hybrid
        case .unavailable: return .iphone
        }
    }

    func setWatchWrist(_ mount: WatchWristMount) {
        WatchWristMount.save(mount)
        watchWristMount = mount
        publishWatchLiveFace()
    }

    func setActiveClub(_ club: GolfClubKind) {
        GolfClubKind.save(club)
        activeClub = club
        publishWatchLiveFace()
    }

    /// Supplies licensed green F/M/B for targeting overlay. Pass nil to clear.
    /// Does not affect swing-to-swing stroke yards.
    func applyHoleGreenTargets(_ targets: GolfHoleGreenTargets?) {
        if let targets, targets.isValid {
            activeHoleGreenTargets = targets
        } else {
            activeHoleGreenTargets = nil
        }
        publishWatchLiveFace()
    }

    /// Publishes Watch live face: stroke yards from the swing shot chain
    /// (phone GPS A→B), optional F/M/B targeting overlay when geometry exists.
    /// `GolfCourseLocator` confirms a facility only — never green pins or
    /// stroke yards.
    func publishWatchLiveFace() {
        let hole = activeRound?.currentHole
        let matchedTargets: GolfHoleGreenTargets?
        if let targets = activeHoleGreenTargets, targets.isValid,
           hole == nil || targets.holeNumber == hole {
            matchedTargets = targets
        } else {
            matchedTargets = nil
        }
        let face = PhoneYardageBridge.makeLiveFace(
            holeNumber: hole,
            courseName: activeRound?.courseName,
            swings: activeRound?.swings ?? [],
            wristMount: watchWristMount,
            phoneFix: location.currentShotFix(maximumAge: 30),
            greenTargets: matchedTargets
        )
        WatchSessionReceiver.shared.publishLiveFace(face)
    }

    func sensorPlan(for recorder: RoundRecorder) -> AdaptiveSensorPlan {
        guard let mode = recorder.adaptiveSensorMode else {
            return SensorModeCoordinator.plan(
                for: SensorCapabilitySnapshot(),
                mode: .unavailable
            )
        }
        return SensorModeCoordinator.plan(for: sensorCapabilities, mode: mode)
    }

    init(
        roundStore: RoundFileStore = RoundFileStore(),
        bridgeOutbox: BridgeRoundOutbox = BridgeRoundOutbox(),
        watchSessionImporter: WatchSessionImporter? = nil,
        courseLocator: GolfCourseLocator = GolfCourseLocator(),
        keychain: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.roundStore = roundStore
        self.bridgeOutbox = bridgeOutbox
        self.watchSessionImporter = watchSessionImporter
            ?? WatchSessionImporter(roundStore: roundStore)
        self.whoopMotionImporter = WhoopMotionImportService(
            roundStore: roundStore,
            locationCorrelator: location
        )
        self.courseLocator = courseLocator
        self.keychain = keychain
        self.defaults = defaults
        if let paired = (try? keychain.pairedBridgeConfiguration()) ?? nil {
            bridgeBaseURL = paired.baseURL.absoluteString
            hasBridgeToken = true
        } else {
            bridgeBaseURL = defaults.string(forKey: "bridge-base-url") ?? ""
            hasBridgeToken = (try? keychain.token())?.isEmpty == false
        }
        bridgeSyncState = bridgeBaseURL.isEmpty || !hasBridgeToken ? .unconfigured : .idle

        Publishers.MergeMany([
            location.objectWillChange.eraseToAnyPublisher(),
            heartRate.objectWillChange.eraseToAnyPublisher(),
            whoop5Discovery.objectWillChange.eraseToAnyPublisher(),
            whoopLiveIMU.objectWillChange.eraseToAnyPublisher(),
            imuMotion.objectWillChange.eraseToAnyPublisher(),
            health.objectWillChange.eraseToAnyPublisher(),
            WatchSessionReceiver.shared.objectWillChange.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)

        whoopLiveIMU.onSample = { [weak self] sample in
            self?.imuMotion.ingest(sample)
        }
        whoopLiveIMU.onLivePathFailed = { [weak self] message in
            self?.notice = message
        }
        imuMotion.onSwing = { [weak self] metrics in
            Task { await self?.recordLiveWhoopSwing(metrics) }
        }

        location.$latestFix
            .compactMap { $0 }
            .sink { [weak self] fix in
                guard let self else { return }
                if self.courseLookupState == .locating {
                    Task { await self.lookupCourse(near: fix) }
                }
                // Refresh F/M/B targeting overlay while a round is live.
                // Stroke yards come from the swing chain, not this fix alone.
                if self.activeRound != nil {
                    self.publishWatchLiveFace()
                }
            }
            .store(in: &cancellables)

        WatchSessionReceiver.shared.$lastReceived
            .compactMap { $0 }
            .sink { [weak self] received in
                guard let self else { return }
                self.lastWatchSession = received
                Task { await self.importWatchSession(received) }
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        let watchReceiver = WatchSessionReceiver.shared
        let watchRecovery = watchReceiver.recoverStoredSessions()
        watchReceiver.activate()
        watchWristMount = WatchWristMount.load()
        publishWatchLiveFace()
        do {
            let snapshot = try await roundStore.snapshot()
            rounds = snapshot.finishedRounds
            activeRound = snapshot.activeDraft
            roundTrackingActive = false
            if let draft = snapshot.activeDraft,
               draft.recordingDevice == .appleWatch || draft.recordingDevice == .hybrid {
                watchReceiver.publishActiveRound(
                    roundID: draft.id,
                    courseName: draft.courseName,
                    startedAt: draft.startedAt
                )
            } else {
                watchReceiver.clearActiveRound()
            }
            if let draft = snapshot.activeDraft {
                let older = snapshot.additionalDraftCount == 0
                    ? ""
                    : " \(snapshot.additionalDraftCount) older draft(s) remain safely stored."
                notice = "Restored the draft at \(draft.courseName). Open Round and resume sensors when ready.\(older)"
            }
        } catch {
            notice = "Saved rounds could not be loaded: \(error.localizedDescription)"
        }

        for recovered in watchRecovery.sessions {
            lastWatchSession = recovered
            await importWatchSession(recovered)
        }
        if !watchRecovery.failures.isEmpty {
            notice = "Recovered \(watchRecovery.sessions.count) Watch session(s); \(watchRecovery.failures.count) protected file(s) need attention."
        }

        await reloadPendingWatchSessions()
        await reloadPendingWhoopMotionBatches()
        await reloadPendingWhoopMotionReviews()

        if bridgeBaseURL.isEmpty || !hasBridgeToken {
            #if DEBUG
            readiness = DemoFixtures.readiness
            dataMode = .demo
            #else
            readiness = nil
            dataMode = .unconfigured
            #endif
            return
        }
        await retryBridgeUploads(showSuccessNotice: false)
        await refreshReadiness()
        await refreshWhoopMotion(showNotReadyNotice: false)
    }

    func refreshReadiness() async {
        dataMode = .loading
        do {
            guard let config = configuredBridgeConfiguration() else {
                throw WhoopBridgeError.invalidConfiguration
            }
            let response = try await WhoopBridgeClient(configuration: config).day(Self.localDate())
            readiness = .from(response)
            dataMode = .live
        } catch {
            dataMode = .error(error.localizedDescription)
        }
    }

    func saveBridge(baseURL: String, token: String) async {
        do {
            let pairedToken = try keychain.pairedBridgeConfiguration()?.bearerToken
            let legacyToken = try keychain.token() ?? ""
            let existingToken = pairedToken ?? legacyToken
            let effectiveToken = token.isEmpty ? existingToken : token
            let configuration = try BridgeConfiguration(
                baseURLString: baseURL,
                bearerToken: effectiveToken
            )
            try keychain.setPairedBridgeConfiguration(configuration)
            try keychain.setToken(effectiveToken)
            let normalizedURL = configuration.baseURL.absoluteString
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            defaults.set(normalizedURL, forKey: "bridge-base-url")
            bridgeBaseURL = normalizedURL
            hasBridgeToken = true
            bridgeSyncState = .idle
            await retryBridgeUploads(showSuccessNotice: false)
            await refreshReadiness()
        } catch {
            notice = error.localizedDescription
        }
    }

    func startRound(
        courseName: String,
        holeCount: GolfHoleCount = .eighteen,
        recordingDevice: RoundRecorder? = nil
    ) async {
        guard activeRound == nil else { return }

        let admission = dualWearableAdmission
        guard admission.allowsStart else {
            notice = DualWearableRequirement.startBlockedNotice(for: admission)
            return
        }

        // Dual maximize only — refuse Watch-only / WHOOP-only / manual starts.
        let selectedRecorder: RoundRecorder = .hybrid
        _ = recordingDevice // Callers may pass a preference; product gate overrides.

        let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmedCourse: String?
        if case .confirmed(let candidate) = courseLookupState {
            confirmedCourse = candidate.name
        } else {
            confirmedCourse = nil
        }
        let round = GolfRound(
            courseName: trimmed.isEmpty ? confirmedCourse ?? "Golf Round" : trimmed,
            holeCount: holeCount,
            recordingDevice: selectedRecorder
        )
        do {
            try await roundStore.save(round)
            activeRound = round
            activeHoleGreenTargets = nil
        } catch {
            notice = "The round could not start because its protected draft was not saved: \(error.localizedDescription)"
            return
        }

        WatchSessionReceiver.shared.publishActiveRound(
            roundID: round.id,
            courseName: round.courseName,
            startedAt: round.startedAt
        )
        publishWatchLiveFace()
        await beginSensorTracking(roundID: round.id)
        notice = "Hybrid round saved. Apple Watch owns live path, tempo, HR, and counted shots; WHOOP owns delayed wrist enrich + readiness/recovery/strain. Club and ball-start tendency are journaled per stroke."
    }

    /// Begins key-free nearby-course discovery. Permission is requested only by
    /// iOS, and a MapKit result remains a suggestion until the golfer confirms
    /// it. A facility result never implies per-hole geometry.
    func requestCourseSuggestion() async {
        guard activeRound == nil else { return }
        switch courseLookupState {
        case .locating, .searching, .suggested, .ambiguous, .confirmed:
            return
        case .idle, .noneNearby, .failed:
            break
        }

        if let fix = location.currentShotFix(maximumAge: 60) {
            await lookupCourse(near: fix)
        } else {
            courseLookupState = .locating
            location.requestPermission()
        }
    }

    func confirmCourse(_ candidate: GolfCourseCandidate) {
        let allowed: Bool
        switch courseLookupState {
        case .suggested(let current):
            allowed = current.id == candidate.id
        case .ambiguous(let candidates):
            allowed = candidates.contains { $0.id == candidate.id }
        case .confirmed(let current):
            allowed = current.id == candidate.id
        default:
            allowed = false
        }
        guard allowed else { return }
        courseLookupState = .confirmed(candidate.userConfirmed())
    }

    func retryCourseSuggestion() async {
        await courseLocator.cancelSearch()
        courseLookupState = .idle
        await requestCourseSuggestion()
    }

    private func lookupCourse(near fix: LocationFix) async {
        guard activeRound == nil else { return }
        courseLookupState = .searching
        do {
            switch try await courseLocator.suggestCourse(near: fix) {
            case .suggested(let candidate):
                courseLookupState = .suggested(candidate)
            case .ambiguous(let candidates):
                courseLookupState = .ambiguous(candidates)
            case .noneNearby:
                courseLookupState = .noneNearby
            }
        } catch is CancellationError {
            if activeRound == nil { courseLookupState = .idle }
        } catch {
            courseLookupState = .failed(error.localizedDescription)
        }
    }

    func resumeRoundTracking() async {
        guard let round = activeRound, !roundTrackingActive else { return }
        if round.recordingDevice == .appleWatch || round.recordingDevice == .hybrid {
            WatchSessionReceiver.shared.publishActiveRound(
                roundID: round.id,
                courseName: round.courseName,
                startedAt: round.startedAt
            )
        }
        location.resumeRoundTracking(roundID: round.id)
        applyHeartRateFusionPolicy()
        roundTrackingActive = true
        notice = "Round sensors resumed. The existing protected GPS timeline was reopened without truncation."
    }

    private func beginSensorTracking(roundID: UUID) async {
        location.startRoundTracking(roundID: roundID)
        applyHeartRateFusionPolicy()
        roundTrackingActive = true
        // Apple Health is an explicit optional export, never a prerequisite for
        // a round. Starting a round must not prompt for or depend on an Apple
        // service; the user can opt in from Connections before finishing.
    }

    /// D19 dual-wearable-fusion: Watch owns HR when it is the live golf wearable;
    /// WHOOP Broadcast only when Watch is not the HR source; never with live IMU.
    var heartRateFusionContext: DualWearableFusion.HeartRateContext {
        DualWearableFusion.HeartRateContext(
            plan: adaptiveSensorPlan,
            watchAppReady: WatchSessionReceiver.shared.isPaired
                && WatchSessionReceiver.shared.isWatchAppInstalled,
            whoopLiveIMUActive: whoopLiveIMU.imuActive || whoopLiveIMU.sessionBusy
        )
    }

    var wearableContributionBoard: DualWearableFusion.ContributionBoard {
        DualWearableFusion.contributionsToday(
            for: DualWearableFusion.ContributionContext(
                plan: adaptiveSensorPlan,
                watchAppReady: heartRateFusionContext.watchAppReady,
                whoopLiveIMUActive: heartRateFusionContext.whoopLiveIMUActive,
                whoopMotionConfigured: sensorCapabilities.whoop.hasSwingSource,
                whoopCloudReady: dataMode == .live || hasBridgeToken,
                hasReadinessSnapshot: readiness != nil,
                iphoneGPSReady: location.permissionState == .always
                    && location.accuracyAuthorization == .fullAccuracy
            )
        )
    }

    func applyHeartRateFusionPolicy() {
        let context = heartRateFusionContext
        if DualWearableFusion.shouldAutoStartWhoopBroadcast(for: context) {
            heartRate.start()
        } else {
            switch heartRate.state {
            case .idle, .bluetoothOff, .unauthorised, .failed:
                break
            default:
                heartRate.stop()
            }
        }
    }

    func recordShot() async {
        guard var round = activeRound, !isFinishingRound else { return }
        guard let fix = location.currentShotFix() else {
            notice = "Waiting for an iPhone GPS fix under 25 m accuracy."
            return
        }

        if let previousIndex = round.shots.indices.last,
           round.shots[previousIndex].hole == round.currentHole,
           let yards = ShotDistanceCalculator.displacementYards(
               from: round.shots[previousIndex].location,
               to: fix
           ) {
            round.shots[previousIndex].distanceToNextYards = yards
            round.shots[previousIndex].distanceUncertaintyYards = ShotDistanceCalculator
                .uncertaintyYards(first: round.shots[previousIndex].location, second: fix)
        }
        round.shots.append(
            ShotRecord(
                sequence: round.shots.count + 1,
                hole: round.currentHole,
                capturedAt: .now,
                location: fix
            )
        )
        await persistDraft(
            round,
            previous: activeRound,
            failureMessage: "The shot location could not be saved"
        )
    }

    func changeStrokes(by delta: Int) async {
        guard var round = activeRound, !isFinishingRound else { return }
        guard round.adjustCurrentStrokes(by: delta) else { return }
        await persistDraft(
            round,
            previous: activeRound,
            failureMessage: "The stroke entry could not be saved"
        )
    }

    func changePar(by delta: Int) async {
        guard var round = activeRound, !isFinishingRound else { return }
        guard round.adjustCurrentPar(by: delta) else { return }
        await persistDraft(
            round,
            previous: activeRound,
            failureMessage: "The par change could not be saved"
        )
    }

    /// Live WHOOP 5 wrist IMU swing. Phone GPS may attach a spatial A→B
    /// estimate; phone IMU is never the swing source (D13).
    func recordLiveWhoopSwing(_ detected: SwingMetrics) async {
        guard var round = activeRound, !isFinishingRound else { return }
        let observedAt = Date()
        let gpsFix = location.currentShotFix(maximumAge: 15)
        let locationObservation = gpsFix.map { fix in
            SwingLocationObservation(
                latitude: fix.latitude,
                longitude: fix.longitude,
                altitudeMeters: fix.altitudeMeters,
                horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
                capturedAt: fix.capturedAt,
                provenance: fix.provenance
            )
        }
        var inputSources: [MetricSource] = [.whoopMotion]
        if locationObservation != nil { inputSources.append(.iphoneGPS) }
        let metrics = GolfSwingMetrics(
            capturedAt: observedAt,
            peakG: detected.peakG,
            backswingSeconds: detected.backswingS,
            downswingSeconds: detected.downswingS,
            tempoRatio: detected.tempoRatio,
            heartRateBPM: whoopLiveIMU.heartRate ?? heartRate.heartRateBPM,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: observedAt,
                quality: .estimated,
                algorithmVersion: "whoop-live-imu-v1",
                inputSources: inputSources
            ),
            location: locationObservation,
            locationCorrelationMethod: locationObservation == nil ? nil : .nearestTimelineFix
        )
        round.swings.append(metrics)
        round.finalizeWHOOPTriggeredShotIntervals()
        await persistDraft(
            round,
            previous: activeRound,
            failureMessage: "The WHOOP swing could not be saved"
        )
        notice = "WHOOP swing \(round.swings.count) · hole \(round.currentHole) · iPhone GPS is spatial only"
    }

    func connectWhoopLiveIMU() {
        // Bond-fight rule: Broadcast and live IMU cannot share the strap.
        switch heartRate.state {
        case .idle, .bluetoothOff, .unauthorised, .failed:
            break
        default:
            heartRate.stop()
        }
        notice = "Close the official WHOOP app, then put the strap in pairing mode (blue LEDs). WHOOP 5 will not hang on Arming — delayed import remains the golf path."
        whoopLiveIMU.scanAndConnect()
    }

    func disconnectWhoopLiveIMU() {
        whoopLiveIMU.disconnect()
        imuMotion.reset()
        applyHeartRateFusionPolicy()
        notice = "Live WHOOP wrist IMU disconnected. Delayed reconstruction remains available."
    }

    func moveHole(by delta: Int, at date: Date = .now) async {
        guard var round = activeRound, !isFinishingRound else { return }
        guard round.moveHole(by: delta, at: date) else { return }
        await persistDraft(
            round,
            previous: activeRound,
            failureMessage: "The current hole could not be saved"
        )
    }

    /// Persists a post-round manual assignment (or explicit unassignment) as
    /// an append-only audit entry, then reloads finished history from the same
    /// atomic file store used by delayed WHOOP imports.
    func setSwingHoleCorrection(
        roundID: UUID,
        swingID: UUID,
        hole: Int?,
        at date: Date = .now
    ) async {
        guard !swingAssignmentUpdateInFlight else {
            notice = "Finish the current swing assignment before making another correction."
            return
        }
        swingAssignmentUpdateInFlight = true
        defer { swingAssignmentUpdateInFlight = false }

        do {
            guard var round = try await roundStore.rounds().first(where: { $0.id == roundID }),
                  round.isFinished else {
                notice = "That finished round is no longer available for swing correction."
                return
            }
            guard round.setSwingHoleCorrection(swingID: swingID, hole: hole, at: date) else {
                notice = "The swing or hole assignment was invalid, or that correction is already saved."
                return
            }

            try await roundStore.save(round)
            do {
                rounds = try await roundStore.finishedRounds()
            } catch {
                // The atomic write succeeded. Keep the visible copy current
                // even if the subsequent directory reload is interrupted.
                if let index = rounds.firstIndex(where: { $0.id == roundID }) {
                    rounds[index] = round
                }
                notice = "The correction was saved, but round history could not reload: \(error.localizedDescription)"
                return
            }

            if let hole {
                notice = "Accepted swing observation manually assigned to hole \(hole)."
            } else {
                notice = "Accepted swing observation manually left unassigned."
            }
        } catch {
            notice = "The swing assignment could not be saved: \(error.localizedDescription)"
        }
    }

    private func persistDraft(
        _ round: GolfRound,
        previous: GolfRound?,
        failureMessage: String
    ) async {
        // Publish first so rapid scorecard taps compose from the newest state;
        // RoundFileStore serializes their atomic writes in the same order.
        activeRound = round
        do {
            try await roundStore.save(round)
            publishWatchLiveFace()
        } catch {
            if activeRound == round {
                activeRound = previous
            }
            notice = "\(failureMessage): \(error.localizedDescription)"
        }
    }

    func finishRound() async {
        guard var round = activeRound, !isFinishingRound else { return }
        isFinishingRound = true
        defer { isFinishingRound = false }
        round.markFinished()

        do {
            try await roundStore.save(round)
        } catch {
            notice = "The round is still an active draft because final save failed: \(error.localizedDescription)"
            return
        }

        // Only a successful atomic final write is allowed to clear resumable
        // phone UI or the Watch's exact round identity.
        WatchSessionReceiver.shared.clearActiveRound()
        activeRound = nil
        activeHoleGreenTargets = nil
        roundTrackingActive = false
        location.stopRoundTracking(roundID: round.id)
        heartRate.stop()
        do {
            rounds = try await roundStore.finishedRounds()
        } catch {
            notice = "The round finished safely, but history could not reload: \(error.localizedDescription)"
        }

        let scoreNote = round.isScoreComplete
            ? ""
            : " The incomplete scorecard is saved but excluded from score analysis."
        let bridgeNote = await enqueueFinishedRoundForBridge(round)
        let motionNote = await requestWhoopMotion(for: round)
        if round.recordingDevice == .appleWatch || round.recordingDevice == .hybrid {
            notice = "Round saved locally. The iPhone did not create a duplicate Health workout; finish the linked Apple Watch session to save its workout and route.\(scoreNote)\(bridgeNote)\(motionNote)"
        } else if health.state == .ready {
            do {
                try await health.saveWorkout(for: round)
                notice = "Round saved locally and to Apple Health.\(scoreNote)\(bridgeNote)\(motionNote)"
            } catch {
                notice = "Round saved locally. Apple Health save needs attention: \(error.localizedDescription).\(scoreNote)\(bridgeNote)\(motionNote)"
            }
        } else {
            notice = "Round saved locally. Apple Health was not connected and was not required.\(scoreNote)\(bridgeNote)\(motionNote)"
        }
        selectedTab = .today
    }

    func retryBridgeUploads(showSuccessNotice: Bool = true) async {
        guard let client = configuredBridgeClient() else {
            bridgeSyncState = .unconfigured
            if showSuccessNotice {
                notice = "Configure the private HTTPS bridge before retrying round sync."
            }
            return
        }

        bridgeSyncState = .syncing
        do {
            let result = try await bridgeOutbox.flush(using: client)
            if result.remaining == 0 {
                bridgeSyncState = .synced(.now)
                if showSuccessNotice {
                    notice = result.delivered == 0
                        ? "No rounds are waiting to sync."
                        : "Synced \(result.delivered) round(s) to the private bridge."
                }
            } else {
                bridgeSyncState = .queued(result.remaining, "Waiting for the private bridge")
            }
        } catch BridgeRoundOutboxError.flushAlreadyRunning {
            return
        } catch {
            let pending = (try? await bridgeOutbox.pending().count) ?? 0
            bridgeSyncState = pending > 0
                ? .queued(pending, error.localizedDescription)
                : .failed(error.localizedDescription)
            if showSuccessNotice {
                notice = "Round sync is queued safely: \(error.localizedDescription)"
            }
        }
    }

    /// Pulls any immutable delayed WHOOP 5 batch for a finished round and
    /// imports accepted swing events only after the protected inbox owns the
    /// exact response bytes. Repeated calls are idempotent.
    func refreshWhoopMotion(showNotReadyNotice: Bool = true) async {
        guard let client = configuredBridgeClient() else {
            if showNotReadyNotice {
                notice = "Configure the private HTTPS bridge before checking WHOOP 5 motion."
            }
            return
        }

        var importedAny = false
        for round in rounds where round.isFinished &&
            (round.recordingDevice == .whoop5 || round.recordingDevice == .hybrid) {
            do {
                let etagKey = motionETagKey(for: round.id)
                let cachedETag = defaults.string(forKey: etagKey)
                let savedETag = cachedETag.flatMap {
                    WhoopBridgeClient.isValidStrongMotionETag($0) ? $0 : nil
                }
                if cachedETag != nil, savedETag == nil {
                    // A legacy or corrupted cache value must never wedge this
                    // round before a request is sent. Drop it and perform one
                    // unconditional pull; a valid 200 response will replace it.
                    defaults.removeObject(forKey: etagKey)
                }
                switch try await client.pullWhoopMotion(
                    roundID: round.id,
                    ifNoneMatch: savedETag
                ) {
                case .pending, .notModified:
                    continue
                case .available(_, let payload, let etag):
                    let outcome = await whoopMotionImporter.importBatch(
                        payload,
                        allowingCrossSourceMerge: round.recordingDevice == .hybrid
                    )
                    switch outcome {
                    case .imported(_, _, let swingCount, let needsReviewCount):
                        persistMotionETag(etag, forKey: etagKey, outcome: outcome)
                        importedAny = true
                        notice = "Imported \(swingCount) WHOOP 5 swing(s). \(needsReviewCount) observation(s) remain for review."
                    case .duplicate:
                        persistMotionETag(etag, forKey: etagKey, outcome: outcome)
                        continue
                    case .stagedCrossSourceConflict:
                        persistMotionETag(etag, forKey: etagKey, outcome: outcome)
                        notice = "WHOOP 5 motion is safe in the inbox, but this round already has another swing source and needs reconciliation."
                    case .stagedNeedsReview(_, _, let count):
                        persistMotionETag(etag, forKey: etagKey, outcome: outcome)
                        notice = "WHOOP 5 motion is safe in the inbox; \(count) observation(s) need review before import."
                    case .stagedRoundUnavailable:
                        // Keep this response eligible for a later pull. The
                        // protected inbox already owns the exact bytes, and a
                        // subsequently restored local round can make the same
                        // deterministic batch importable.
                        defaults.removeObject(forKey: etagKey)
                        notice = "WHOOP 5 motion is safe in the inbox, but its local round is unavailable."
                    case .stagedLocationUnavailable:
                        // A delayed GPS journal flush can make correlation
                        // succeed on the next foreground refresh. Persisting
                        // the ETag here would turn that retry into a permanent
                        // 304 and strand a recoverable batch.
                        defaults.removeObject(forKey: etagKey)
                        notice = "WHOOP 5 motion is safe in the inbox, but the GPS timeline could not be correlated yet."
                    case .invalid(_, let reason):
                        notice = "WHOOP 5 motion was rejected: \(reason)"
                    }
                }
            } catch WhoopBridgeError.motionRequestNotFound {
                _ = await requestWhoopMotion(for: round)
                continue
            } catch {
                if showNotReadyNotice {
                    notice = "WHOOP 5 motion check is waiting on the private bridge: \(error.localizedDescription)"
                }
            }
        }

        if importedAny {
            do {
                rounds = try await roundStore.finishedRounds()
            } catch {
                notice = "WHOOP 5 motion imported, but round history could not reload: \(error.localizedDescription)"
            }
        } else if showNotReadyNotice, notice == nil {
            notice = "No new WHOOP 5 historical swing batch is ready yet."
        }
        await reloadPendingWhoopMotionBatches()
        await reloadPendingWhoopMotionReviews()
    }

    func recordWhoopMotionReviewDecision(
        batchID: String,
        eventID: String,
        decision: WhoopMotionUserReviewDecision,
        allowingCrossSourceMerge: Bool = false
    ) async {
        let reviewedRoundID = pendingWhoopMotionReviewBatches
            .first(where: { $0.batchID == batchID })?.roundID
        let isHybridRound = reviewedRoundID.flatMap { roundID in
            rounds.first(where: { $0.id == roundID })?.recordingDevice
        } == .hybrid
        let outcome = await whoopMotionImporter.recordReviewDecision(
            batchID: batchID,
            eventID: eventID,
            decision: decision,
            allowingCrossSourceMerge: allowingCrossSourceMerge || isHybridRound
        )
        switch outcome {
        case .recorded(_, _, let remainingDecisionCount):
            notice = "Review saved. \(remainingDecisionCount) WHOOP swing candidate(s) still need a decision."
        case .resolved(_, _, let acceptedReviewCount, let rejectedReviewCount):
            do {
                rounds = try await roundStore.finishedRounds()
                notice = "WHOOP review complete: \(acceptedReviewCount) accepted, \(rejectedReviewCount) rejected. GPS shot intervals were rebuilt."
            } catch {
                notice = "WHOOP review resolved, but round history could not reload: \(error.localizedDescription)"
            }
        case .stagedCrossSourceConflict:
            notice = "Every decision is saved. Confirm the source merge to combine WHOOP observations with existing manual or Apple Watch data."
        case .stagedRoundUnavailable:
            notice = "Every decision is saved, but the protected local round is not currently available."
        case .stagedLocationUnavailable:
            notice = "Every decision is saved, but a quality-gated iPhone GPS fix is not available yet. Retry after the location journal finishes."
        case .duplicate:
            notice = "That WHOOP review decision was already saved."
        case .invalid(_, _, let reason):
            notice = "WHOOP review was not changed: \(reason)"
        }
        await reloadPendingWhoopMotionBatches()
        await reloadPendingWhoopMotionReviews()
    }

    private func requestWhoopMotion(for round: GolfRound) async -> String {
        guard round.recordingDevice == .whoop5 || round.recordingDevice == .hybrid,
              let endedAt = round.endedAt,
              let client = configuredBridgeClient() else {
            return (round.recordingDevice == .whoop5 || round.recordingDevice == .hybrid)
                ? " WHOOP motion request is waiting for private bridge setup."
                : ""
        }
        do {
            let request = try WhoopMotionRequest(
                roundID: round.id,
                startedAt: round.startedAt,
                endedAt: endedAt,
                requestedAt: .now
            )
            try await client.requestWhoopMotion(request)
            return " WHOOP 5 historical motion requested."
        } catch {
            return " WHOOP 5 motion request needs attention: \(error.localizedDescription)."
        }
    }

    func linkPendingWatchSession(_ sessionID: String, to roundID: UUID) async {
        let outcome = await watchSessionImporter.linkPendingSession(
            sessionID: sessionID,
            to: roundID
        )
        await handleWatchImport(outcome)
    }

    private func enqueueFinishedRoundForBridge(_ round: GolfRound) async -> String {
        guard round.isFinished, round.isScoreComplete else { return "" }

        do {
            let payload = try BridgeRoundPayload(round: round)
            _ = try await bridgeOutbox.enqueue(payload)
            let pending = try await bridgeOutbox.pending().count
            bridgeSyncState = .queued(pending, "Saved locally; waiting for bridge acknowledgement")
            if configuredBridgeClient() != nil {
                await retryBridgeUploads(showSuccessNotice: false)
            }
            switch bridgeSyncState {
            case .synced:
                return " Bridge sync acknowledged."
            case .queued(let count, _):
                return " \(count) round(s) safely queued for bridge sync."
            case .failed(let reason):
                return " Bridge queue needs attention: \(reason)."
            default:
                return ""
            }
        } catch {
            bridgeSyncState = .failed(error.localizedDescription)
            return " Bridge queue needs attention: \(error.localizedDescription)."
        }
    }

    private func configuredBridgeClient() -> WhoopBridgeClient? {
        guard let configuration = configuredBridgeConfiguration() else { return nil }
        return WhoopBridgeClient(configuration: configuration)
    }

    private func configuredBridgeConfiguration() -> BridgeConfiguration? {
        if let paired = (try? keychain.pairedBridgeConfiguration()) ?? nil {
            return paired
        }
        guard !bridgeBaseURL.isEmpty,
              hasBridgeToken,
              let token = (try? keychain.token()) ?? nil else { return nil }
        return try? BridgeConfiguration(
            baseURLString: bridgeBaseURL,
            bearerToken: token
        )
    }

    private func importWatchSession(_ received: ReceivedWatchSession) async {
        let outcome = await watchSessionImporter.importSession(received)
        await handleWatchImport(outcome)
    }

    private func handleWatchImport(_ outcome: WatchSessionImportOutcome) async {
        switch outcome {
        case .imported(let sessionID, let roundID, let swingCount):
            do {
                let snapshot = try await roundStore.snapshot()
                rounds = snapshot.finishedRounds
                if activeRound?.id == roundID {
                    let allRounds = try await roundStore.rounds()
                    activeRound = allRounds.first { $0.id == roundID }
                }
                notice = "Imported \(swingCount) Apple Watch swing(s) from \(sessionID)."
            } catch {
                notice = "Watch data imported, but the round view could not reload: \(error.localizedDescription)"
            }
        case .pendingUserLink(let sessionID):
            notice = "Apple Watch session \(sessionID) is safe on this iPhone. Choose its round in Connections."
        case .duplicate:
            break
        case .rangeStored(let sessionID, let swingCount):
            notice = "Stored range session \(sessionID) with \(swingCount) swing(s)."
        case .invalid(_, let reason):
            notice = "Apple Watch session could not be imported: \(reason)"
        }
        await reloadPendingWatchSessions()
    }

    private func reloadPendingWatchSessions() async {
        do {
            pendingWatchSessions = try await watchSessionImporter.pendingSessions()
        } catch {
            notice = "Pending Watch sessions could not be loaded: \(error.localizedDescription)"
        }
    }

    private func reloadPendingWhoopMotionBatches() async {
        do {
            pendingWhoopMotionBatches = try await whoopMotionImporter.pendingBatches()
        } catch {
            notice = "Pending WHOOP 5 motion batches could not be loaded: \(error.localizedDescription)"
        }
    }

    private func reloadPendingWhoopMotionReviews() async {
        do {
            pendingWhoopMotionReviewBatches = try await whoopMotionImporter.pendingReviewBatches()
        } catch {
            notice = "Pending WHOOP 5 review details could not be loaded: \(error.localizedDescription)"
        }
    }

    private func motionETagKey(for roundID: UUID) -> String {
        "whoop-motion-etag-\(roundID.uuidString.lowercased())"
    }

    private func persistMotionETag(
        _ etag: String,
        forKey key: String,
        outcome: WhoopMotionImportOutcome
    ) {
        if Self.isTerminalMotionImportOutcome(outcome) {
            defaults.set(etag, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    nonisolated static func isTerminalMotionImportOutcome(_ outcome: WhoopMotionImportOutcome) -> Bool {
        return switch outcome {
        case .imported, .duplicate, .stagedCrossSourceConflict, .stagedNeedsReview:
            true
        case .stagedRoundUnavailable, .stagedLocationUnavailable, .invalid:
            false
        }
    }

    private static func localDate(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

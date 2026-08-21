import Foundation

/// The app's adaptive sensor operating mode. `unavailable` is deliberately a
/// real state: a polished interface must not claim one of the three requested
/// modes when no swing source is actually configured or observable.
///
/// D19 (2026-08-21) dual maximize — does not delete D15 or silently rewrite D18:
/// Apple Watch (Series) and WHOOP 5.0 are **co-equal contributors**. When both
/// swing sources are proven, the plan is `.hybrid`: maximize live Watch path /
/// tempo / HR / haptics **and** delayed WHOOP wrist analysis / physiology.
/// One counted shot identity still anchors on the Watch timestamp so fusion
/// cannot double the scorecard — that is anti-double-count mechanics, not
/// Watch-exclusive product framing. WHOOP 5 live `TOGGLE_IMU` / Arming is
/// never the primary golf path; delayed historical import remains the WHOOP
/// motion contribution.
enum AdaptiveSensorMode: String, Codable, CaseIterable, Hashable, Sendable {
    case whoopOnly
    case appleWatchOnly
    case hybrid
    case unavailable
}

/// WHOOP 5 capabilities that the app can prove at the moment it makes a plan.
///
/// WHOOP 5 has no built-in GPS. Historical motion is delayed, and neither live
/// raw IMU nor arbitrary band haptics are part of the public developer API.
/// The two `authorized...` flags are seams for a future written provider SDK;
/// production code must leave them false until that provider exists.
struct WhoopSensorCapabilities: Codable, Hashable, Sendable {
    let historicalCaptureConfigured: Bool
    let historicalMotionAvailable: Bool
    let authorizedLiveMotionProviderAvailable: Bool
    let authorizedBandHapticProviderAvailable: Bool

    init(
        historicalCaptureConfigured: Bool = false,
        historicalMotionAvailable: Bool = false,
        authorizedLiveMotionProviderAvailable: Bool = false,
        authorizedBandHapticProviderAvailable: Bool = false
    ) {
        self.historicalCaptureConfigured = historicalCaptureConfigured
        self.historicalMotionAvailable = historicalMotionAvailable
        self.authorizedLiveMotionProviderAvailable = authorizedLiveMotionProviderAvailable
        self.authorizedBandHapticProviderAvailable = authorizedBandHapticProviderAvailable
    }

    var hasSwingSource: Bool {
        historicalCaptureConfigured || historicalMotionAvailable ||
            authorizedLiveMotionProviderAvailable
    }

    var canCaptureLive: Bool { authorizedLiveMotionProviderAvailable }
    var canReconstructPostRound: Bool {
        historicalCaptureConfigured || historicalMotionAvailable
    }
}

/// Apple Watch capability is split by what each WCSession signal actually
/// proves. Reachability affects immediate phone/watch messaging, but a paired,
/// installed Watch app can record an independent workout while unreachable and
/// transfer its durable session later.
struct AppleWatchSensorCapabilities: Codable, Hashable, Sendable {
    let isPaired: Bool
    let isAppInstalled: Bool
    let isReachable: Bool
    /// A durable session for the active round is already available to import.
    let activeSessionSourceAvailable: Bool
    /// The Watch is authorized/configured to capture a synchronized location
    /// with each swing, or the active session proves such a source exists.
    let synchronizedLocationAvailable: Bool

    init(
        isPaired: Bool = false,
        isAppInstalled: Bool = false,
        isReachable: Bool = false,
        activeSessionSourceAvailable: Bool = false,
        synchronizedLocationAvailable: Bool = false
    ) {
        self.isPaired = isPaired
        self.isAppInstalled = isAppInstalled
        self.isReachable = isReachable
        self.activeSessionSourceAvailable = activeSessionSourceAvailable
        self.synchronizedLocationAvailable = synchronizedLocationAvailable
    }

    /// The Watch app can record locally even when WCSession is not currently
    /// reachable. Reachability is not a proxy for sensor availability.
    var canCaptureLive: Bool { isPaired && isAppInstalled }
    var hasSwingSource: Bool { canCaptureLive || activeSessionSourceAvailable }
}

enum IPhoneLocationCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case unavailable
    case approximate
    case precise

    var isAvailable: Bool { self != .unavailable }
}

struct SensorCapabilitySnapshot: Codable, Hashable, Sendable {
    let whoop: WhoopSensorCapabilities
    let appleWatch: AppleWatchSensorCapabilities
    let iphoneLocation: IPhoneLocationCapability

    init(
        whoop: WhoopSensorCapabilities = WhoopSensorCapabilities(),
        appleWatch: AppleWatchSensorCapabilities = AppleWatchSensorCapabilities(),
        iphoneLocation: IPhoneLocationCapability = .unavailable
    ) {
        self.whoop = whoop
        self.appleWatch = appleWatch
        self.iphoneLocation = iphoneLocation
    }
}

enum SwingCapturePlan: String, Codable, Hashable, Sendable {
    case whoopAuthorizedLiveMotion
    case whoopHistoricalMotion
    case appleWatchMotion
    /// D19 dual maximize: Watch supplies the live counted event; delayed WHOOP
    /// wrist analysis fuses in after conservative cross-source reconciliation
    /// without becoming a second shot.
    case appleWatchMotionWithWhoopEnrichment
    case none
}

enum ShotSpatialProvider: String, Codable, Hashable, Sendable {
    case appleWatchGPS
    case iphoneGPS
    case unavailable
}

enum ShotConfirmationHapticRoute: String, Codable, Hashable, Sendable {
    case appleWatchLocal
    case iphone
    case whoopBandAuthorizedProvider
    case unavailable
}

enum ShotConfirmationTiming: String, Codable, Hashable, Sendable {
    case immediateAtLiveDetection
    case delayedAtHistoricalImport
    case unavailable
}

enum SensorModeOperationalState: String, Codable, Hashable, Sendable {
    case ready
    case liveCaptureWithDelayedEnrichment
    case delayedPostRoundCapture
    case distanceUnavailable
    case unavailable
}

enum SensorModeConstraint: String, Codable, CaseIterable, Hashable, Sendable {
    case whoopHasNoBuiltInGPS
    case whoopHistoricalMotionPending
    case whoopLiveRawMotionUnavailable
    case whoopBandHapticUnavailable
    case watchNotReachable
    case watchSynchronizedLocationUnavailable
    case iphoneLocationUnavailable
    case approximateIPhoneLocation
    case noSwingSensorAvailable
}

struct AdaptiveSensorPlan: Codable, Hashable, Sendable {
    let mode: AdaptiveSensorMode
    let operationalState: SensorModeOperationalState
    let swingCapture: SwingCapturePlan
    /// Source whose timestamp becomes the canonical shot anchor (anti-double-count).
    let canonicalSwingSource: MetricSource?
    let spatialProvider: ShotSpatialProvider
    let hapticRoute: ShotConfirmationHapticRoute
    let hapticTiming: ShotConfirmationTiming
    let canCaptureSwingLive: Bool
    let canReconstructSwingPostRound: Bool
    let canMeasureShotDistance: Bool
    let constraints: [SensorModeConstraint]

    /// D19: both wearables contribute when hybrid — not Watch-exclusive UI.
    var isDualMaximize: Bool { mode == .hybrid }

    /// Shared Settings / Today title for the adaptive wearable card.
    var fusedStatusTitle: String {
        switch mode {
        case .hybrid:
            "Dual maximize · Watch + WHOOP"
        case .appleWatchOnly:
            "Apple Watch · live swing automation"
        case .whoopOnly:
            canCaptureSwingLive
                ? "WHOOP-only · authorized live motion"
                : "WHOOP-only · delayed swing reconstruction"
        case .unavailable:
            "No wearable motion source is proven"
        }
    }

    /// Shared Settings / Today detail for fused contributor roles.
    var fusedStatusDetail: String {
        switch mode {
        case .hybrid:
            "Apple Watch and WHOOP 5 are co-equal contributors. Watch: live path, tempo, HR, and on-wrist confirmation. WHOOP: delayed wrist analysis and physiology after import. One counted shot per fused event—WHOOP never doubles the scorecard. Live WHOOP IMU / Arming is not the golf path."
        case .appleWatchOnly:
            "The Watch supplies each live swing, synchronized position, and confirmation haptic—even when live messaging is temporarily unreachable. Add WHOOP delayed import to unlock dual maximize."
        case .whoopOnly:
            "WHOOP supplies delayed wrist analytics (and physiology). iPhone GPS is position only because the band has no GPS. Pair an Apple Watch to dual-maximize live path guidance with WHOOP enrichment."
        case .unavailable:
            "The scorecard and manual GPS fallback still work, but the app will not label them as an automatic wearable swing."
        }
    }

    var watchContributorStatus: String {
        switch mode {
        case .hybrid, .appleWatchOnly:
            if canCaptureSwingLive { return "LIVE" }
            if canReconstructSwingPostRound { return "POST-ROUND" }
            return "STANDBY"
        case .whoopOnly, .unavailable:
            return "NOT IN PLAN"
        }
    }

    var whoopContributorStatus: String {
        switch mode {
        case .hybrid:
            if constraints.contains(.whoopHistoricalMotionPending) { return "FUSED · PENDING" }
            if canReconstructSwingPostRound { return "FUSED · READY" }
            return "FUSED · SETUP"
        case .whoopOnly:
            if canCaptureSwingLive { return "LIVE" }
            if canReconstructSwingPostRound { return "POST-ROUND" }
            return "SETUP NEEDED"
        case .appleWatchOnly, .unavailable:
            return "NOT IN PLAN"
        }
    }

    var whoopContributorDetail: String {
        switch mode {
        case .hybrid:
            "Co-equal delayed contributor: six-axis wrist analysis and physiology fuse into Watch-timed shots after Check for WHOOP swings. Not a second scorecard row. No live Arming path."
        case .whoopOnly:
            canCaptureSwingLive
                ? "Authorized live motion provider is configured. Prefer delayed historical import on WHOOP 5 firmware."
                : "Delayed six-axis wrist analysis and physiology; no band GPS or public haptic command."
        case .appleWatchOnly:
            "Configure WHOOP delayed import (bridge + Check for WHOOP swings) to dual-maximize with the Watch."
        case .unavailable:
            "WHOOP delayed import remains available once the private bridge and motion inbox are configured."
        }
    }

    var watchContributorDetail: String {
        switch mode {
        case .hybrid:
            "Co-equal live contributor: path cue, tempo, HR, and confirmation haptic. Phone GPS remains yardage / facility context."
        case .appleWatchOnly:
            "Live path, tempo, and HR. Phone GPS is yardage; Watch owns on-wrist guidance."
        case .whoopOnly, .unavailable:
            "Pair and install the Watch companion to contribute live path guidance alongside WHOOP."
        }
    }
}

/// Pure capability-to-mode policy. It consumes facts collected by Bluetooth,
/// WatchConnectivity, the protected WHOOP inbox, and location authorization;
/// it performs no discovery and never upgrades a missing capability itself.
///
/// Mode selection (D15 contract, D19 dual maximize):
/// 1. Watch + WHOOP → `.hybrid` — co-equal contributors; maximize both.
///    Watch anchors the counted live event; uniquely matched delayed WHOOP
///    fuses without adding shots. No live WHOOP Arming as primary.
/// 2. Watch only → `.appleWatchOnly` (invite WHOOP delayed for dual maximize)
/// 3. WHOOP only → `.whoopOnly` — delayed historical by default; live WHOOP
///    motion only when an authorized provider flag is explicitly true
/// 4. Neither → `.unavailable` (never invent a mode).
enum SensorModeCoordinator {
    static func plan(for capabilities: SensorCapabilitySnapshot) -> AdaptiveSensorPlan {
        let hasWhoop = capabilities.whoop.hasSwingSource
        let hasWatch = capabilities.appleWatch.hasSwingSource

        // Both proven → dual maximize (hybrid). Single-source modes only when
        // the other wearable has no swing source.
        switch (hasWhoop, hasWatch) {
        case (true, true):
            return hybridPlan(for: capabilities)
        case (false, true):
            return watchOnlyPlan(for: capabilities)
        case (true, false):
            return whoopOnlyPlan(for: capabilities)
        case (false, false):
            return AdaptiveSensorPlan(
                mode: .unavailable,
                operationalState: .unavailable,
                swingCapture: .none,
                canonicalSwingSource: nil,
                spatialProvider: .unavailable,
                hapticRoute: .unavailable,
                hapticTiming: .unavailable,
                canCaptureSwingLive: false,
                canReconstructSwingPostRound: false,
                canMeasureShotDistance: false,
                constraints: [.noSwingSensorAvailable]
            )
        }
    }

    /// Re-evaluates the mode persisted at round start without silently
    /// switching sensor ownership when connectivity changes mid-round.
    static func plan(
        for capabilities: SensorCapabilitySnapshot,
        mode: AdaptiveSensorMode
    ) -> AdaptiveSensorPlan {
        switch mode {
        case .whoopOnly:
            guard capabilities.whoop.hasSwingSource else {
                return unavailablePlan(constraint: .noSwingSensorAvailable)
            }
            return whoopOnlyPlan(for: capabilities)
        case .appleWatchOnly:
            guard capabilities.appleWatch.hasSwingSource else {
                return unavailablePlan(constraint: .noSwingSensorAvailable)
            }
            return watchOnlyPlan(for: capabilities)
        case .hybrid:
            guard capabilities.whoop.hasSwingSource,
                  capabilities.appleWatch.hasSwingSource else {
                return unavailablePlan(constraint: .noSwingSensorAvailable)
            }
            return hybridPlan(for: capabilities)
        case .unavailable:
            return unavailablePlan(constraint: .noSwingSensorAvailable)
        }
    }

    private static func unavailablePlan(
        constraint: SensorModeConstraint
    ) -> AdaptiveSensorPlan {
        AdaptiveSensorPlan(
            mode: .unavailable,
            operationalState: .unavailable,
            swingCapture: .none,
            canonicalSwingSource: nil,
            spatialProvider: .unavailable,
            hapticRoute: .unavailable,
            hapticTiming: .unavailable,
            canCaptureSwingLive: false,
            canReconstructSwingPostRound: false,
            canMeasureShotDistance: false,
            constraints: [constraint]
        )
    }

    private static func whoopOnlyPlan(
        for capabilities: SensorCapabilitySnapshot
    ) -> AdaptiveSensorPlan {
        let live = capabilities.whoop.canCaptureLive
        let postRound = capabilities.whoop.canReconstructPostRound
        let spatial: ShotSpatialProvider = capabilities.iphoneLocation.isAvailable
            ? .iphoneGPS
            : .unavailable
        let hapticRoute: ShotConfirmationHapticRoute
        if live && capabilities.whoop.authorizedBandHapticProviderAvailable {
            hapticRoute = .whoopBandAuthorizedProvider
        } else {
            hapticRoute = .iphone
        }
        let hapticTiming: ShotConfirmationTiming = live
            ? .immediateAtLiveDetection
            : .delayedAtHistoricalImport
        var constraints: [SensorModeConstraint] = [.whoopHasNoBuiltInGPS]
        if !live { constraints.append(.whoopLiveRawMotionUnavailable) }
        if !capabilities.whoop.historicalMotionAvailable && postRound {
            constraints.append(.whoopHistoricalMotionPending)
        }
        if !capabilities.whoop.authorizedBandHapticProviderAvailable {
            constraints.append(.whoopBandHapticUnavailable)
        }
        appendIPhoneLocationConstraints(capabilities.iphoneLocation, to: &constraints)

        let state: SensorModeOperationalState
        if spatial == .unavailable {
            state = .distanceUnavailable
        } else if live {
            state = .ready
        } else {
            state = .delayedPostRoundCapture
        }

        return AdaptiveSensorPlan(
            mode: .whoopOnly,
            operationalState: state,
            swingCapture: live ? .whoopAuthorizedLiveMotion : .whoopHistoricalMotion,
            canonicalSwingSource: .whoopMotion,
            spatialProvider: spatial,
            hapticRoute: hapticRoute,
            hapticTiming: hapticTiming,
            canCaptureSwingLive: live,
            canReconstructSwingPostRound: postRound,
            canMeasureShotDistance: spatial != .unavailable && (live || postRound),
            constraints: constraints
        )
    }

    private static func watchOnlyPlan(
        for capabilities: SensorCapabilitySnapshot
    ) -> AdaptiveSensorPlan {
        let live = capabilities.appleWatch.canCaptureLive
        // Watch-only means Watch-owned motion *and* Watch-owned synchronized
        // location. Phone GPS is a valid hybrid/WHOOP utility, but silently
        // substituting it here would misstate this mode's independence.
        let spatial: ShotSpatialProvider = capabilities.appleWatch.synchronizedLocationAvailable
            ? .appleWatchGPS
            : .unavailable
        let postRound = capabilities.appleWatch.activeSessionSourceAvailable
        var constraints: [SensorModeConstraint] = []
        if !capabilities.appleWatch.isReachable && live {
            constraints.append(.watchNotReachable)
        }
        if spatial != .appleWatchGPS {
            constraints.append(.watchSynchronizedLocationUnavailable)
        }

        let state: SensorModeOperationalState
        if spatial == .unavailable {
            state = .distanceUnavailable
        } else if live {
            state = .ready
        } else {
            state = .delayedPostRoundCapture
        }

        return AdaptiveSensorPlan(
            mode: .appleWatchOnly,
            operationalState: state,
            swingCapture: .appleWatchMotion,
            canonicalSwingSource: .appleWatch,
            spatialProvider: spatial,
            hapticRoute: live ? .appleWatchLocal : .iphone,
            hapticTiming: live ? .immediateAtLiveDetection : .delayedAtHistoricalImport,
            canCaptureSwingLive: live,
            canReconstructSwingPostRound: postRound,
            canMeasureShotDistance: spatial != .unavailable && (live || postRound),
            constraints: constraints
        )
    }

    private static func hybridPlan(
        for capabilities: SensorCapabilitySnapshot
    ) -> AdaptiveSensorPlan {
        let watchLive = capabilities.appleWatch.canCaptureLive
        let watchPostRound = capabilities.appleWatch.activeSessionSourceAvailable
        let whoopLive = capabilities.whoop.canCaptureLive
        let whoopPostRound = capabilities.whoop.canReconstructPostRound
        let spatial = spatialProviderForWatch(capabilities)
        var constraints: [SensorModeConstraint] = [.whoopHasNoBuiltInGPS]
        // D19 dual maximize: both contribute. Shot UUID/timestamp still anchors
        // on Watch so fusion cannot double-count; WHOOP delayed wrist analysis
        // is a co-equal fused observation, not a second shot. Even if a WHOOP
        // live provider flag is true, hybrid does not make Arming the golf path.
        if !whoopLive { constraints.append(.whoopLiveRawMotionUnavailable) }
        if !capabilities.whoop.historicalMotionAvailable && whoopPostRound {
            constraints.append(.whoopHistoricalMotionPending)
        }
        if !capabilities.whoop.authorizedBandHapticProviderAvailable {
            constraints.append(.whoopBandHapticUnavailable)
        }
        if !capabilities.appleWatch.isReachable && watchLive {
            constraints.append(.watchNotReachable)
        }
        if spatial != .appleWatchGPS {
            constraints.append(.watchSynchronizedLocationUnavailable)
            appendIPhoneLocationConstraints(capabilities.iphoneLocation, to: &constraints)
        }

        let state: SensorModeOperationalState
        if spatial == .unavailable {
            state = .distanceUnavailable
        } else if watchLive && whoopPostRound && !capabilities.whoop.historicalMotionAvailable {
            state = .liveCaptureWithDelayedEnrichment
        } else if watchLive {
            state = .ready
        } else {
            state = .delayedPostRoundCapture
        }

        return AdaptiveSensorPlan(
            mode: .hybrid,
            operationalState: state,
            swingCapture: .appleWatchMotionWithWhoopEnrichment,
            canonicalSwingSource: .appleWatch,
            spatialProvider: spatial,
            hapticRoute: watchLive ? .appleWatchLocal : .iphone,
            hapticTiming: watchLive ? .immediateAtLiveDetection : .delayedAtHistoricalImport,
            canCaptureSwingLive: watchLive,
            canReconstructSwingPostRound: watchPostRound || whoopPostRound || whoopLive,
            canMeasureShotDistance: spatial != .unavailable &&
                (watchLive || watchPostRound || whoopLive || whoopPostRound),
            constraints: constraints
        )
    }

    private static func spatialProviderForWatch(
        _ capabilities: SensorCapabilitySnapshot
    ) -> ShotSpatialProvider {
        if capabilities.appleWatch.synchronizedLocationAvailable {
            return .appleWatchGPS
        }
        if capabilities.iphoneLocation.isAvailable {
            return .iphoneGPS
        }
        return .unavailable
    }

    private static func appendIPhoneLocationConstraints(
        _ capability: IPhoneLocationCapability,
        to constraints: inout [SensorModeConstraint]
    ) {
        switch capability {
        case .unavailable:
            constraints.append(.iphoneLocationUnavailable)
        case .approximate:
            constraints.append(.approximateIPhoneLocation)
        case .precise:
            break
        }
    }
}

enum HybridSwingResolution: String, Codable, Hashable, Sendable {
    /// One Watch event is canonical and one uniquely matched WHOOP event is a
    /// supplemental analytics observation, not a second shot.
    case watchCanonicalWithWhoopEnrichment
    /// A Watch event remains a valid live shot while a delayed WHOOP match is
    /// absent. Re-running reconciliation after import retains the Watch UUID.
    case watchCanonicalAwaitingWhoop
}

enum HybridSwingReviewReason: String, Codable, Hashable, Sendable {
    case unsupportedSource
    case duplicateIdentity
    case invalidTimestamp
    case subsecondSameSourceConflict
    case ambiguousCrossSourceMatch
    case unmatchedWhoopCandidate
}

struct HybridSwingReviewItem: Codable, Hashable, Sendable {
    let reason: HybridSwingReviewReason
    let candidates: [GolfSwingMetrics]

    var candidateIDs: [UUID] { candidates.map(\.id) }
}

struct ReconciledHybridSwing: Codable, Hashable, Sendable {
    static let fusionAlgorithmVersion = "watch-whoop-swing-reconciliation-v1"

    let watchObservation: GolfSwingMetrics
    let whoopEnrichment: GolfSwingMetrics?
    let resolution: HybridSwingResolution
    /// Absolute delta between Watch and WHOOP event times. Nil means WHOOP has
    /// not been attached, not that the timestamps were identical.
    let timestampDeltaSeconds: Double?

    var canonicalID: UUID { watchObservation.id }
    var canonicalCapturedAt: Date { watchObservation.capturedAt }
    var attachedWristAnalysis: WhoopMotionWristAnalysis? {
        whoopEnrichment?.wristAnalysis
    }

    /// Materializes exactly one shot-timeline observation. Watch retains the
    /// identity, live timestamp, synchronized location, and path coaching.
    /// WHOOP supplies wrist analytics / tempo when paired. Any old interval is
    /// cleared so the caller recomputes A→B only after reconciliation.
    var materializedObservation: GolfSwingMetrics {
        guard let whoopEnrichment else {
            return GolfSwingMetrics(
                id: watchObservation.id,
                capturedAt: watchObservation.capturedAt,
                peakG: watchObservation.peakG,
                backswingSeconds: watchObservation.backswingSeconds,
                downswingSeconds: watchObservation.downswingSeconds,
                tempoRatio: watchObservation.tempoRatio,
                heartRateBPM: watchObservation.heartRateBPM,
                detectionConfidence: watchObservation.detectionConfidence,
                wristAnalysis: watchObservation.wristAnalysis,
                pathYawDegrees: watchObservation.pathYawDegrees,
                pathClass: watchObservation.pathClass,
                pathScore: watchObservation.pathScore,
                pathExplanation: watchObservation.pathExplanation,
                improverTip: watchObservation.improverTip,
                club: watchObservation.club,
                ballStartBias: watchObservation.ballStartBias,
                attackFeel: watchObservation.attackFeel,
                ballStartDetail: watchObservation.ballStartDetail,
                provenance: watchObservation.provenance,
                location: watchObservation.location,
                locationCorrelationMethod: watchObservation.locationCorrelationMethod,
                shotInterval: nil
            )
        }

        let location = watchObservation.location ?? whoopEnrichment.location
        let locationMethod = watchObservation.location != nil
            ? watchObservation.locationCorrelationMethod
            : whoopEnrichment.locationCorrelationMethod
        var inputSources: [MetricSource] = [.appleWatch, .whoopMotion]
        inputSources.append(contentsOf: watchObservation.provenance.inputSources)
        inputSources.append(contentsOf: whoopEnrichment.provenance.inputSources)
        if let location {
            inputSources.append(location.provenance.source)
            inputSources.append(contentsOf: location.provenance.inputSources)
        }
        inputSources = inputSources.reduce(into: []) { result, source in
            if !result.contains(source) { result.append(source) }
        }

        return GolfSwingMetrics(
            id: watchObservation.id,
            capturedAt: watchObservation.capturedAt,
            peakG: whoopEnrichment.peakG,
            backswingSeconds: whoopEnrichment.backswingSeconds ?? watchObservation.backswingSeconds,
            downswingSeconds: whoopEnrichment.downswingSeconds ?? watchObservation.downswingSeconds,
            tempoRatio: whoopEnrichment.tempoRatio ?? watchObservation.tempoRatio,
            heartRateBPM: whoopEnrichment.heartRateBPM ?? watchObservation.heartRateBPM,
            detectionConfidence: whoopEnrichment.detectionConfidence ??
                watchObservation.detectionConfidence,
            wristAnalysis: whoopEnrichment.wristAnalysis,
            pathYawDegrees: watchObservation.pathYawDegrees ?? whoopEnrichment.pathYawDegrees,
            pathClass: watchObservation.pathClass ?? whoopEnrichment.pathClass,
            pathScore: watchObservation.pathScore ?? whoopEnrichment.pathScore,
            pathExplanation: watchObservation.pathExplanation ?? whoopEnrichment.pathExplanation,
            improverTip: watchObservation.improverTip ?? whoopEnrichment.improverTip,
            club: watchObservation.club ?? whoopEnrichment.club,
            ballStartBias: watchObservation.ballStartBias ?? whoopEnrichment.ballStartBias,
            attackFeel: watchObservation.attackFeel ?? whoopEnrichment.attackFeel,
            ballStartDetail: watchObservation.ballStartDetail ?? whoopEnrichment.ballStartDetail,
            provenance: DataProvenance(
                source: .derived,
                observedAt: watchObservation.capturedAt,
                receivedAt: max(
                    watchObservation.provenance.receivedAt,
                    whoopEnrichment.provenance.receivedAt
                ),
                quality: .estimated,
                algorithmVersion: Self.fusionAlgorithmVersion,
                inputSources: inputSources
            ),
            location: location,
            locationCorrelationMethod: locationMethod,
            shotInterval: nil
        )
    }
}

struct HybridSwingReconciliationResult: Codable, Hashable, Sendable {
    let reconciled: [ReconciledHybridSwing]
    let review: [HybridSwingReviewItem]

    /// One element per counted shot. WHOOP attachments never increase this
    /// count, and all intervals are nil until the post-reconciliation A→B pass.
    var canonicalSwings: [GolfSwingMetrics] {
        reconciled.map(\.materializedObservation)
    }
}

/// Conservative cross-source association for hybrid mode.
///
/// Location never participates in matching: it cannot prove that two motion
/// events are the same swing. A cross-source pair is accepted only when it is
/// the sole candidate inside the timestamp window on both sides. Same-source
/// events closer than a plausible shot cadence are staged together instead of
/// silently creating a tiny A→B interval.
enum HybridSwingReconciler {
    static let maximumPairingDeltaSeconds: TimeInterval = 1.5
    static let minimumSameSourceShotSeparationSeconds: TimeInterval = 1.5

    static func reconcile(_ observations: [GolfSwingMetrics]) -> HybridSwingReconciliationResult {
        var review: [HybridSwingReviewItem] = []
        var eligible = observations

        let unsupported = eligible.filter {
            $0.provenance.source != .appleWatch && $0.provenance.source != .whoopMotion
        }
        if !unsupported.isEmpty {
            review.append(reviewItem(.unsupportedSource, candidates: unsupported))
            let ids = Set(unsupported.map(\.id))
            eligible.removeAll { ids.contains($0.id) }
        }

        let invalidTime = eligible.filter {
            !$0.capturedAt.timeIntervalSinceReferenceDate.isFinite
        }
        if !invalidTime.isEmpty {
            review.append(reviewItem(.invalidTimestamp, candidates: invalidTime))
            let ids = Set(invalidTime.map(\.id))
            eligible.removeAll { ids.contains($0.id) }
        }

        let duplicateIDs = Dictionary(grouping: eligible, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
        if !duplicateIDs.isEmpty {
            let duplicateSet = Set(duplicateIDs)
            let duplicates = eligible.filter { duplicateSet.contains($0.id) }
            review.append(reviewItem(.duplicateIdentity, candidates: duplicates))
            eligible.removeAll { duplicateSet.contains($0.id) }
        }

        for source in [MetricSource.appleWatch, .whoopMotion] {
            let sourceCandidates = eligible.filter { $0.provenance.source == source }
            let conflictGroups = sameSourceConflictGroups(sourceCandidates)
            let conflictIDs = Set(conflictGroups.flatMap { $0.map(\.id) })
            for group in conflictGroups {
                review.append(reviewItem(.subsecondSameSourceConflict, candidates: group))
            }
            eligible.removeAll { conflictIDs.contains($0.id) }
        }

        let watches = sorted(eligible.filter { $0.provenance.source == .appleWatch })
        let whoops = sorted(eligible.filter { $0.provenance.source == .whoopMotion })
        let watchByID = Dictionary(uniqueKeysWithValues: watches.map { ($0.id, $0) })
        let whoopByID = Dictionary(uniqueKeysWithValues: whoops.map { ($0.id, $0) })

        var watchEdges: [UUID: Set<UUID>] = [:]
        var whoopEdges: [UUID: Set<UUID>] = [:]
        for watch in watches {
            for whoop in whoops {
                let delta = abs(watch.capturedAt.timeIntervalSince(whoop.capturedAt))
                guard delta <= maximumPairingDeltaSeconds else { continue }
                watchEdges[watch.id, default: []].insert(whoop.id)
                whoopEdges[whoop.id, default: []].insert(watch.id)
            }
        }

        let ambiguousComponents = ambiguousCrossSourceComponents(
            watchEdges: watchEdges,
            whoopEdges: whoopEdges,
            watchByID: watchByID,
            whoopByID: whoopByID
        )
        let ambiguousIDs = Set(ambiguousComponents.flatMap { $0.map(\.id) })
        for component in ambiguousComponents {
            review.append(reviewItem(.ambiguousCrossSourceMatch, candidates: component))
        }

        var consumedWhoopIDs = Set<UUID>()
        var records: [ReconciledHybridSwing] = []
        for watch in watches where !ambiguousIDs.contains(watch.id) {
            let possibleWhoops = (watchEdges[watch.id] ?? []).filter {
                !ambiguousIDs.contains($0)
            }
            if possibleWhoops.count == 1,
               let whoopID = possibleWhoops.first,
               (whoopEdges[whoopID] ?? []).filter({ !ambiguousIDs.contains($0) }).count == 1,
               let whoop = whoopByID[whoopID] {
                consumedWhoopIDs.insert(whoopID)
                records.append(
                    ReconciledHybridSwing(
                        watchObservation: watch,
                        whoopEnrichment: whoop,
                        resolution: .watchCanonicalWithWhoopEnrichment,
                        timestampDeltaSeconds: abs(
                            watch.capturedAt.timeIntervalSince(whoop.capturedAt)
                        )
                    )
                )
            } else {
                records.append(
                    ReconciledHybridSwing(
                        watchObservation: watch,
                        whoopEnrichment: nil,
                        resolution: .watchCanonicalAwaitingWhoop,
                        timestampDeltaSeconds: nil
                    )
                )
            }
        }

        let unmatchedWhoops = whoops.filter {
            !consumedWhoopIDs.contains($0.id) && !ambiguousIDs.contains($0.id)
        }
        for whoop in unmatchedWhoops {
            review.append(reviewItem(.unmatchedWhoopCandidate, candidates: [whoop]))
        }

        records.sort {
            if $0.canonicalCapturedAt == $1.canonicalCapturedAt {
                return $0.canonicalID.uuidString < $1.canonicalID.uuidString
            }
            return $0.canonicalCapturedAt < $1.canonicalCapturedAt
        }
        review.sort(by: reviewOrdering)
        return HybridSwingReconciliationResult(reconciled: records, review: review)
    }

    private static func sameSourceConflictGroups(
        _ candidates: [GolfSwingMetrics]
    ) -> [[GolfSwingMetrics]] {
        let candidates = sorted(candidates)
        guard let first = candidates.first else { return [] }
        var groups: [[GolfSwingMetrics]] = []
        var current = [first]
        for candidate in candidates.dropFirst() {
            let previous = current[current.count - 1]
            if candidate.capturedAt.timeIntervalSince(previous.capturedAt)
                < minimumSameSourceShotSeparationSeconds {
                current.append(candidate)
            } else {
                if current.count > 1 { groups.append(current) }
                current = [candidate]
            }
        }
        if current.count > 1 { groups.append(current) }
        return groups
    }

    /// Returns every connected timestamp-match component with more than one
    /// possible pairing on either side. Entire components are staged so no
    /// candidate is simultaneously paired and reviewed.
    private static func ambiguousCrossSourceComponents(
        watchEdges: [UUID: Set<UUID>],
        whoopEdges: [UUID: Set<UUID>],
        watchByID: [UUID: GolfSwingMetrics],
        whoopByID: [UUID: GolfSwingMetrics]
    ) -> [[GolfSwingMetrics]] {
        var seeds = Set<UUID>()
        for (id, edges) in watchEdges where edges.count > 1 { seeds.insert(id) }
        for (id, edges) in whoopEdges where edges.count > 1 { seeds.insert(id) }
        guard !seeds.isEmpty else { return [] }

        var visited = Set<UUID>()
        var components: [[GolfSwingMetrics]] = []
        for seed in seeds.sorted(by: { $0.uuidString < $1.uuidString }) where !visited.contains(seed) {
            var queue = [seed]
            var componentIDs = Set<UUID>()
            while let id = queue.first {
                queue.removeFirst()
                guard visited.insert(id).inserted else { continue }
                componentIDs.insert(id)
                let neighbours = (watchEdges[id] ?? []).union(whoopEdges[id] ?? [])
                queue.append(contentsOf: neighbours.filter { !visited.contains($0) })
            }
            let candidates = componentIDs.compactMap { watchByID[$0] ?? whoopByID[$0] }
            if !candidates.isEmpty { components.append(sorted(candidates)) }
        }
        return components
    }

    private static func reviewItem(
        _ reason: HybridSwingReviewReason,
        candidates: [GolfSwingMetrics]
    ) -> HybridSwingReviewItem {
        HybridSwingReviewItem(reason: reason, candidates: sorted(candidates))
    }

    private static func reviewOrdering(
        _ lhs: HybridSwingReviewItem,
        _ rhs: HybridSwingReviewItem
    ) -> Bool {
        let lhsDate = lhs.candidates.first?.capturedAt ?? .distantFuture
        let rhsDate = rhs.candidates.first?.capturedAt ?? .distantFuture
        if lhsDate == rhsDate { return lhs.reason.rawValue < rhs.reason.rawValue }
        return lhsDate < rhsDate
    }

    private static func sorted(_ observations: [GolfSwingMetrics]) -> [GolfSwingMetrics] {
        observations.sorted {
            if $0.capturedAt == $1.capturedAt {
                if $0.provenance.source == $1.provenance.source {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.provenance.source.rawValue < $1.provenance.source.rawValue
            }
            return $0.capturedAt < $1.capturedAt
        }
    }
}

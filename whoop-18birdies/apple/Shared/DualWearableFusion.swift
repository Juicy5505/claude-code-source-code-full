import Foundation

/// D19 smart fusion policy: maximize Apple Watch Series + WHOOP 5.0 without
/// BLE bond fights or live `TOGGLE_IMU` / Arming as the golf path.
///
/// Consumes `AdaptiveSensorPlan` facts from `SensorModeCoordinator`; does not
/// invent swing sources or upgrade missing capabilities.
enum DualWearableFusion {

    // MARK: - Heart rate ownership (bond-fight rules)

    /// Who may own live heart rate for the current plan.
    ///
    /// Rules (non-negotiable):
    /// 1. Live WHOOP IMU session and HR Broadcast never share the strap.
    /// 2. When Watch is the live golf wearable (hybrid / watch-only with a
    ///    proven Watch app), Watch owns HR — do not auto-start Broadcast.
    /// 3. WHOOP Broadcast is optional only when Watch is not the HR source
    ///    (WHOOP-only, or no Watch swing source).
    enum HeartRateOwner: String, Codable, Hashable, Sendable {
        case appleWatch
        case whoopBroadcast
        case none

        var title: String {
            switch self {
            case .appleWatch: "Apple Watch"
            case .whoopBroadcast: "WHOOP Broadcast"
            case .none: "None"
            }
        }
    }

    /// Pure policy input — no CoreBluetooth / WCSession side effects.
    struct HeartRateContext: Hashable, Sendable {
        let plan: AdaptiveSensorPlan
        let watchAppReady: Bool
        let whoopLiveIMUActive: Bool

        init(
            plan: AdaptiveSensorPlan,
            watchAppReady: Bool,
            whoopLiveIMUActive: Bool = false
        ) {
            self.plan = plan
            self.watchAppReady = watchAppReady
            self.whoopLiveIMUActive = whoopLiveIMUActive
        }
    }

    static func heartRateOwner(for context: HeartRateContext) -> HeartRateOwner {
        if context.whoopLiveIMUActive {
            // Experimental IMU path already owns the strap bond; Broadcast must yield.
            return .none
        }
        switch context.plan.mode {
        case .hybrid, .appleWatchOnly:
            return context.watchAppReady ? .appleWatch : .whoopBroadcast
        case .whoopOnly:
            return .whoopBroadcast
        case .unavailable:
            return .none
        }
    }

    /// Auto-start Broadcast only when policy selects WHOOP as HR owner.
    static func shouldAutoStartWhoopBroadcast(for context: HeartRateContext) -> Bool {
        heartRateOwner(for: context) == .whoopBroadcast
    }

    /// Manual Scan is allowed only when Broadcast is the selected owner
    /// (avoids fighting a Watch workout bond mid-round).
    static func shouldAllowWhoopBroadcastScan(for context: HeartRateContext) -> Bool {
        heartRateOwner(for: context) == .whoopBroadcast
    }

    static func heartRatePolicyDetail(for context: HeartRateContext) -> String {
        switch heartRateOwner(for: context) {
        case .appleWatch:
            return "Watch owns live HR for this plan. WHOOP HR Broadcast stays off to avoid strap bond fights with the Watch workout."
        case .whoopBroadcast:
            return "WHOOP HR Broadcast is the live physiology channel. Turn Broadcast on in the WHOOP app, then scan here."
        case .none:
            if context.whoopLiveIMUActive {
                return "Live WHOOP IMU holds the strap bond. Disconnect IMU before using HR Broadcast. Prefer delayed import on WHOOP 5."
            }
            return "No live HR source is selected until a Watch companion or WHOOP Broadcast path is proven."
        }
    }

    // MARK: - Round / journal fusion

    /// How a round should fuse Watch live scoring with delayed WHOOP import.
    struct RoundFusionPlan: Hashable, Sendable {
        let liveScoringSource: MetricSource?
        let delayedEnrichmentSource: MetricSource?
        /// When true, delayed WHOOP swings merge into the journal after the
        /// golfer taps Check for WHOOP swings — never as a second live scorecard.
        let mergeDelayedWhoopIntoJournal: Bool
        let liveScoringCaption: String
        let delayedMergeCaption: String
        let avoidsWhoop5LiveArming: Bool

        var isSmartFusion: Bool {
            liveScoringSource == .appleWatch && delayedEnrichmentSource == .whoopMotion
        }
    }

    static func roundFusion(for plan: AdaptiveSensorPlan) -> RoundFusionPlan {
        switch plan.mode {
        case .hybrid:
            return RoundFusionPlan(
                liveScoringSource: .appleWatch,
                delayedEnrichmentSource: .whoopMotion,
                mergeDelayedWhoopIntoJournal: true,
                liveScoringCaption:
                    "Watch scores the live round: path, tempo, HR, and counted shot identity.",
                delayedMergeCaption:
                    "WHOOP delayed swings merge into the journal when you Check for WHOOP swings — enrichment only, no double count.",
                avoidsWhoop5LiveArming: true
            )
        case .appleWatchOnly:
            return RoundFusionPlan(
                liveScoringSource: .appleWatch,
                delayedEnrichmentSource: nil,
                mergeDelayedWhoopIntoJournal: false,
                liveScoringCaption:
                    "Watch scores the live round. Configure WHOOP delayed import to unlock dual maximize.",
                delayedMergeCaption:
                    "No WHOOP enrichment is in the current plan.",
                avoidsWhoop5LiveArming: true
            )
        case .whoopOnly:
            return RoundFusionPlan(
                liveScoringSource: plan.canCaptureSwingLive ? .whoopMotion : nil,
                delayedEnrichmentSource: .whoopMotion,
                mergeDelayedWhoopIntoJournal: true,
                liveScoringCaption: plan.canCaptureSwingLive
                    ? "Authorized live WHOOP motion is configured — prefer delayed historical import on WHOOP 5 firmware."
                    : "WHOOP delayed historical import owns swing reconstruction after the round.",
                delayedMergeCaption:
                    "Check for WHOOP swings merges reviewed motion into the journal. Live Arming is not the golf path.",
                avoidsWhoop5LiveArming: true
            )
        case .unavailable:
            return RoundFusionPlan(
                liveScoringSource: nil,
                delayedEnrichmentSource: nil,
                mergeDelayedWhoopIntoJournal: false,
                liveScoringCaption: "No automatic wearable scoring until a swing source is proven.",
                delayedMergeCaption: "Manual scorecard and GPS checkpoints remain available.",
                avoidsWhoop5LiveArming: true
            )
        }
    }

    // MARK: - Today's contributions (Settings / preflight)

    struct ContributionLine: Hashable, Identifiable, Sendable {
        let id: String
        let title: String
        let status: String
        let detail: String
        let available: Bool
    }

    struct ContributionBoard: Hashable, Sendable {
        let modeTitle: String
        let heartRateOwner: HeartRateOwner
        let heartRateDetail: String
        let lines: [ContributionLine]
        let readinessBeforeRoundDetail: String
        let roundFusion: RoundFusionPlan
    }

    struct ContributionContext: Hashable, Sendable {
        let plan: AdaptiveSensorPlan
        let watchAppReady: Bool
        let whoopLiveIMUActive: Bool
        let whoopMotionConfigured: Bool
        let whoopCloudReady: Bool
        let hasReadinessSnapshot: Bool
        let iphoneGPSReady: Bool

        var heartRateContext: HeartRateContext {
            HeartRateContext(
                plan: plan,
                watchAppReady: watchAppReady,
                whoopLiveIMUActive: whoopLiveIMUActive
            )
        }
    }

    static func contributionsToday(for context: ContributionContext) -> ContributionBoard {
        let hrContext = context.heartRateContext
        let owner = heartRateOwner(for: hrContext)
        let fusion = roundFusion(for: context.plan)

        var lines: [ContributionLine] = [
            ContributionLine(
                id: "watch-live",
                title: "Apple Watch · live",
                status: context.plan.watchContributorStatus,
                detail: context.plan.watchContributorDetail,
                available: context.plan.mode == .hybrid || context.plan.mode == .appleWatchOnly
            ),
            ContributionLine(
                id: "whoop-delayed",
                title: "WHOOP 5 · delayed motion",
                status: context.plan.whoopContributorStatus,
                detail: context.plan.whoopContributorDetail,
                available: context.whoopMotionConfigured
                    || context.plan.mode == .hybrid
                    || context.plan.mode == .whoopOnly
            ),
            ContributionLine(
                id: "whoop-physio",
                title: "WHOOP · readiness / recovery / strain",
                status: context.whoopCloudReady ? "CLOUD" : "SETUP",
                detail: context.hasReadinessSnapshot
                    ? "Show the readiness card before the first tee; physiology stays cloud-cached, not live IMU."
                    : "Connect the private bridge for day-level readiness before the round.",
                available: context.whoopCloudReady || context.hasReadinessSnapshot
            ),
            ContributionLine(
                id: "hr",
                title: "Live heart rate",
                status: owner == .none ? "OFF" : owner.title.uppercased(),
                detail: heartRatePolicyDetail(for: hrContext),
                available: owner != .none
            ),
            ContributionLine(
                id: "phone-gps",
                title: "iPhone GPS · yardage",
                status: context.iphoneGPSReady ? "READY" : "ACTION",
                detail: "Inter-swing displacement only — never labeled as WHOOP band GPS.",
                available: context.iphoneGPSReady
            ),
        ]

        if fusion.mergeDelayedWhoopIntoJournal {
            lines.append(
                ContributionLine(
                    id: "journal-merge",
                    title: "Journal merge",
                    status: "ON CHECK",
                    detail: fusion.delayedMergeCaption,
                    available: true
                )
            )
        }

        let readinessDetail: String
        if context.hasReadinessSnapshot {
            readinessDetail =
                "Readiness card is available before the round from cached WHOOP cloud inputs."
        } else if context.whoopCloudReady {
            readinessDetail =
                "Pull Today readiness before the first tee for recovery / sleep / strain context."
        } else {
            readinessDetail =
                "No readiness snapshot yet — round can still start; physiology appears after bridge sync."
        }

        return ContributionBoard(
            modeTitle: context.plan.fusedStatusTitle,
            heartRateOwner: owner,
            heartRateDetail: heartRatePolicyDetail(for: hrContext),
            lines: lines,
            readinessBeforeRoundDetail: readinessDetail,
            roundFusion: fusion
        )
    }
}

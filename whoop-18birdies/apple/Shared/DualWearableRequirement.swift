import Foundation

/// Admission policy: WHOOP Golf requires **both** Apple Watch and WHOOP 5
/// for every new round. Pure — no WCSession / CoreBluetooth side effects.
///
/// Does not change `SensorModeCoordinator` mode math; it only decides whether
/// the golfer may start. Single-source drafts already on disk remain readable.
enum DualWearableRequirement {
    enum Outcome: Equatable, Sendable {
        case satisfied(AdaptiveSensorPlan)
        case missingWatch
        case missingWhoop
        case missingBoth
        case hybridDegraded(AdaptiveSensorPlan)

        var allowsStart: Bool {
            if case .satisfied = self { return true }
            return false
        }
    }

    struct Policy: Equatable, Sendable {
        /// Prefer paired+installed Watch (live capture), not only a recovered session.
        var requireWatchLiveCapture: Bool = true
        /// Require WHOOP historical/configured swing source (bridge or pending motion).
        /// Live Arming is never required — WHOOP 5 refuses it as the golf path.
        var requireWhoopSwingSource: Bool = true
        /// Soft physiology: readiness improves Overview but is not a hard tee gate.
        var requireReadinessSnapshot: Bool = false
    }

    static let productPolicy = Policy()

    static func evaluate(
        capabilities: SensorCapabilitySnapshot,
        hasReadinessSnapshot: Bool = false,
        policy: Policy = productPolicy
    ) -> Outcome {
        let watchOK = policy.requireWatchLiveCapture
            ? capabilities.appleWatch.canCaptureLive
            : capabilities.appleWatch.hasSwingSource
        let whoopOK = policy.requireWhoopSwingSource
            ? capabilities.whoop.hasSwingSource
            : true

        switch (watchOK, whoopOK) {
        case (false, false):
            return .missingBoth
        case (false, true):
            return .missingWatch
        case (true, false):
            return .missingWhoop
        case (true, true):
            let plan = SensorModeCoordinator.plan(for: capabilities)
            guard plan.mode == .hybrid else {
                return .hybridDegraded(plan)
            }
            if policy.requireReadinessSnapshot, !hasReadinessSnapshot {
                return .hybridDegraded(plan)
            }
            return .satisfied(plan)
        }
    }

    static func title(for outcome: Outcome) -> String {
        switch outcome {
        case .satisfied:
            return "Dual wearables ready"
        case .missingWatch:
            return "Apple Watch required"
        case .missingWhoop:
            return "WHOOP 5 required"
        case .missingBoth:
            return "Watch + WHOOP required"
        case .hybridDegraded:
            return "Dual maximize incomplete"
        }
    }

    static func detail(for outcome: Outcome) -> String {
        switch outcome {
        case .satisfied(let plan):
            return plan.fusedStatusDetail
        case .missingWatch:
            return "Pair and install WhoopGolfWatch on your Series Watch (trail-right). Live path, tempo, HR, and on-wrist cues require the Watch companion — Watch-only rounds are not allowed."
        case .missingWhoop:
            return "Configure the private WHOOP bridge / delayed motion path. Readiness, recovery, strain, and Check for WHOOP swings require WHOOP 5 — WHOOP-only rounds are not allowed; live IMU Arming is not used."
        case .missingBoth:
            return "WHOOP Golf is a dual-wearable product. New rounds require both Apple Watch (live capture) and WHOOP 5 (delayed enrich + physiology). Watch-only and WHOOP-only starts are disabled."
        case .hybridDegraded(let plan):
            return "Both devices look present, but the adaptive plan is \(plan.mode.rawValue) instead of hybrid. Re-check Watch live pairing and WHOOP delayed-import — start stays blocked until both admit hybrid."
        }
    }

    /// Primary Round CTA label. Blocked states always name what is still required.
    static func startButtonTitle(for outcome: Outcome) -> String {
        switch outcome {
        case .satisfied:
            return "Start dual Watch + WHOOP round"
        case .missingWatch:
            return "Apple Watch still required"
        case .missingWhoop:
            return "WHOOP 5 still required"
        case .missingBoth:
            return "Both Watch + WHOOP required"
        case .hybridDegraded:
            return "Fix dual Watch + WHOOP setup"
        }
    }

    static func startBlockedNotice(for outcome: Outcome) -> String {
        "\(title(for: outcome)). \(detail(for: outcome))"
    }
}

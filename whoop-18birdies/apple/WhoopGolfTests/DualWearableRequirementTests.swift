import XCTest
@testable import WhoopGolf

final class DualWearableRequirementTests: XCTestCase {
    func testMissingBothBlocksStart() {
        let outcome = DualWearableRequirement.evaluate(
            capabilities: SensorCapabilitySnapshot()
        )
        XCTAssertEqual(outcome, .missingBoth)
        XCTAssertFalse(outcome.allowsStart)
        XCTAssertEqual(DualWearableRequirement.title(for: outcome), "Watch + WHOOP required")
        XCTAssertTrue(
            DualWearableRequirement.detail(for: outcome)
                .localizedCaseInsensitiveContains("dual-wearable")
        )
        XCTAssertTrue(
            DualWearableRequirement.startBlockedNotice(for: outcome)
                .contains(DualWearableRequirement.title(for: outcome))
        )
    }

    func testWatchOnlyIsMissingWhoop() {
        let caps = SensorCapabilitySnapshot(
            whoop: WhoopSensorCapabilities(
                historicalCaptureConfigured: false,
                historicalMotionAvailable: false,
                authorizedLiveMotionProviderAvailable: false,
                authorizedBandHapticProviderAvailable: false
            ),
            appleWatch: AppleWatchSensorCapabilities(
                isPaired: true,
                isAppInstalled: true,
                isReachable: true,
                activeSessionSourceAvailable: false,
                synchronizedLocationAvailable: true
            ),
            iphoneLocation: .precise
        )
        let outcome = DualWearableRequirement.evaluate(capabilities: caps)
        XCTAssertEqual(outcome, .missingWhoop)
        XCTAssertFalse(outcome.allowsStart)
        XCTAssertEqual(DualWearableRequirement.title(for: outcome), "WHOOP 5 required")
        XCTAssertTrue(
            DualWearableRequirement.detail(for: outcome)
                .localizedCaseInsensitiveContains("delayed")
        )
    }

    func testWhoopOnlyIsMissingWatch() {
        let caps = SensorCapabilitySnapshot(
            whoop: WhoopSensorCapabilities(
                historicalCaptureConfigured: true,
                historicalMotionAvailable: false,
                authorizedLiveMotionProviderAvailable: false,
                authorizedBandHapticProviderAvailable: false
            ),
            appleWatch: AppleWatchSensorCapabilities(
                isPaired: false,
                isAppInstalled: false,
                isReachable: false,
                activeSessionSourceAvailable: false,
                synchronizedLocationAvailable: false
            ),
            iphoneLocation: .precise
        )
        let outcome = DualWearableRequirement.evaluate(capabilities: caps)
        XCTAssertEqual(outcome, .missingWatch)
        XCTAssertFalse(outcome.allowsStart)
        XCTAssertEqual(DualWearableRequirement.title(for: outcome), "Apple Watch required")
        XCTAssertTrue(
            DualWearableRequirement.detail(for: outcome)
                .localizedCaseInsensitiveContains("trail-right")
        )
    }

    func testBothProvenSatisfiesHybrid() {
        let caps = SensorCapabilitySnapshot(
            whoop: WhoopSensorCapabilities(
                historicalCaptureConfigured: true,
                historicalMotionAvailable: true,
                authorizedLiveMotionProviderAvailable: false,
                authorizedBandHapticProviderAvailable: false
            ),
            appleWatch: AppleWatchSensorCapabilities(
                isPaired: true,
                isAppInstalled: true,
                isReachable: true,
                activeSessionSourceAvailable: true,
                synchronizedLocationAvailable: true
            ),
            iphoneLocation: .precise
        )
        let outcome = DualWearableRequirement.evaluate(capabilities: caps)
        guard case .satisfied(let plan) = outcome else {
            return XCTFail("expected satisfied, got \(outcome)")
        }
        XCTAssertEqual(plan.mode, .hybrid)
        XCTAssertTrue(outcome.allowsStart)
        XCTAssertEqual(DualWearableRequirement.title(for: outcome), "Dual wearables ready")
    }

    /// Paired Watch without live app install is not enough when live capture is required.
    func testRecoveredWatchSessionAloneDoesNotSatisfyLiveGate() {
        let caps = SensorCapabilitySnapshot(
            whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
            appleWatch: AppleWatchSensorCapabilities(
                isPaired: false,
                isAppInstalled: false,
                activeSessionSourceAvailable: true,
                synchronizedLocationAvailable: true
            ),
            iphoneLocation: .precise
        )
        let outcome = DualWearableRequirement.evaluate(capabilities: caps)
        XCTAssertEqual(outcome, .missingWatch)
        XCTAssertFalse(outcome.allowsStart)
    }
}

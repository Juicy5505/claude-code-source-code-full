import XCTest
@testable import WhoopGolf

final class DualWearableFusionTests: XCTestCase {
    func testHybridWithWatchReadyGivesWatchHRAndBlocksBroadcast() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    isReachable: true,
                    synchronizedLocationAvailable: true
                ),
                iphoneLocation: .precise
            )
        )
        let context = DualWearableFusion.HeartRateContext(
            plan: plan,
            watchAppReady: true,
            whoopLiveIMUActive: false
        )

        XCTAssertEqual(plan.mode, .hybrid)
        XCTAssertEqual(DualWearableFusion.heartRateOwner(for: context), .appleWatch)
        XCTAssertFalse(DualWearableFusion.shouldAutoStartWhoopBroadcast(for: context))
        XCTAssertFalse(DualWearableFusion.shouldAllowWhoopBroadcastScan(for: context))
    }

    func testWhoopOnlyAllowsBroadcast() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                iphoneLocation: .precise
            )
        )
        let context = DualWearableFusion.HeartRateContext(
            plan: plan,
            watchAppReady: false
        )

        XCTAssertEqual(DualWearableFusion.heartRateOwner(for: context), .whoopBroadcast)
        XCTAssertTrue(DualWearableFusion.shouldAutoStartWhoopBroadcast(for: context))
        XCTAssertTrue(DualWearableFusion.shouldAllowWhoopBroadcastScan(for: context))
    }

    func testLiveIMUForcesHRNoneToAvoidBondFight() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                iphoneLocation: .precise
            )
        )
        let context = DualWearableFusion.HeartRateContext(
            plan: plan,
            watchAppReady: false,
            whoopLiveIMUActive: true
        )

        XCTAssertEqual(DualWearableFusion.heartRateOwner(for: context), .none)
        XCTAssertFalse(DualWearableFusion.shouldAllowWhoopBroadcastScan(for: context))
    }

    func testHybridRoundFusionMergesDelayedWhoopWithoutLiveArming() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    synchronizedLocationAvailable: true
                )
            )
        )
        let fusion = DualWearableFusion.roundFusion(for: plan)

        XCTAssertTrue(fusion.isSmartFusion)
        XCTAssertEqual(fusion.liveScoringSource, .appleWatch)
        XCTAssertEqual(fusion.delayedEnrichmentSource, .whoopMotion)
        XCTAssertTrue(fusion.mergeDelayedWhoopIntoJournal)
        XCTAssertTrue(fusion.avoidsWhoop5LiveArming)
    }

    func testContributionsTodaySurfacesReadinessAndJournalMerge() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalMotionAvailable: true),
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    synchronizedLocationAvailable: true
                ),
                iphoneLocation: .precise
            )
        )
        let board = DualWearableFusion.contributionsToday(
            for: DualWearableFusion.ContributionContext(
                plan: plan,
                watchAppReady: true,
                whoopLiveIMUActive: false,
                whoopMotionConfigured: true,
                whoopCloudReady: true,
                hasReadinessSnapshot: true,
                iphoneGPSReady: true
            )
        )

        XCTAssertEqual(board.heartRateOwner, .appleWatch)
        XCTAssertTrue(board.lines.contains { $0.id == "journal-merge" })
        XCTAssertTrue(board.lines.contains { $0.id == "whoop-physio" && $0.available })
        XCTAssertTrue(board.readinessBeforeRoundDetail.contains("Readiness card"))
    }
}

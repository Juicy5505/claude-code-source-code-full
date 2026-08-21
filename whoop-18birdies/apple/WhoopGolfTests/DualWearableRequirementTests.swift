import XCTest
@testable import WhoopGolf

final class DualWearableRequirementTests: XCTestCase {
    func testMissingBothBlocksStart() {
        let outcome = DualWearableRequirement.evaluate(
            capabilities: SensorCapabilitySnapshot()
        )
        XCTAssertEqual(outcome, .missingBoth)
        XCTAssertFalse(outcome.allowsStart)
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
    }
}

final class ComprehensiveShotIntelligenceTests: XCTestCase {
    func testOutToInMapsToPullFadeTendency() {
        let (bias, detail) = ComprehensiveShotIntelligence.ballStartBias(
            path: .outToIn,
            severity: .moderate
        )
        XCTAssertEqual(bias, .pullFade)
        XCTAssertFalse(detail.isEmpty)
    }

    func testInToOutMapsToPushDrawTendency() {
        let (bias, _) = ComprehensiveShotIntelligence.ballStartBias(
            path: .inToOut,
            severity: .severe
        )
        XCTAssertEqual(bias, .pushDraw)
    }

    func testOnPlaneMapsToStraight() {
        let (bias, _) = ComprehensiveShotIntelligence.ballStartBias(path: .onPlane)
        XCTAssertEqual(bias, .straight)
    }

    func testEnrichTrackingFieldsPersistsClubAndBias() {
        let t0 = Date(timeIntervalSince1970: 1_700_200_000)
        let swing = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 4.0,
            tempoRatio: 2.4,
            pathYawDegrees: -20,
            pathClass: SwingPathClass.outToIn.rawValue,
            pathScore: 62,
            pathExplanation: "Out-to-in",
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            )
        )
        let enriched = ComprehensiveShotIntelligence.enrichTrackingFields(
            [swing],
            defaultClub: .sevenIron,
            wrist: .trailRight
        )
        XCTAssertEqual(enriched[0].club, GolfClubKind.sevenIron.rawValue)
        XCTAssertEqual(enriched[0].resolvedBallStartBias, .pullFade)
        XCTAssertNotEqual(enriched[0].resolvedAttackFeel, .unknown)
        XCTAssertFalse(enriched[0].ballStartDetail?.isEmpty ?? true)
    }

    func testHybridMaterializationPreservesPathAndClub() {
        let t0 = Date(timeIntervalSince1970: 1_700_200_100)
        let watch = GolfSwingMetrics(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            capturedAt: t0,
            peakG: 3.5,
            pathYawDegrees: -12,
            pathClass: SwingPathClass.outToIn.rawValue,
            pathScore: 70,
            pathExplanation: "Watch path",
            improverTip: "Inside",
            club: GolfClubKind.driver.rawValue,
            ballStartBias: BallStartBias.fade.rawValue,
            attackFeel: AttackFeel.steep.rawValue,
            ballStartDetail: "Fade tendency",
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            )
        )
        let whoop = GolfSwingMetrics(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            capturedAt: t0.addingTimeInterval(0.4),
            peakG: 5.2,
            tempoRatio: 3.0,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: t0.addingTimeInterval(0.4),
                quality: .estimated
            )
        )
        let result = HybridSwingReconciler.reconcile([watch, whoop])
        XCTAssertEqual(result.canonicalSwings.count, 1)
        let fused = result.canonicalSwings[0]
        XCTAssertEqual(fused.pathScore, 70)
        XCTAssertEqual(fused.pathClass, SwingPathClass.outToIn.rawValue)
        XCTAssertEqual(fused.club, GolfClubKind.driver.rawValue)
        XCTAssertEqual(fused.provenance.source, .derived)
    }
}

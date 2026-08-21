import XCTest
@testable import WhoopGolf

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

    func testMildPathSeverityMapsSofterCurveBias() {
        let (outMild, _) = ComprehensiveShotIntelligence.ballStartBias(
            path: .outToIn,
            severity: .mild
        )
        let (inMild, _) = ComprehensiveShotIntelligence.ballStartBias(
            path: .inToOut,
            severity: .mild
        )
        XCTAssertEqual(outMild, .fade)
        XCTAssertEqual(inMild, .draw)
    }

    func testUnknownPathSeverityFallsBackToStartBias() {
        let (outUnknown, _) = ComprehensiveShotIntelligence.ballStartBias(
            path: .outToIn,
            severity: .unknown
        )
        let (inUnknown, _) = ComprehensiveShotIntelligence.ballStartBias(
            path: .inToOut,
            severity: .unknown
        )
        XCTAssertEqual(outUnknown, .pull)
        XCTAssertEqual(inUnknown, .push)
    }

    func testOnPlaneMapsToStraight() {
        let (bias, _) = ComprehensiveShotIntelligence.ballStartBias(path: .onPlane)
        XCTAssertEqual(bias, .straight)
    }

    func testUnknownPathMapsToUnknownBias() {
        let (bias, detail) = ComprehensiveShotIntelligence.ballStartBias(path: .unknown)
        XCTAssertEqual(bias, .unknown)
        XCTAssertTrue(detail.localizedCaseInsensitiveContains("path"))
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

    func testEnrichTrackingFieldsPreservesMeasuredYards() {
        let t0 = Date(timeIntervalSince1970: 1_700_200_050)
        let nextID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let interval = SwingShotInterval(
            finalizedBySwingID: nextID,
            finalizedAt: t0.addingTimeInterval(35),
            elapsedSeconds: 35,
            straightLineDisplacementYards: 168.5,
            distanceUncertaintyYards: 4,
            distanceStatus: .measured,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: t0.addingTimeInterval(35),
                quality: .measured
            )
        )
        let swing = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 3.6,
            pathYawDegrees: -14,
            pathClass: SwingPathClass.outToIn.rawValue,
            pathScore: 68,
            club: GolfClubKind.eightIron.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            ),
            shotInterval: interval
        )
        let enriched = ComprehensiveShotIntelligence.enrichTrackingFields(
            [swing],
            wrist: .trailRight
        )
        XCTAssertEqual(enriched[0].shotYards ?? -1, 168.5, accuracy: 0.01)
        XCTAssertEqual(enriched[0].club, GolfClubKind.eightIron.rawValue)
        XCTAssertEqual(enriched[0].resolvedBallStartBias, .pullFade)
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
        XCTAssertEqual(fused.pathExplanation, "Watch path")
        XCTAssertEqual(fused.club, GolfClubKind.driver.rawValue)
        XCTAssertEqual(fused.ballStartBias, BallStartBias.fade.rawValue)
        XCTAssertEqual(fused.provenance.source, .derived)
        XCTAssertEqual(fused.peakG, 5.2, accuracy: 0.001)
    }

    func testMaterializedObservationPreservesWatchPathAndClub() {
        let t0 = Date(timeIntervalSince1970: 1_700_200_150)
        let watch = GolfSwingMetrics(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            capturedAt: t0,
            peakG: 4.1,
            pathYawDegrees: 16,
            pathClass: SwingPathClass.inToOut.rawValue,
            pathScore: 74,
            pathExplanation: "In-to-out",
            club: GolfClubKind.fiveIron.rawValue,
            ballStartBias: BallStartBias.pushDraw.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            )
        )
        let whoop = GolfSwingMetrics(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            capturedAt: t0.addingTimeInterval(0.8),
            peakG: 6.0,
            tempoRatio: 2.9,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: t0.addingTimeInterval(0.8),
                quality: .estimated
            )
        )
        let row = ReconciledHybridSwing(
            watchObservation: watch,
            whoopEnrichment: whoop,
            resolution: .watchCanonicalWithWhoopEnrichment,
            timestampDeltaSeconds: 0.8
        )
        let fused = row.materializedObservation
        XCTAssertEqual(fused.id, watch.id)
        XCTAssertEqual(fused.pathScore, 74)
        XCTAssertEqual(fused.pathClass, SwingPathClass.inToOut.rawValue)
        XCTAssertEqual(fused.club, GolfClubKind.fiveIron.rawValue)
        XCTAssertEqual(fused.ballStartBias, BallStartBias.pushDraw.rawValue)
        XCTAssertNil(fused.shotInterval)
        XCTAssertEqual(fused.tempoRatio ?? -1, 2.9, accuracy: 0.001)
    }

    func testDossierMapsTrailRightOutToInToPullFade() {
        let t0 = Date(timeIntervalSince1970: 1_700_200_200)
        let swing = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 4.4,
            tempoRatio: 2.5,
            pathYawDegrees: -18,
            pathClass: SwingPathClass.outToIn.rawValue,
            pathScore: 60,
            club: GolfClubKind.sevenIron.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            )
        )
        let dossier = ComprehensiveShotIntelligence.dossier(
            for: swing,
            sequence: 3,
            wrist: .trailRight
        )
        XCTAssertEqual(dossier.sequence, 3)
        XCTAssertEqual(dossier.club, .sevenIron)
        XCTAssertEqual(dossier.pathClass, .outToIn)
        XCTAssertEqual(dossier.ballStartBias, .pullFade)
        XCTAssertTrue(dossier.watchLive)
        XCTAssertFalse(dossier.whoopEnriched)
        XCTAssertTrue(dossier.fusionCaption.localizedCaseInsensitiveContains("watch"))
        XCTAssertEqual(dossier.ballStartBias.shortLabel, "P-FADE")
    }
}

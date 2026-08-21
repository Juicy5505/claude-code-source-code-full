import XCTest
@testable import WhoopGolf

final class StrokeScoreShotChainTests: XCTestCase {
    func testEnrichSwingMetricsPersistsPathScoreAndExplanation() {
        let t0 = Date(timeIntervalSince1970: 1_700_100_000)
        let swing = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 4.2,
            tempoRatio: 3.1,
            pathYawDegrees: -18,
            pathClass: SwingPathClass.outToIn.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            ),
            location: SwingLocationObservation(
                latitude: 40.0,
                longitude: -75.0,
                altitudeMeters: nil,
                horizontalAccuracyMeters: 5,
                capturedAt: t0,
                provenance: DataProvenance(
                    source: .iphoneGPS,
                    observedAt: t0,
                    quality: .measured
                )
            )
        )

        let enriched = StrokeScoreShotChain.enrichSwingMetrics([swing], wrist: .trailRight)
        XCTAssertEqual(enriched.count, 1)
        XCTAssertNotNil(enriched[0].pathScore)
        XCTAssertGreaterThan(enriched[0].pathScore ?? 0, 0)
        XCTAssertFalse(enriched[0].pathExplanation?.isEmpty ?? true)
        XCTAssertEqual(enriched[0].pathClass, SwingPathClass.outToIn.rawValue)
        XCTAssertFalse(enriched[0].improverTip?.isEmpty ?? true)
    }

    func testTrailRightPolarityDoesNotDoubleFlipStoredYaw() {
        let t0 = Date(timeIntervalSince1970: 1_700_100_050)
        // Stored Watch yaw is already mount-corrected (negative = out-to-in on trail-right).
        let swing = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 3.8,
            pathYawDegrees: -22,
            pathClass: nil,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            )
        )
        let enriched = StrokeScoreShotChain.enrichSwingMetrics([swing], wrist: .trailRight)
        XCTAssertEqual(enriched[0].resolvedPathClass, .outToIn)
        XCTAssertEqual(enriched[0].pathYawDegrees, -22, accuracy: 0.001)
    }

    func testEnrichPreservesMeasuredShotIntervals() {
        let t0 = Date(timeIntervalSince1970: 1_700_100_100)
        let first = GolfSwingMetrics(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            capturedAt: t0,
            peakG: 3.0,
            pathYawDegrees: 4,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            ),
            location: location(at: t0, lat: 40.0, lon: -75.0)
        )
        let second = GolfSwingMetrics(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            capturedAt: t0.addingTimeInterval(40),
            peakG: 3.5,
            pathYawDegrees: -12,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0.addingTimeInterval(40),
                quality: .measured
            ),
            location: location(at: t0.addingTimeInterval(40), lat: 40.0015, lon: -75.0)
        )
        let chained = SwingShotIntervalCalculator.finalizingIntervals(in: [first, second])
        XCTAssertNotNil(chained[0].shotInterval)
        XCTAssertNotNil(chained[0].shotYards)

        let enriched = StrokeScoreShotChain.enrichSwingMetrics(chained, wrist: .trailRight)
        XCTAssertNotNil(enriched[0].shotInterval)
        XCTAssertEqual(
            enriched[0].shotYards ?? -1,
            chained[0].shotYards ?? -2,
            accuracy: 0.01
        )
        XCTAssertNotNil(enriched[1].pathScore)
    }

    func testMakeLiveFaceIncludesPathScoreFromChain() {
        let t0 = Date(timeIntervalSince1970: 1_700_100_200)
        let a = GolfSwingMetrics(
            capturedAt: t0,
            peakG: 3.0,
            pathYawDegrees: 3,
            pathClass: SwingPathClass.onPlane.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            ),
            location: location(at: t0, lat: 40.0, lon: -75.0)
        )
        let b = GolfSwingMetrics(
            capturedAt: t0.addingTimeInterval(30),
            peakG: 3.2,
            pathYawDegrees: -8,
            pathClass: SwingPathClass.outToIn.rawValue,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0.addingTimeInterval(30),
                quality: .measured
            ),
            location: location(at: t0.addingTimeInterval(30), lat: 40.001, lon: -75.0)
        )
        let chain = SwingShotIntervalCalculator.finalizingIntervals(in: [a, b])
        let face = PhoneYardageBridge.makeLiveFace(
            holeNumber: 4,
            courseName: "Demo",
            swings: chain,
            wristMount: .trailRight,
            phoneFix: nil,
            greenTargets: nil
        )
        XCTAssertNotNil(face.lastShotYards)
        XCTAssertNotNil(face.lastPathScore)
        XCTAssertEqual(face.strokeCount, 2)
        XCTAssertEqual(face.wristMount, .trailRight)
    }

    func testHybridReconcileDoesNotDoubleCountMatchedSwings() {
        let t0 = Date(timeIntervalSince1970: 1_700_100_300)
        let watchID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let watch = GolfSwingMetrics(
            id: watchID,
            capturedAt: t0,
            peakG: 4.0,
            pathYawDegrees: -10,
            provenance: DataProvenance(
                source: .appleWatch,
                observedAt: t0,
                quality: .measured
            ),
            location: location(at: t0, lat: 40.0, lon: -75.0)
        )
        let whoop = GolfSwingMetrics(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            capturedAt: t0.addingTimeInterval(1.2),
            peakG: 3.9,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: t0.addingTimeInterval(1.2),
                quality: .estimated
            ),
            location: location(at: t0.addingTimeInterval(1.2), lat: 40.0001, lon: -75.0)
        )
        let result = HybridSwingReconciler.reconcile([watch, whoop])
        XCTAssertEqual(result.canonicalSwings.count, 1)
        XCTAssertEqual(result.canonicalSwings.first?.id, watchID)
        XCTAssertTrue(result.review.isEmpty)
    }

    private func location(at date: Date, lat: Double, lon: Double) -> SwingLocationObservation {
        SwingLocationObservation(
            latitude: lat,
            longitude: lon,
            altitudeMeters: nil,
            horizontalAccuracyMeters: 4,
            capturedAt: date,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: date,
                quality: .measured
            )
        )
    }
}

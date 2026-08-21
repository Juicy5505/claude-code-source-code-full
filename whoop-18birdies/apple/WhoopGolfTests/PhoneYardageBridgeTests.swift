import XCTest
@testable import WhoopGolf

final class PhoneYardageBridgeTests: XCTestCase {
    func testLastMeasuredShotYardsUsesFinalizedSwingChainNotPendingTail() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let first = swing(at: t0, lat: 40.0, lon: -75.0)
        let second = swing(at: t0.addingTimeInterval(30), lat: 40.001, lon: -75.0)
        let third = swing(at: t0.addingTimeInterval(60), lat: 40.002, lon: -75.0)

        let chain = SwingShotIntervalCalculator.finalizingIntervals(in: [first, second, third])
        XCTAssertNil(chain.last?.shotInterval, "newest swing stays pending")
        XCTAssertNotNil(chain[chain.count - 2].shotInterval)

        let yards = PhoneYardageBridge.lastMeasuredShotYards(from: chain)
        XCTAssertNotNil(yards)
        XCTAssertGreaterThan(yards ?? 0, 0)

        // Reading swings.last.shotInterval would falsely yield nil.
        XCTAssertNil(chain.last?.shotInterval?.straightLineDisplacementYards)
    }

    func testSingleSwingYieldsNoStrokeYards() {
        let alone = [swing(at: Date(), lat: 40.0, lon: -75.0)]
        let chain = SwingShotIntervalCalculator.finalizingIntervals(in: alone)
        XCTAssertNil(PhoneYardageBridge.lastMeasuredShotYards(from: chain))
    }

    func testFacilitySearchNeverBecomesGreenMap() {
        let candidate = GolfCourseCandidate(
            id: "poi-1",
            name: "Somewhere GC",
            latitude: 40.0,
            longitude: -75.0,
            distanceMeters: 120,
            confidence: .high,
            source: GolfCourseCandidate.appleMapsSource,
            selectionState: .suggested
        )
        XCTAssertNil(PhoneYardageBridge.greenTargetsFromFacilitySearch(candidate))
    }

    func testMakeLiveFaceKeepsStrokeYardsAndEmptyOverlayWithoutGeometry() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        let a = swing(at: t0, lat: 40.0, lon: -75.0)
        let b = swing(at: t0.addingTimeInterval(25), lat: 40.0015, lon: -75.0)
        let chain = SwingShotIntervalCalculator.finalizingIntervals(in: [a, b])

        let face = PhoneYardageBridge.makeLiveFace(
            holeNumber: 7,
            courseName: "Test",
            swings: chain,
            wristMount: .trailRight,
            phoneFix: phoneFix(lat: 40.001, lon: -75.0),
            greenTargets: nil
        )
        XCTAssertEqual(face.holeNumber, 7)
        XCTAssertFalse(face.hasHoleMap)
        XCTAssertNil(face.frontYards)
        XCTAssertNotNil(face.lastShotYards)
        XCTAssertEqual(face.wristMount, .trailRight)
    }

    func testMakeLiveFaceFillsFrontMidBackOnlyWithLicensedTargets() {
        let targets = GolfHoleGreenTargets(
            courseIdentifier: "course-licensed-1",
            holeNumber: 3,
            frontLatitude: 40.01,
            frontLongitude: -75.01,
            middleLatitude: 40.011,
            middleLongitude: -75.01,
            backLatitude: 40.012,
            backLongitude: -75.01,
            attribution: GolfHoleGeometryAttribution(
                providerName: "Test Provider",
                datasetVersion: "v1",
                licenseNotice: "test license"
            )
        )
        let face = PhoneYardageBridge.makeLiveFace(
            holeNumber: 3,
            courseName: "Test",
            swings: [],
            wristMount: .trailRight,
            phoneFix: phoneFix(lat: 40.0, lon: -75.0),
            greenTargets: targets
        )
        XCTAssertTrue(face.hasHoleMap)
        XCTAssertNotNil(face.frontYards)
        XCTAssertNotNil(face.middleYards)
        XCTAssertNotNil(face.backYards)
        XCTAssertNil(face.lastShotYards)
        XCTAssertGreaterThan(face.backYards ?? 0, face.frontYards ?? 0)
    }

    func testExcludedHoleTransitionDoesNotPublishStrokeYards() {
        let interval = SwingShotInterval(
            finalizedBySwingID: UUID(),
            finalizedAt: Date(),
            elapsedSeconds: 40,
            straightLineDisplacementYards: 180,
            distanceUncertaintyYards: 8,
            distanceStatus: .measured,
            exclusionReason: .confirmedHoleTransition,
            provenance: DataProvenance(
                source: .derived,
                observedAt: Date(),
                quality: .unavailable,
                algorithmVersion: "test"
            )
        )
        var swing = swing(at: Date(), lat: 40.0, lon: -75.0)
        swing.shotInterval = interval
        XCTAssertNil(PhoneYardageBridge.lastMeasuredShotYards(from: [swing]))
    }

    private func phoneFix(lat: Double, lon: Double) -> LocationFix {
        LocationFix(
            latitude: lat,
            longitude: lon,
            altitudeMeters: 10,
            horizontalAccuracyMeters: 5,
            capturedAt: Date(),
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: Date(),
                quality: .verified
            )
        )
    }

    private func swing(at date: Date, lat: Double, lon: Double) -> GolfSwingMetrics {
        GolfSwingMetrics(
            capturedAt: date,
            peakG: 8.0,
            provenance: DataProvenance(
                source: .whoopMotion,
                observedAt: date,
                quality: .verified
            ),
            location: SwingLocationObservation(
                latitude: lat,
                longitude: lon,
                altitudeMeters: 10,
                horizontalAccuracyMeters: 4,
                capturedAt: date,
                provenance: DataProvenance(
                    source: .iphoneGPS,
                    observedAt: date,
                    quality: .verified
                )
            ),
            locationCorrelationMethod: .sensorSynchronized
        )
    }
}

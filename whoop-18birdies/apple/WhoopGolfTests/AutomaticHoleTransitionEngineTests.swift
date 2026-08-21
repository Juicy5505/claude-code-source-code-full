import XCTest
@testable import WhoopGolf

final class AutomaticHoleTransitionEngineTests: XCTestCase {
    func testLicensedGreenToNextTeeCorroborationAdvancesAndWithholdsWalkingDistance() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(180),
            latitude: 40.002,
            longitude: -75
        )
        let geometry = transitionGeometry()
        let context = AutomaticHoleTransitionContext(
            currentHole: 1,
            holeCount: .eighteen,
            whoopSwingCountOnCurrentHole: 4,
            geometry: geometry
        )

        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: context
        )

        XCTAssertEqual(decision.action, .advance)
        XCTAssertEqual(decision.confidence, .high)
        XCTAssertEqual(decision.destinationHole, 2)
        XCTAssertEqual(decision.boundaryAt, destination.capturedAt)
        XCTAssertEqual(decision.intervalDisposition, .withholdConfirmedHoleTransition)
        XCTAssertTrue(decision.evidence.contains(.licensedCurrentGreenRegion))
        XCTAssertTrue(decision.evidence.contains(.licensedNextTeeRegion))
        XCTAssertEqual(decision.geometryAttribution, geometry.attribution)
        XCTAssertEqual(decision.spatialInputSources, [.iphoneGPS])

        let interval = SwingShotIntervalCalculator.interval(
            from: origin,
            finalizedBy: destination,
            disposition: decision.intervalDisposition
        )
        XCTAssertEqual(interval.exclusionReason, .confirmedHoleTransition)
        XCTAssertNil(interval.straightLineDisplacementYards)
        XCTAssertNil(interval.distanceUncertaintyYards)
    }

    func testNoHoleGeometryCanOnlyRequestReviewNeverAdvance() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(9 * 60),
            latitude: 40.001,
            longitude: -75
        )
        let context = AutomaticHoleTransitionContext(
            currentHole: 7,
            holeCount: .eighteen,
            whoopSwingCountOnCurrentHole: 3
        )

        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: context
        )

        XCTAssertEqual(decision.action, .review)
        XCTAssertEqual(decision.confidence, .low)
        XCTAssertEqual(decision.destinationHole, 8)
        XCTAssertEqual(decision.intervalDisposition, .withholdPendingHoleTransitionReview)
        XCTAssertTrue(decision.evidence.contains(.noLicensedHoleGeometry))
        XCTAssertNil(decision.geometryAttribution)
    }

    func testEnteredScoreShortensReviewWindowButStillDoesNotAutoAdvanceWithoutGeometry() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(150),
            latitude: 40.001,
            longitude: -75
        )
        let context = AutomaticHoleTransitionContext(
            currentHole: 3,
            holeCount: .nine,
            whoopSwingCountOnCurrentHole: 4,
            enteredStrokesForCurrentHole: 4
        )

        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: context
        )

        XCTAssertEqual(decision.action, .review)
        XCTAssertEqual(decision.confidence, .medium)
        XCTAssertTrue(decision.evidence.contains(.enteredHoleScore))
        XCTAssertNotEqual(decision.action, .advance)
    }

    func testOrdinaryWHOOPSwingPairRemainsMeasurable() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(5 * 60),
            latitude: 40.001,
            longitude: -75
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 2
            )
        )

        XCTAssertEqual(decision.action, .remain)
        XCTAssertEqual(decision.intervalDisposition, .measure)
        XCTAssertEqual(decision.spatialInputSources, [.iphoneGPS])
        let interval = SwingShotIntervalCalculator.interval(
            from: origin,
            finalizedBy: destination,
            disposition: decision.intervalDisposition
        )
        XCTAssertEqual(interval.distanceStatus, .measured)
        XCTAssertGreaterThan(interval.straightLineDisplacementYards ?? 0, 100)
        XCTAssertEqual(interval.provenance.inputSources, [.whoopMotion, .iphoneGPS])
    }

    func testNextTeeWithoutCurrentGreenCorroborationRequiresReview() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 39.998, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(9 * 60),
            latitude: 40.002,
            longitude: -75
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 3,
                geometry: transitionGeometry()
            )
        )

        XCTAssertEqual(decision.action, .review)
        XCTAssertEqual(decision.confidence, .medium)
        XCTAssertTrue(decision.evidence.contains(.licensedNextTeeRegion))
        XCTAssertFalse(decision.evidence.contains(.licensedCurrentGreenRegion))
    }

    func testRecordedTimelineBoundaryWinsWithoutRequiringGeometry() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(30),
            latitude: 40.001,
            longitude: -75
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 4,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 1,
                recordedDestinationHole: 5
            )
        )

        XCTAssertEqual(decision.action, .useRecordedBoundary)
        XCTAssertEqual(decision.confidence, .confirmed)
        XCTAssertEqual(decision.intervalDisposition, .withholdConfirmedHoleTransition)
        XCTAssertTrue(decision.evidence.contains(.recordedHoleBoundary))
    }

    func testMismatchedOrIncompleteGeometryCannotCauseAutonomousAdvance() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(60),
            latitude: 40.002,
            longitude: -75
        )
        let mismatched = GolfHoleTransitionGeometry(
            courseIdentifier: "licensed-course-id",
            fromHole: 2,
            toHole: 3,
            currentGreen: transitionGeometry().currentGreen,
            nextTeeRegions: transitionGeometry().nextTeeRegions,
            attribution: transitionGeometry().attribution
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 3,
                geometry: mismatched
            )
        )

        XCTAssertEqual(decision.action, .remain)
        XCTAssertTrue(decision.evidence.contains(.noLicensedHoleGeometry))
        XCTAssertNil(decision.geometryAttribution)
    }

    func testLastHoleAndNonWHOOPSourcesNeverAutoAdvance() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let whoopOrigin = swing(at: start, latitude: 40, longitude: -75)
        let destination = swing(
            at: start.addingTimeInterval(10 * 60),
            latitude: 40.002,
            longitude: -75
        )
        let lastHole = AutomaticHoleTransitionEngine.evaluate(
            origin: whoopOrigin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 9,
                holeCount: .nine,
                whoopSwingCountOnCurrentHole: 4,
                geometry: transitionGeometry()
            )
        )
        XCTAssertEqual(lastHole.action, .remain)

        let manualOrigin = swing(
            at: start,
            latitude: 40,
            longitude: -75,
            source: .manual
        )
        let nonWhoop = AutomaticHoleTransitionEngine.evaluate(
            origin: manualOrigin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 4,
                geometry: transitionGeometry()
            )
        )
        XCTAssertEqual(nonWhoop.action, .remain)
        XCTAssertFalse(nonWhoop.evidence.contains(.whoopMotionPair))
    }

    func testCoordinatesClaimingWHOOPMotionProvenanceFailClosed() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(
            at: start,
            latitude: 40,
            longitude: -75,
            locationSource: .whoopMotion
        )
        let destination = swing(
            at: start.addingTimeInterval(10 * 60),
            latitude: 40.002,
            longitude: -75,
            locationSource: .whoopMotion
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 4,
                geometry: transitionGeometry()
            )
        )

        XCTAssertEqual(decision.action, .remain)
        XCTAssertEqual(decision.confidence, .unavailable)
        XCTAssertEqual(decision.intervalDisposition, .withholdUnverifiedSpatialSource)
        XCTAssertTrue(decision.evidence.contains(.unverifiedSpatialSource))
        XCTAssertTrue(decision.spatialInputSources.isEmpty)
        XCTAssertNil(decision.geometryAttribution)

        let interval = SwingShotIntervalCalculator.interval(
            from: origin,
            finalizedBy: destination,
            disposition: .measure
        )
        XCTAssertNil(interval.straightLineDisplacementYards)
        XCTAssertEqual(interval.exclusionReason, .unverifiedSpatialSource)
    }

    func testDerivedCoordinateRetainsItsExplicitIPhoneGPSInput() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let origin = swing(
            at: start,
            latitude: 40,
            longitude: -75,
            locationSource: .derived,
            locationInputSources: [.iphoneGPS]
        )
        let destination = swing(
            at: start.addingTimeInterval(180),
            latitude: 40.001,
            longitude: -75,
            locationSource: .derived,
            locationInputSources: [.iphoneGPS]
        )
        let decision = AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: 1,
                holeCount: .eighteen,
                whoopSwingCountOnCurrentHole: 2
            )
        )

        XCTAssertEqual(decision.action, .remain)
        XCTAssertEqual(decision.spatialInputSources, [.iphoneGPS])
        XCTAssertTrue(decision.evidence.contains(.explicitIPhoneGPSLocation))
        let interval = SwingShotIntervalCalculator.interval(
            from: origin,
            finalizedBy: destination
        )
        XCTAssertEqual(interval.distanceStatus, .measured)
        XCTAssertNil(interval.exclusionReason)
        XCTAssertEqual(interval.provenance.inputSources, [.whoopMotion, .derived, .iphoneGPS])
    }

    func testRoundIntegrationSeamAppliesOnlyHighConfidenceLiveAdvance() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = swing(at: start.addingTimeInterval(60), latitude: 40, longitude: -75)
        let second = swing(
            at: start.addingTimeInterval(240),
            latitude: 40.002,
            longitude: -75
        )
        var round = GolfRound(
            courseName: "Licensed Course",
            startedAt: start,
            holeCount: .nine,
            swings: [first, second]
        )

        let decision = try XCTUnwrap(round.automaticHoleTransitionDecision(
            finalizedBy: second.id,
            geometry: transitionGeometry()
        ))
        XCTAssertEqual(decision.action, .advance)
        XCTAssertTrue(round.applyAutomaticHoleTransition(decision))
        XCTAssertEqual(round.currentHole, 2)
        XCTAssertEqual(round.holeTransitions.last?.transitionedAt, second.capturedAt)

        let repeated = round.automaticHoleTransitionDecision(
            finalizedBy: second.id,
            geometry: transitionGeometry()
        )
        XCTAssertEqual(repeated?.action, .useRecordedBoundary)
        XCTAssertFalse(round.applyAutomaticHoleTransition(try XCTUnwrap(repeated)))
    }

    func testReviewAndFinishedRoundCannotMutateHoleTimeline() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = swing(at: start.addingTimeInterval(60), latitude: 40, longitude: -75)
        let second = swing(
            at: start.addingTimeInterval(10 * 60),
            latitude: 40.001,
            longitude: -75
        )
        var reviewRound = GolfRound(
            courseName: "No Geometry",
            startedAt: start,
            holeCount: .nine,
            swings: [first, second]
        )
        let review = try XCTUnwrap(reviewRound.automaticHoleTransitionDecision(
            finalizedBy: second.id
        ))
        XCTAssertEqual(review.action, .review)
        XCTAssertFalse(reviewRound.applyAutomaticHoleTransition(review))
        XCTAssertEqual(reviewRound.currentHole, 1)

        let teeSwing = swing(
            at: second.capturedAt,
            latitude: 40.002,
            longitude: -75
        )
        var finishedRound = GolfRound(
            courseName: "Finished",
            startedAt: start,
            holeCount: .nine,
            swings: [first, teeSwing]
        )
        let advance = try XCTUnwrap(finishedRound.automaticHoleTransitionDecision(
            finalizedBy: teeSwing.id,
            geometry: transitionGeometry()
        ))
        XCTAssertEqual(advance.action, .advance)
        finishedRound.markFinished(at: teeSwing.capturedAt.addingTimeInterval(60))
        XCTAssertFalse(finishedRound.applyAutomaticHoleTransition(advance))
        XCTAssertEqual(finishedRound.currentHole, 1)
    }

    func testRoundTimelineFinalizerSuppressesCrossHoleSegmentAndKeepsSameHoleSegment() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = swing(at: start.addingTimeInterval(60), latitude: 40, longitude: -75)
        let second = swing(at: start.addingTimeInterval(180), latitude: 40.001, longitude: -75)
        let third = swing(at: start.addingTimeInterval(420), latitude: 40.002, longitude: -75)
        var round = GolfRound(
            courseName: "Timeline Course",
            startedAt: start,
            holeCount: .nine,
            swings: [first, second, third]
        )
        XCTAssertTrue(round.moveHole(by: 1, at: start.addingTimeInterval(300)))

        round.finalizeWHOOPTriggeredShotIntervals()

        XCTAssertEqual(round.swings[0].shotInterval?.distanceStatus, .measured)
        XCTAssertNotNil(round.swings[0].shotInterval?.straightLineDisplacementYards)
        XCTAssertEqual(round.swings[1].shotInterval?.exclusionReason, .confirmedHoleTransition)
        XCTAssertNil(round.swings[1].shotInterval?.straightLineDisplacementYards)
        XCTAssertEqual(round.swings[1].shotInterval?.finalizedBySwingID, third.id)
        XCTAssertNil(round.swings[2].shotInterval)
    }

    func testRoundFinalizerCanWithholdUnresolvedReviewCandidate() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = swing(at: start.addingTimeInterval(60), latitude: 40, longitude: -75)
        let second = swing(at: start.addingTimeInterval(600), latitude: 40.001, longitude: -75)
        var round = GolfRound(
            courseName: "Review Course",
            startedAt: start,
            holeCount: .nine,
            swings: [first, second]
        )

        round.finalizeWHOOPTriggeredShotIntervals(
            pendingBoundaryDestinationSwingIDs: [second.id]
        )

        XCTAssertEqual(round.swings[0].shotInterval?.exclusionReason, .possibleHoleTransition)
        XCTAssertNil(round.swings[0].shotInterval?.straightLineDisplacementYards)
    }

    private func transitionGeometry() -> GolfHoleTransitionGeometry {
        GolfHoleTransitionGeometry(
            courseIdentifier: "licensed-course-id",
            fromHole: 1,
            toHole: 2,
            currentGreen: GolfHoleSpatialRegion(
                latitude: 40,
                longitude: -75,
                radiusMeters: 30
            ),
            nextTeeRegions: [
                GolfHoleSpatialRegion(
                    latitude: 40.002,
                    longitude: -75,
                    radiusMeters: 30
                )
            ],
            attribution: GolfHoleGeometryAttribution(
                providerName: "Licensed Test Provider",
                datasetVersion: "test-v1",
                licenseNotice: "Test fixture only"
            )
        )
    }

    private func swing(
        at date: Date,
        latitude: Double,
        longitude: Double,
        source: MetricSource = .whoopMotion,
        locationSource: MetricSource = .iphoneGPS,
        locationInputSources: [MetricSource] = []
    ) -> GolfSwingMetrics {
        let gpsProvenance = DataProvenance(
            source: locationSource,
            observedAt: date,
            receivedAt: date,
            quality: .verified,
            inputSources: locationInputSources
        )
        return GolfSwingMetrics(
            capturedAt: date,
            peakG: 7.4,
            provenance: DataProvenance(
                source: source,
                observedAt: date,
                receivedAt: date,
                quality: .estimated
            ),
            location: SwingLocationObservation(
                latitude: latitude,
                longitude: longitude,
                altitudeMeters: nil,
                horizontalAccuracyMeters: 4,
                capturedAt: date,
                provenance: gpsProvenance
            ),
            locationCorrelationMethod: .interpolatedTimelineFix
        )
    }
}

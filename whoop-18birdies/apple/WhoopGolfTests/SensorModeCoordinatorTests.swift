import XCTest
@testable import WhoopGolf

final class SensorModeCoordinatorTests: XCTestCase {
    func testWhoopOnlyUsesHistoricalMotionAndExplicitIPhoneSpatialProvider() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                iphoneLocation: .precise
            )
        )

        XCTAssertEqual(plan.mode, .whoopOnly)
        XCTAssertEqual(plan.operationalState, .delayedPostRoundCapture)
        XCTAssertEqual(plan.swingCapture, .whoopHistoricalMotion)
        XCTAssertEqual(plan.canonicalSwingSource, .whoopMotion)
        XCTAssertEqual(plan.spatialProvider, .iphoneGPS)
        XCTAssertTrue(plan.canReconstructSwingPostRound)
        XCTAssertFalse(plan.canCaptureSwingLive)
        XCTAssertTrue(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.hapticRoute, .iphone)
        XCTAssertEqual(plan.hapticTiming, .delayedAtHistoricalImport)
        XCTAssertTrue(plan.constraints.contains(.whoopHasNoBuiltInGPS))
        XCTAssertTrue(plan.constraints.contains(.whoopHistoricalMotionPending))
        XCTAssertTrue(plan.constraints.contains(.whoopLiveRawMotionUnavailable))
        XCTAssertTrue(plan.constraints.contains(.whoopBandHapticUnavailable))
    }

    func testWhoopOnlyKeepsSwingCaptureWhenLocationIsUnavailableButWithholdsDistance() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalMotionAvailable: true),
                iphoneLocation: .unavailable
            )
        )

        XCTAssertEqual(plan.mode, .whoopOnly)
        XCTAssertEqual(plan.operationalState, .distanceUnavailable)
        XCTAssertTrue(plan.canReconstructSwingPostRound)
        XCTAssertFalse(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.spatialProvider, .unavailable)
        XCTAssertTrue(plan.constraints.contains(.iphoneLocationUnavailable))
    }

    func testWatchOnlyCanRecordLocallyWhileWatchConnectivityIsNotReachable() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    isReachable: false,
                    synchronizedLocationAvailable: true
                )
            )
        )

        XCTAssertEqual(plan.mode, .appleWatchOnly)
        XCTAssertEqual(plan.operationalState, .ready)
        XCTAssertEqual(plan.swingCapture, .appleWatchMotion)
        XCTAssertEqual(plan.canonicalSwingSource, .appleWatch)
        XCTAssertEqual(plan.spatialProvider, .appleWatchGPS)
        XCTAssertTrue(plan.canCaptureSwingLive)
        XCTAssertTrue(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.hapticRoute, .appleWatchLocal)
        XCTAssertEqual(plan.hapticTiming, .immediateAtLiveDetection)
        XCTAssertTrue(plan.constraints.contains(.watchNotReachable))
    }

    func testDurableWatchSessionIsARealPostRoundSourceWithoutClaimingLiveCapture() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                appleWatch: AppleWatchSensorCapabilities(
                    activeSessionSourceAvailable: true,
                    synchronizedLocationAvailable: true
                )
            )
        )

        XCTAssertEqual(plan.mode, .appleWatchOnly)
        XCTAssertEqual(plan.operationalState, .delayedPostRoundCapture)
        XCTAssertFalse(plan.canCaptureSwingLive)
        XCTAssertTrue(plan.canReconstructSwingPostRound)
        XCTAssertTrue(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.hapticRoute, .iphone)
        XCTAssertEqual(plan.hapticTiming, .delayedAtHistoricalImport)
    }

    func testWatchOnlyDoesNotSilentlyReplaceMissingWatchGPSWithIPhoneGPS() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    isReachable: true,
                    synchronizedLocationAvailable: false
                ),
                iphoneLocation: .precise
            )
        )

        XCTAssertEqual(plan.mode, .appleWatchOnly)
        XCTAssertEqual(plan.operationalState, .distanceUnavailable)
        XCTAssertEqual(plan.spatialProvider, .unavailable)
        XCTAssertFalse(plan.canMeasureShotDistance)
        XCTAssertTrue(plan.canCaptureSwingLive)
        XCTAssertTrue(plan.constraints.contains(.watchSynchronizedLocationUnavailable))
    }

    func testHybridUsesWatchForLiveCanonicalEventAndWhoopForDelayedEnrichment() {
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

        XCTAssertEqual(plan.mode, .hybrid)
        XCTAssertEqual(plan.operationalState, .liveCaptureWithDelayedEnrichment)
        XCTAssertEqual(plan.swingCapture, .appleWatchMotionWithWhoopEnrichment)
        XCTAssertEqual(plan.canonicalSwingSource, .appleWatch)
        XCTAssertEqual(plan.spatialProvider, .appleWatchGPS)
        XCTAssertTrue(plan.canCaptureSwingLive)
        XCTAssertTrue(plan.canReconstructSwingPostRound)
        XCTAssertTrue(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.hapticRoute, .appleWatchLocal)
        XCTAssertEqual(plan.hapticTiming, .immediateAtLiveDetection)
        XCTAssertTrue(plan.constraints.contains(.whoopHistoricalMotionPending))
    }

    func testFutureAuthorizedWhoopProviderCanEnableLiveBandConfirmationWithoutChangingPolicy() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(
                    authorizedLiveMotionProviderAvailable: true,
                    authorizedBandHapticProviderAvailable: true
                ),
                iphoneLocation: .precise
            )
        )

        XCTAssertEqual(plan.mode, .whoopOnly)
        XCTAssertEqual(plan.operationalState, .ready)
        XCTAssertEqual(plan.swingCapture, .whoopAuthorizedLiveMotion)
        XCTAssertTrue(plan.canCaptureSwingLive)
        XCTAssertEqual(plan.hapticRoute, .whoopBandAuthorizedProvider)
        XCTAssertEqual(plan.hapticTiming, .immediateAtLiveDetection)
        XCTAssertFalse(plan.constraints.contains(.whoopBandHapticUnavailable))
    }

    func testNoConfiguredSwingSourceReturnsUnavailableInsteadOfInventingAMode() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(iphoneLocation: .precise)
        )

        XCTAssertEqual(plan.mode, .unavailable)
        XCTAssertEqual(plan.operationalState, .unavailable)
        XCTAssertEqual(plan.swingCapture, .none)
        XCTAssertNil(plan.canonicalSwingSource)
        XCTAssertFalse(plan.canCaptureSwingLive)
        XCTAssertFalse(plan.canReconstructSwingPostRound)
        XCTAssertFalse(plan.canMeasureShotDistance)
        XCTAssertEqual(plan.constraints, [.noSwingSensorAvailable])
    }

    func testPersistedHybridModeDoesNotSilentlyChangeOwnershipAfterWatchDisconnects() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                iphoneLocation: .precise
            ),
            mode: .hybrid
        )

        XCTAssertEqual(plan.mode, .unavailable)
        XCTAssertEqual(plan.swingCapture, .none)
        XCTAssertFalse(plan.canCaptureSwingLive)
        XCTAssertEqual(plan.constraints, [.noSwingSensorAvailable])
    }

    func testPersistedWatchModeStaysWatchEvenWhenWhoopBecomesAvailable() {
        let plan = SensorModeCoordinator.plan(
            for: SensorCapabilitySnapshot(
                whoop: WhoopSensorCapabilities(historicalCaptureConfigured: true),
                appleWatch: AppleWatchSensorCapabilities(
                    isPaired: true,
                    isAppInstalled: true,
                    synchronizedLocationAvailable: true
                )
            ),
            mode: .appleWatchOnly
        )

        XCTAssertEqual(plan.mode, .appleWatchOnly)
        XCTAssertEqual(plan.swingCapture, .appleWatchMotion)
        XCTAssertEqual(plan.canonicalSwingSource, .appleWatch)
    }
}

final class HybridSwingReconcilerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_786_000_000)

    func testUniqueCrossSourceMatchesCreateOneCanonicalShotPerWatchEvent() throws {
        let watchOne = swing(
            source: .appleWatch,
            offset: 0,
            peakG: 8.1,
            location: location(offset: 0, latitude: 40.0, source: .appleWatch)
        )
        let whoopOne = swing(source: .whoopMotion, offset: 0.24, peakG: 11.8)
        let watchTwo = swing(
            source: .appleWatch,
            offset: 60,
            peakG: 8.4,
            location: location(offset: 60, latitude: 40.001, source: .appleWatch)
        )
        let whoopTwo = swing(source: .whoopMotion, offset: 60.31, peakG: 12.2)

        let result = HybridSwingReconciler.reconcile([
            whoopTwo, watchOne, whoopOne, watchTwo,
        ])

        XCTAssertEqual(result.reconciled.count, 2)
        XCTAssertTrue(result.review.isEmpty)
        XCTAssertEqual(result.reconciled.map(\.canonicalID), [watchOne.id, watchTwo.id])
        XCTAssertEqual(
            result.reconciled.map(\.resolution),
            [.watchCanonicalWithWhoopEnrichment, .watchCanonicalWithWhoopEnrichment]
        )
        XCTAssertEqual(result.reconciled[0].timestampDeltaSeconds ?? 0, 0.24, accuracy: 0.001)

        let first = result.canonicalSwings[0]
        XCTAssertEqual(first.id, watchOne.id)
        XCTAssertEqual(first.capturedAt, watchOne.capturedAt)
        XCTAssertEqual(first.location, watchOne.location)
        XCTAssertEqual(first.peakG, whoopOne.peakG)
        XCTAssertEqual(first.provenance.source, .derived)
        XCTAssertEqual(
            first.provenance.algorithmVersion,
            ReconciledHybridSwing.fusionAlgorithmVersion
        )
        XCTAssertEqual(first.provenance.inputSources.prefix(2), [.appleWatch, .whoopMotion])
        XCTAssertNil(first.shotInterval)

        let finalized = SwingShotIntervalCalculator.finalizingIntervals(
            in: result.canonicalSwings
        )
        let interval = try XCTUnwrap(finalized.first?.shotInterval)
        XCTAssertEqual(interval.elapsedSeconds, 60, accuracy: 0.001)
        XCTAssertGreaterThan(interval.straightLineDisplacementYards ?? 0, 100)
        XCTAssertNil(finalized.last?.shotInterval)
    }

    func testUnmatchedWhoopCandidateIsStagedAndCannotIncreaseShotCount() {
        let watch = swing(source: .appleWatch, offset: 0)
        let whoop = swing(source: .whoopMotion, offset: 20)

        let result = HybridSwingReconciler.reconcile([whoop, watch])

        XCTAssertEqual(result.canonicalSwings.map(\.id), [watch.id])
        XCTAssertEqual(result.reconciled.first?.resolution, .watchCanonicalAwaitingWhoop)
        XCTAssertEqual(result.review.count, 1)
        XCTAssertEqual(result.review.first?.reason, .unmatchedWhoopCandidate)
        XCTAssertEqual(result.review.first?.candidateIDs, [whoop.id])
    }

    func testAmbiguousTimestampComponentIsEntirelyStaged() {
        let watch = swing(source: .appleWatch, offset: 10)
        let earlyWhoop = swing(source: .whoopMotion, offset: 8.6)
        let lateWhoop = swing(source: .whoopMotion, offset: 11.4)

        let result = HybridSwingReconciler.reconcile([earlyWhoop, watch, lateWhoop])

        XCTAssertTrue(result.reconciled.isEmpty)
        XCTAssertEqual(result.review.count, 1)
        XCTAssertEqual(result.review.first?.reason, .ambiguousCrossSourceMatch)
        XCTAssertEqual(Set(result.review.first?.candidateIDs ?? []), [
            watch.id, earlyWhoop.id, lateWhoop.id,
        ])
    }

    func testSubsecondSameSourceCandidatesAreStagedBeforeIntervalCalculation() {
        let first = swing(source: .appleWatch, offset: 0)
        let second = swing(source: .appleWatch, offset: 0.7)

        let result = HybridSwingReconciler.reconcile([first, second])

        XCTAssertTrue(result.canonicalSwings.isEmpty)
        XCTAssertEqual(result.review.count, 1)
        XCTAssertEqual(result.review.first?.reason, .subsecondSameSourceConflict)
        XCTAssertEqual(Set(result.review.first?.candidateIDs ?? []), [first.id, second.id])
    }

    func testExistingWatchIntervalIsClearedUntilReconciledTimelineIsRebuilt() {
        var watch = swing(source: .appleWatch, offset: 0)
        watch.shotInterval = SwingShotInterval(
            finalizedBySwingID: UUID(),
            finalizedAt: start.addingTimeInterval(0.2),
            elapsedSeconds: 0.2,
            straightLineDisplacementYards: 0,
            distanceUncertaintyYards: 0,
            distanceStatus: .measured,
            provenance: DataProvenance(
                source: .derived,
                observedAt: start,
                quality: .estimated
            )
        )

        let result = HybridSwingReconciler.reconcile([watch])

        XCTAssertEqual(result.canonicalSwings.count, 1)
        XCTAssertNil(result.canonicalSwings[0].shotInterval)
    }

    func testUnsupportedAndDuplicateIdentityCandidatesFailClosed() {
        let sharedID = UUID()
        let first = swing(id: sharedID, source: .appleWatch, offset: 0)
        let duplicate = swing(id: sharedID, source: .whoopMotion, offset: 0.2)
        let manual = swing(source: .manual, offset: 30)

        let result = HybridSwingReconciler.reconcile([first, duplicate, manual])

        XCTAssertTrue(result.reconciled.isEmpty)
        XCTAssertEqual(Set(result.review.map(\.reason)), [.unsupportedSource, .duplicateIdentity])
    }

    private func swing(
        id: UUID = UUID(),
        source: MetricSource,
        offset: TimeInterval,
        peakG: Double = 9,
        location: SwingLocationObservation? = nil
    ) -> GolfSwingMetrics {
        let capturedAt = start.addingTimeInterval(offset)
        return GolfSwingMetrics(
            id: id,
            capturedAt: capturedAt,
            peakG: peakG,
            backswingSeconds: 0.78,
            downswingSeconds: 0.26,
            tempoRatio: 3,
            heartRateBPM: source == .whoopMotion ? 109 : 106,
            detectionConfidence: 0.9,
            provenance: DataProvenance(
                source: source,
                observedAt: capturedAt,
                receivedAt: capturedAt.addingTimeInterval(source == .whoopMotion ? 900 : 0),
                quality: source == .whoopMotion ? .estimated : .verified
            ),
            location: location,
            locationCorrelationMethod: location == nil ? nil : .sensorSynchronized
        )
    }

    private func location(
        offset: TimeInterval,
        latitude: Double,
        source: MetricSource
    ) -> SwingLocationObservation {
        let capturedAt = start.addingTimeInterval(offset)
        return SwingLocationObservation(
            latitude: latitude,
            longitude: -73,
            altitudeMeters: 15,
            horizontalAccuracyMeters: 3,
            capturedAt: capturedAt,
            provenance: DataProvenance(
                source: source,
                observedAt: capturedAt,
                quality: .verified
            )
        )
    }
}

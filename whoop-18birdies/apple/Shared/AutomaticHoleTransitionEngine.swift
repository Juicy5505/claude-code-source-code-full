import Foundation

/// A bounded region supplied by a course-data provider. This type deliberately
/// does not scrape or infer proprietary 18Birdies geometry. A future provider
/// must supply data it is licensed or otherwise authorized to use.
struct GolfHoleSpatialRegion: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && radiusMeters.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
            (3...250).contains(radiusMeters)
    }
}

struct GolfHoleGeometryAttribution: Codable, Hashable, Sendable {
    let providerName: String
    let datasetVersion: String
    let licenseNotice: String

    var isComplete: Bool {
        !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !datasetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The minimum geometry needed to corroborate a transition from one hole to
/// the next. Multiple next-tee regions support different tee boxes.
struct GolfHoleTransitionGeometry: Codable, Hashable, Sendable {
    let courseIdentifier: String
    let fromHole: Int
    let toHole: Int
    let currentGreen: GolfHoleSpatialRegion
    let nextTeeRegions: [GolfHoleSpatialRegion]
    let attribution: GolfHoleGeometryAttribution

    var isValid: Bool {
        !courseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            fromHole >= 1 && toHole == fromHole + 1 &&
            currentGreen.isValid && !nextTeeRegions.isEmpty &&
            nextTeeRegions.allSatisfy(\.isValid) && attribution.isComplete
    }
}

/// Integration seam for a licensed course map vendor. Apple Maps place search
/// identifies a facility only and cannot satisfy this protocol by itself.
protocol GolfHoleGeometryProviding: Sendable {
    func transitionGeometry(
        courseIdentifier: String,
        fromHole: Int,
        toHole: Int
    ) async throws -> GolfHoleTransitionGeometry?
}

enum AutomaticHoleTransitionAction: String, Codable, Hashable, Sendable {
    /// Keep both swings on the current hole and measure the GPS segment.
    case remain
    /// Withhold the segment and ask for one post-round confirmation.
    case review
    /// Append a transition at the destination WHOOP event timestamp.
    case advance
    /// A persisted transition/correction already places the two swings on
    /// different holes; do not append another transition.
    case useRecordedBoundary
}

enum AutomaticHoleTransitionConfidence: String, Codable, Hashable, Sendable {
    case unavailable
    case low
    case medium
    case high
    case confirmed
}

enum AutomaticHoleTransitionEvidence: String, Codable, Hashable, Sendable {
    case whoopMotionPair
    case recordedHoleBoundary
    case licensedCurrentGreenRegion
    case licensedNextTeeRegion
    case enteredHoleScore
    case multipleSwingsOnCurrentHole
    case longInterSwingPause
    case meaningfulGPSDisplacement
    case noLicensedHoleGeometry
    case unusableLocation
    case explicitIPhoneGPSLocation
    case explicitAppleWatchGPSLocation
    case unverifiedSpatialSource
}

struct AutomaticHoleTransitionContext: Hashable, Sendable {
    let currentHole: Int
    let holeCount: GolfHoleCount
    /// Accepted WHOOP swing observations already associated with the current
    /// hole, including `destination` when evaluation occurs after import.
    let whoopSwingCountOnCurrentHole: Int
    /// A user-entered/confirmed stroke total, when one exists.
    let enteredStrokesForCurrentHole: Int?
    /// Non-nil when the persisted timeline or a manual correction already
    /// assigns `destination` to a different hole than `origin`.
    let recordedDestinationHole: Int?
    let geometry: GolfHoleTransitionGeometry?

    init(
        currentHole: Int,
        holeCount: GolfHoleCount,
        whoopSwingCountOnCurrentHole: Int,
        enteredStrokesForCurrentHole: Int? = nil,
        recordedDestinationHole: Int? = nil,
        geometry: GolfHoleTransitionGeometry? = nil
    ) {
        self.currentHole = currentHole
        self.holeCount = holeCount
        self.whoopSwingCountOnCurrentHole = whoopSwingCountOnCurrentHole
        self.enteredStrokesForCurrentHole = enteredStrokesForCurrentHole
        self.recordedDestinationHole = recordedDestinationHole
        self.geometry = geometry
    }
}

/// Codable so an unresolved `.review` decision can live in a protected local
/// review ledger without recomputing or silently changing after an app restart.
struct AutomaticHoleTransitionDecision: Codable, Hashable, Sendable {
    let action: AutomaticHoleTransitionAction
    let confidence: AutomaticHoleTransitionConfidence
    let fromHole: Int
    let destinationHole: Int?
    /// The destination WHOOP event owns an accepted boundary at this exact
    /// timestamp, matching `GolfRound.moveHole(by:at:)` boundary semantics.
    let boundaryAt: Date?
    let intervalDisposition: SwingShotIntervalDisposition
    let evidence: [AutomaticHoleTransitionEvidence]
    let geometryAttribution: GolfHoleGeometryAttribution?
    /// Coordinate-producing inputs only. `.whoopMotion` is intentionally never
    /// included because the band event supplies motion/time, not GPS.
    let spatialInputSources: [MetricSource]
}

/// Conservative, deterministic transition inference. WHOOP motion supplies
/// the two swing events; iPhone GPS supplies positions. Without authorized
/// per-hole geometry, time/distance patterns can request review but can never
/// silently advance the hole.
enum AutomaticHoleTransitionEngine {
    struct Configuration: Hashable, Sendable {
        let minimumSwingsOnHole: Int
        let reviewedScoreMinimumPause: TimeInterval
        let unscoredMinimumPause: TimeInterval
        let minimumDisplacementYards: Double

        init(
            minimumSwingsOnHole: Int = 2,
            reviewedScoreMinimumPause: TimeInterval = 120,
            unscoredMinimumPause: TimeInterval = 8 * 60,
            minimumDisplacementYards: Double = 25
        ) {
            self.minimumSwingsOnHole = max(1, minimumSwingsOnHole)
            self.reviewedScoreMinimumPause = max(30, reviewedScoreMinimumPause)
            self.unscoredMinimumPause = max(
                self.reviewedScoreMinimumPause,
                unscoredMinimumPause
            )
            self.minimumDisplacementYards = max(5, minimumDisplacementYards)
        }
    }

    static func evaluate(
        origin: GolfSwingMetrics,
        destination: GolfSwingMetrics,
        context: AutomaticHoleTransitionContext,
        configuration: Configuration = Configuration()
    ) -> AutomaticHoleTransitionDecision {
        let baseEvidence: [AutomaticHoleTransitionEvidence] =
            origin.provenance.source == .whoopMotion &&
            destination.provenance.source == .whoopMotion
                ? [.whoopMotionPair]
                : []

        guard context.currentHole >= 1,
              context.currentHole <= context.holeCount.rawValue,
              destination.capturedAt > origin.capturedAt,
              context.currentHole < context.holeCount.rawValue,
              baseEvidence == [.whoopMotionPair]
        else {
            return remain(context: context, evidence: baseEvidence)
        }

        if let recordedHole = context.recordedDestinationHole,
           (1...context.holeCount.rawValue).contains(recordedHole),
           recordedHole != context.currentHole {
            return AutomaticHoleTransitionDecision(
                action: .useRecordedBoundary,
                confidence: .confirmed,
                fromHole: context.currentHole,
                destinationHole: recordedHole,
                boundaryAt: destination.capturedAt,
                intervalDisposition: .withholdConfirmedHoleTransition,
                evidence: baseEvidence + [.recordedHoleBoundary],
                geometryAttribution: nil,
                spatialInputSources: spatialInputSources(origin, destination)
            )
        }

        let elapsed = destination.capturedAt.timeIntervalSince(origin.capturedAt)
        let originSpatialSources = SwingShotIntervalCalculator.explicitSpatialInputSources(
            origin.location
        )
        let destinationSpatialSources = SwingShotIntervalCalculator.explicitSpatialInputSources(
            destination.location
        )
        let sourceInputs = spatialInputSources(origin, destination)
        let hasUnverifiedCoordinate =
            (origin.location != nil && originSpatialSources.isEmpty) ||
            (destination.location != nil && destinationSpatialSources.isEmpty)
        guard !hasUnverifiedCoordinate else {
            return AutomaticHoleTransitionDecision(
                action: .remain,
                confidence: .unavailable,
                fromHole: context.currentHole,
                destinationHole: nil,
                boundaryAt: nil,
                intervalDisposition: .withholdUnverifiedSpatialSource,
                evidence: baseEvidence + [.unverifiedSpatialSource],
                geometryAttribution: nil,
                spatialInputSources: []
            )
        }
        let displacement = measuredDisplacementYards(origin: origin, destination: destination)
        let hasMultipleSwings = context.whoopSwingCountOnCurrentHole >=
            configuration.minimumSwingsOnHole
        let scoreSupportsCompletion = context.enteredStrokesForCurrentHole.map {
            $0 > 0 && context.whoopSwingCountOnCurrentHole >= $0
        } ?? false

        var patternEvidence = baseEvidence
        if sourceInputs.contains(.iphoneGPS) { patternEvidence.append(.explicitIPhoneGPSLocation) }
        if sourceInputs.contains(.appleWatch) { patternEvidence.append(.explicitAppleWatchGPSLocation) }
        if hasMultipleSwings { patternEvidence.append(.multipleSwingsOnCurrentHole) }
        if scoreSupportsCompletion { patternEvidence.append(.enteredHoleScore) }
        if elapsed >= configuration.reviewedScoreMinimumPause {
            patternEvidence.append(.longInterSwingPause)
        }
        if displacement.map({ $0 >= configuration.minimumDisplacementYards }) == true {
            patternEvidence.append(.meaningfulGPSDisplacement)
        }

        if let geometry = validGeometry(context.geometry, context: context),
           let originLocation = origin.location,
           let destinationLocation = destination.location {
            let originInGreen = definitelyContains(originLocation, in: geometry.currentGreen)
            let destinationInNextTee = geometry.nextTeeRegions.contains {
                definitelyContains(destinationLocation, in: $0)
            }

            if originInGreen && destinationInNextTee {
                return AutomaticHoleTransitionDecision(
                    action: .advance,
                    confidence: .high,
                    fromHole: context.currentHole,
                    destinationHole: context.currentHole + 1,
                    boundaryAt: destination.capturedAt,
                    intervalDisposition: .withholdConfirmedHoleTransition,
                    evidence: patternEvidence + [
                        .licensedCurrentGreenRegion,
                        .licensedNextTeeRegion,
                    ],
                    geometryAttribution: geometry.attribution,
                    spatialInputSources: sourceInputs
                )
            }

            if destinationInNextTee && hasMultipleSwings &&
                (scoreSupportsCompletion || isStrongPattern(
                    elapsed: elapsed,
                    displacement: displacement,
                    minimumPause: configuration.unscoredMinimumPause,
                    configuration: configuration
                )) {
                return AutomaticHoleTransitionDecision(
                    action: .review,
                    confidence: scoreSupportsCompletion ? .high : .medium,
                    fromHole: context.currentHole,
                    destinationHole: context.currentHole + 1,
                    boundaryAt: destination.capturedAt,
                    intervalDisposition: .withholdPendingHoleTransitionReview,
                    evidence: patternEvidence + [.licensedNextTeeRegion],
                    geometryAttribution: geometry.attribution,
                    spatialInputSources: sourceInputs
                )
            }

            return remain(
                context: context,
                evidence: patternEvidence,
                spatialInputSources: sourceInputs
            )
        }

        patternEvidence.append(.noLicensedHoleGeometry)
        guard displacement != nil else {
            patternEvidence.append(.unusableLocation)
            return remain(
                context: context,
                evidence: patternEvidence,
                spatialInputSources: sourceInputs
            )
        }

        let minimumPause = scoreSupportsCompletion
            ? configuration.reviewedScoreMinimumPause
            : configuration.unscoredMinimumPause
        if hasMultipleSwings && isStrongPattern(
            elapsed: elapsed,
            displacement: displacement,
            minimumPause: minimumPause,
            configuration: configuration
        ) {
            return AutomaticHoleTransitionDecision(
                action: .review,
                confidence: scoreSupportsCompletion ? .medium : .low,
                fromHole: context.currentHole,
                destinationHole: context.currentHole + 1,
                boundaryAt: destination.capturedAt,
                intervalDisposition: .withholdPendingHoleTransitionReview,
                evidence: patternEvidence,
                geometryAttribution: nil,
                spatialInputSources: sourceInputs
            )
        }

        return remain(
            context: context,
            evidence: patternEvidence,
            spatialInputSources: sourceInputs
        )
    }

    private static func remain(
        context: AutomaticHoleTransitionContext,
        evidence: [AutomaticHoleTransitionEvidence],
        spatialInputSources: [MetricSource] = []
    ) -> AutomaticHoleTransitionDecision {
        AutomaticHoleTransitionDecision(
            action: .remain,
            confidence: .unavailable,
            fromHole: context.currentHole,
            destinationHole: nil,
            boundaryAt: nil,
            intervalDisposition: .measure,
            evidence: evidence,
            geometryAttribution: nil,
            spatialInputSources: spatialInputSources
        )
    }

    private static func isStrongPattern(
        elapsed: TimeInterval,
        displacement: Double?,
        minimumPause: TimeInterval,
        configuration: Configuration
    ) -> Bool {
        elapsed >= minimumPause &&
            displacement.map { $0 >= configuration.minimumDisplacementYards } == true
    }

    private static func validGeometry(
        _ geometry: GolfHoleTransitionGeometry?,
        context: AutomaticHoleTransitionContext
    ) -> GolfHoleTransitionGeometry? {
        guard let geometry,
              geometry.isValid,
              geometry.fromHole == context.currentHole,
              geometry.toHole == context.currentHole + 1
        else { return nil }
        return geometry
    }

    private static func measuredDisplacementYards(
        origin: GolfSwingMetrics,
        destination: GolfSwingMetrics
    ) -> Double? {
        guard let first = usableFix(origin.location),
              let second = usableFix(destination.location)
        else { return nil }
        return ShotDistanceCalculator.displacementYards(from: first, to: second)
    }

    /// Uses a conservative "definitely inside" test. GPS uncertainty must fit
    /// wholly inside the supplied region; merely overlapping its edge cannot
    /// trigger an autonomous hole change.
    private static func definitelyContains(
        _ observation: SwingLocationObservation,
        in region: GolfHoleSpatialRegion
    ) -> Bool {
        guard region.isValid, let fix = usableFix(observation) else { return false }
        let center = LocationFix(
            latitude: region.latitude,
            longitude: region.longitude,
            altitudeMeters: nil,
            horizontalAccuracyMeters: 0,
            capturedAt: fix.capturedAt,
            provenance: fix.provenance
        )
        guard let yards = ShotDistanceCalculator.displacementYards(from: center, to: fix) else {
            return false
        }
        let meters = yards * 0.9144
        return meters + fix.horizontalAccuracyMeters <= region.radiusMeters
    }

    private static func usableFix(_ observation: SwingLocationObservation?) -> LocationFix? {
        guard let observation,
              observation.hasValidCoordinate,
              !SwingShotIntervalCalculator.explicitSpatialInputSources(observation).isEmpty,
              let accuracy = observation.horizontalAccuracyMeters,
              accuracy.isFinite,
              accuracy >= 0,
              accuracy <= SwingShotIntervalCalculator.maximumHorizontalAccuracyMeters
        else { return nil }
        return LocationFix(
            latitude: observation.latitude,
            longitude: observation.longitude,
            altitudeMeters: observation.altitudeMeters,
            horizontalAccuracyMeters: accuracy,
            capturedAt: observation.capturedAt,
            provenance: observation.provenance
        )
    }

    private static func spatialInputSources(
        _ origin: GolfSwingMetrics,
        _ destination: GolfSwingMetrics
    ) -> [MetricSource] {
        let candidates = SwingShotIntervalCalculator.explicitSpatialInputSources(origin.location) +
            SwingShotIntervalCalculator.explicitSpatialInputSources(destination.location)
        return candidates.reduce(into: []) { sources, source in
            if !sources.contains(source) { sources.append(source) }
        }
    }
}

extension GolfRound {
    /// Builds the conservative decision context for one destination WHOOP
    /// event. This is the integration seam for a live detector: fetch licensed
    /// geometry through `GolfHoleGeometryProviding`, evaluate, then call
    /// `applyAutomaticHoleTransition` only when the decision says `.advance`.
    func automaticHoleTransitionDecision(
        finalizedBy destinationSwingID: UUID,
        geometry: GolfHoleTransitionGeometry? = nil
    ) -> AutomaticHoleTransitionDecision? {
        let ordered = swings.sorted {
            if $0.capturedAt == $1.capturedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.capturedAt < $1.capturedAt
        }
        guard let destinationIndex = ordered.firstIndex(where: { $0.id == destinationSwingID }),
              destinationIndex > ordered.startIndex else { return nil }
        let origin = ordered[destinationIndex - 1]
        let destination = ordered[destinationIndex]
        guard let originHole = holeAssignment(for: origin.id)?.hole else { return nil }
        let destinationHole = holeAssignment(for: destination.id)?.hole
        let recordedDestinationHole = destinationHole != originHole ? destinationHole : nil
        let prefix = ordered[...destinationIndex]
        let whoopCount = prefix.lazy.filter { swing in
            swing.provenance.source == .whoopMotion &&
                holeAssignment(for: swing.id)?.hole == originHole
        }.count
        let strokes = holes.first(where: { $0.number == originHole })?.strokes
        return AutomaticHoleTransitionEngine.evaluate(
            origin: origin,
            destination: destination,
            context: AutomaticHoleTransitionContext(
                currentHole: originHole,
                holeCount: holeCount,
                whoopSwingCountOnCurrentHole: whoopCount,
                enteredStrokesForCurrentHole: strokes,
                recordedDestinationHole: recordedDestinationHole,
                geometry: geometry
            )
        )
    }

    /// Applies only a high-confidence, next-hole decision to a live draft.
    /// Reviews, recorded boundaries, stale decisions, skipped holes, and
    /// finished rounds all fail closed through validation in this method and
    /// `moveHole(by:at:)`.
    @discardableResult
    mutating func applyAutomaticHoleTransition(
        _ decision: AutomaticHoleTransitionDecision
    ) -> Bool {
        guard decision.action == .advance,
              decision.confidence == .high,
              decision.fromHole == currentHole,
              decision.destinationHole == currentHole + 1,
              decision.destinationHole.map({ $0 <= holeCount.rawValue }) == true,
              let boundaryAt = decision.boundaryAt
        else { return false }
        return moveHole(by: 1, at: boundaryAt)
    }

    /// Rebuilds WHOOP-triggered shot intervals from the persisted hole
    /// timeline/corrections and any unresolved automatic-boundary reviews.
    /// Replace direct calls to `SwingShotIntervalCalculator.finalizingIntervals`
    /// in WHOOP import paths with this method after appending accepted swings.
    mutating func finalizeWHOOPTriggeredShotIntervals(
        pendingBoundaryDestinationSwingIDs: Set<UUID> = []
    ) {
        let assignments = Dictionary(uniqueKeysWithValues: swings.compactMap { swing in
            holeAssignment(for: swing.id).map { (swing.id, $0.hole) }
        })
        swings = SwingShotIntervalCalculator.finalizingIntervals(in: swings) { origin, destination in
            if pendingBoundaryDestinationSwingIDs.contains(destination.id) {
                return .withholdPendingHoleTransitionReview
            }
            let originHole = assignments[origin.id] ?? nil
            let destinationHole = assignments[destination.id] ?? nil
            if let originHole, let destinationHole, originHole != destinationHole {
                return .withholdConfirmedHoleTransition
            }
            return .measure
        }
    }
}

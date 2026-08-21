import Foundation

/// Whether the GPS segment between two WHOOP-triggered swing timestamps is a
/// shot-distance candidate. A confirmed or reviewable hole boundary must not
/// become yardage merely because both endpoints have valid iPhone GPS fixes.
enum SwingShotIntervalDisposition: String, Codable, Hashable, Sendable {
    case measure
    case withholdConfirmedHoleTransition
    case withholdPendingHoleTransitionReview
    case withholdUnverifiedSpatialSource
}

/// Sensor-neutral derivation of elapsed time and GPS displacement between
/// consecutive swing observations.
enum SwingShotIntervalCalculator {
    static let algorithmVersion = "whoop-triggered-swing-to-swing-gps-displacement-v2"
    static let maximumHorizontalAccuracyMeters = 25.0
    static let maximumLocationAgeSeconds: TimeInterval = 10

    /// Returns observations in timestamp order. Every observation except the
    /// last receives an interval finalized by the next swing. The last remains
    /// pending (`shotInterval == nil`) until a later observation arrives.
    static func finalizingIntervals(in observations: [GolfSwingMetrics]) -> [GolfSwingMetrics] {
        finalizingIntervals(in: observations) { _, _ in .measure }
    }

    /// Rebuilds every interval while allowing a hole-transition engine or the
    /// persisted hole timeline to suppress cross-hole segments. The WHOOP
    /// event times define the swing pair; iPhone GPS supplies the spatial
    /// displacement. Neither source is relabeled as ball or clubhead telemetry.
    static func finalizingIntervals(
        in observations: [GolfSwingMetrics],
        disposition: (GolfSwingMetrics, GolfSwingMetrics) -> SwingShotIntervalDisposition
    ) -> [GolfSwingMetrics] {
        var ordered = observations.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.capturedAt < $1.capturedAt
        }

        for index in ordered.indices {
            ordered[index].shotInterval = nil
        }
        guard ordered.count > 1 else { return ordered }

        for index in ordered.startIndex..<(ordered.endIndex - 1) {
            ordered[index].shotInterval = interval(
                from: ordered[index],
                finalizedBy: ordered[index + 1],
                disposition: disposition(ordered[index], ordered[index + 1])
            )
        }
        return ordered
    }

    static func interval(
        from origin: GolfSwingMetrics,
        finalizedBy destination: GolfSwingMetrics,
        disposition: SwingShotIntervalDisposition = .measure
    ) -> SwingShotInterval {
        let elapsedSeconds = destination.capturedAt.timeIntervalSince(origin.capturedAt)
        let receivedAt = max(origin.provenance.receivedAt, destination.provenance.receivedAt)
        let evaluation: (
            distanceYards: Double?,
            uncertaintyYards: Double?,
            status: SwingShotDistanceStatus,
            quality: DataQuality
        )
        let exclusionReason: SwingShotIntervalExclusionReason?
        switch disposition {
        case .measure:
            if Self.hasExplicitSpatialSource(origin.location),
               Self.hasExplicitSpatialSource(destination.location) {
                evaluation = evaluateDistance(from: origin, to: destination)
                exclusionReason = nil
            } else if origin.location != nil || destination.location != nil {
                evaluation = (nil, nil, .missingLocation, .unavailable)
                exclusionReason = .unverifiedSpatialSource
            } else {
                evaluation = evaluateDistance(from: origin, to: destination)
                exclusionReason = nil
            }
        case .withholdConfirmedHoleTransition:
            // `distanceStatus` remains backward-compatible for older UI code;
            // the orthogonal exclusion reason is authoritative here.
            evaluation = (nil, nil, .missingLocation, .unavailable)
            exclusionReason = .confirmedHoleTransition
        case .withholdPendingHoleTransitionReview:
            evaluation = (nil, nil, .missingLocation, .unavailable)
            exclusionReason = .possibleHoleTransition
        case .withholdUnverifiedSpatialSource:
            evaluation = (nil, nil, .missingLocation, .unavailable)
            exclusionReason = .unverifiedSpatialSource
        }

        return SwingShotInterval(
            finalizedBySwingID: destination.id,
            finalizedAt: destination.capturedAt,
            elapsedSeconds: max(0, elapsedSeconds),
            straightLineDisplacementYards: evaluation.distanceYards,
            distanceUncertaintyYards: evaluation.uncertaintyYards,
            distanceStatus: evaluation.status,
            exclusionReason: exclusionReason,
            provenance: DataProvenance(
                source: .derived,
                observedAt: destination.capturedAt,
                receivedAt: receivedAt,
                quality: evaluation.quality,
                algorithmVersion: algorithmVersion,
                inputSources: inputSources(origin: origin, destination: destination)
            )
        )
    }

    private static func evaluateDistance(
        from origin: GolfSwingMetrics,
        to destination: GolfSwingMetrics
    ) -> (
        distanceYards: Double?,
        uncertaintyYards: Double?,
        status: SwingShotDistanceStatus,
        quality: DataQuality
    ) {
        guard destination.capturedAt > origin.capturedAt else {
            return (nil, nil, .nonIncreasingTimestamps, .unavailable)
        }
        guard let originLocation = origin.location,
              let destinationLocation = destination.location,
              originLocation.hasValidCoordinate,
              destinationLocation.hasValidCoordinate else {
            return (nil, nil, .missingLocation, .unavailable)
        }
        guard abs(originLocation.capturedAt.timeIntervalSince(origin.capturedAt))
                <= maximumLocationAgeSeconds,
              abs(destinationLocation.capturedAt.timeIntervalSince(destination.capturedAt))
                <= maximumLocationAgeSeconds else {
            return (nil, nil, .staleLocation, .stale)
        }
        guard let originAccuracy = originLocation.horizontalAccuracyMeters,
              let destinationAccuracy = destinationLocation.horizontalAccuracyMeters else {
            return (nil, nil, .missingHorizontalAccuracy, .unavailable)
        }
        guard originAccuracy.isFinite,
              destinationAccuracy.isFinite,
              originAccuracy >= 0,
              destinationAccuracy >= 0,
              originAccuracy <= maximumHorizontalAccuracyMeters,
              destinationAccuracy <= maximumHorizontalAccuracyMeters else {
            return (nil, nil, .lowHorizontalAccuracy, .unavailable)
        }

        let first = LocationFix(
            latitude: originLocation.latitude,
            longitude: originLocation.longitude,
            altitudeMeters: originLocation.altitudeMeters,
            horizontalAccuracyMeters: originAccuracy,
            capturedAt: originLocation.capturedAt,
            provenance: originLocation.provenance
        )
        let second = LocationFix(
            latitude: destinationLocation.latitude,
            longitude: destinationLocation.longitude,
            altitudeMeters: destinationLocation.altitudeMeters,
            horizontalAccuracyMeters: destinationAccuracy,
            capturedAt: destinationLocation.capturedAt,
            provenance: destinationLocation.provenance
        )
        guard let distance = ShotDistanceCalculator.displacementYards(from: first, to: second) else {
            return (nil, nil, .missingLocation, .unavailable)
        }
        return (
            distance,
            ShotDistanceCalculator.uncertaintyYards(first: first, second: second),
            .measured,
            .estimated
        )
    }

    private static func inputSources(
        origin: GolfSwingMetrics,
        destination: GolfSwingMetrics
    ) -> [MetricSource] {
        var candidates = [origin.provenance.source]
        if let location = origin.location {
            candidates.append(location.provenance.source)
            candidates.append(contentsOf: location.provenance.inputSources)
        }
        candidates.append(destination.provenance.source)
        if let location = destination.location {
            candidates.append(location.provenance.source)
            candidates.append(contentsOf: location.provenance.inputSources)
        }
        return candidates.reduce(into: []) { sources, source in
            if !sources.contains(source) {
                sources.append(source)
            }
        }
    }

    /// Accepts only a real coordinate-producing source. A WHOOP motion event
    /// can trigger interval finalization but cannot self-assert GPS provenance.
    static func explicitSpatialInputSources(
        _ observation: SwingLocationObservation?
    ) -> [MetricSource] {
        guard let observation else { return [] }
        let candidates = [observation.provenance.source] + observation.provenance.inputSources
        return candidates.reduce(into: []) { sources, source in
            guard source == .iphoneGPS || source == .appleWatch else { return }
            if !sources.contains(source) { sources.append(source) }
        }
    }

    private static func hasExplicitSpatialSource(
        _ observation: SwingLocationObservation?
    ) -> Bool {
        !explicitSpatialInputSources(observation).isEmpty
    }
}

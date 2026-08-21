import Foundation

/// Licensed (or otherwise authorized) front / middle / back green targets for
/// one hole. Apple Maps facility search cannot produce this type — a course
/// POI is not a green map.
struct GolfHoleGreenTargets: Codable, Hashable, Sendable {
    let courseIdentifier: String
    let holeNumber: Int
    let frontLatitude: Double
    let frontLongitude: Double
    let middleLatitude: Double
    let middleLongitude: Double
    let backLatitude: Double
    let backLongitude: Double
    let attribution: GolfHoleGeometryAttribution

    var isValid: Bool {
        holeNumber >= 1 &&
            !courseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            attribution.isComplete &&
            Self.isValidCoordinate(latitude: frontLatitude, longitude: frontLongitude) &&
            Self.isValidCoordinate(latitude: middleLatitude, longitude: middleLongitude) &&
            Self.isValidCoordinate(latitude: backLatitude, longitude: backLongitude)
    }

    private static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Optional future provider for per-hole F/M/B targeting overlay. Distinct from
/// facility search (`GolfCourseLocator`) and from swing-to-swing stroke yards.
protocol GolfHoleYardageProviding: Sendable {
    func greenTargets(
        courseIdentifier: String,
        holeNumber: Int
    ) async throws -> GolfHoleGreenTargets?
}

/// Phone GPS shot chain + optional green targeting → Watch live-face yards.
///
/// **Stroke yards** = straight-line phone GPS between consecutive verified
/// swings (`SwingShotInterval` via `ShotDistanceCalculator`). The newest swing
/// stays pending until the next arrives.
///
/// **Front/mid/back** = optional targeting overlay from authorized hole
/// geometry only. `GolfCourseLocator` facility search never invents pins.
enum PhoneYardageBridge {
    struct GreenYards: Equatable, Sendable {
        let frontYards: Int?
        let middleYards: Int?
        let backYards: Int?

        var hasAny: Bool {
            frontYards != nil || middleYards != nil || backYards != nil
        }
    }

    /// Last measured swing→swing displacement on the shot chain.
    ///
    /// Walks newest-first among intervals that are `.measured` with finite
    /// yards and no hole-boundary exclusion. Returns nil when the chain has
    /// fewer than two verified GPS endpoints (honest empty — never faked).
    static func lastMeasuredShotYards(from swings: [GolfSwingMetrics]) -> Int? {
        let ordered = swings.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.capturedAt < $1.capturedAt
        }
        for swing in ordered.reversed() {
            guard let interval = swing.shotInterval,
                  interval.exclusionReason == nil,
                  interval.distanceStatus == .measured,
                  let yards = interval.straightLineDisplacementYards,
                  yards.isFinite, yards >= 0
            else {
                continue
            }
            return Int(yards.rounded())
        }
        return nil
    }

    /// Straight-line yards from a usable phone GPS fix to licensed green
    /// targets. Incomplete input → all-nil (targeting overlay only).
    static func greenYards(
        from phoneFix: LocationFix?,
        targets: GolfHoleGreenTargets?
    ) -> GreenYards {
        guard let phoneFix, phoneFix.isUsableForShotDistance,
              let targets, targets.isValid,
              phoneFix.provenance.source == .iphoneGPS ||
                phoneFix.provenance.source == .derived
        else {
            return GreenYards(frontYards: nil, middleYards: nil, backYards: nil)
        }

        return GreenYards(
            frontYards: roundedYards(
                from: phoneFix,
                toLatitude: targets.frontLatitude,
                toLongitude: targets.frontLongitude
            ),
            middleYards: roundedYards(
                from: phoneFix,
                toLatitude: targets.middleLatitude,
                toLongitude: targets.middleLongitude
            ),
            backYards: roundedYards(
                from: phoneFix,
                toLatitude: targets.backLatitude,
                toLongitude: targets.backLongitude
            )
        )
    }

    /// Builds the Watch live-face payload.
    /// - `swings`: shot-chain source for stroke yards (swing-to-swing).
    /// - `greenTargets`: optional F/M/B overlay; never from facility search.
    /// - `phoneFix`: current GPS for green targeting only (not stroke yards).
    static func makeLiveFace(
        holeNumber: Int?,
        courseName: String?,
        swings: [GolfSwingMetrics],
        wristMount: WatchWristMount,
        phoneFix: LocationFix?,
        greenTargets: GolfHoleGreenTargets?
    ) -> WatchLiveFace {
        let matchedTargets: GolfHoleGreenTargets?
        if let greenTargets, greenTargets.isValid,
           holeNumber == nil || greenTargets.holeNumber == holeNumber {
            matchedTargets = greenTargets
        } else {
            matchedTargets = nil
        }
        let overlay = greenYards(from: phoneFix, targets: matchedTargets)
        let base = WatchLiveFace(
            holeNumber: holeNumber,
            frontYards: overlay.frontYards,
            middleYards: overlay.middleYards,
            backYards: overlay.backYards,
            lastShotYards: lastMeasuredShotYards(from: swings),
            activeClubCode: GolfClubKind.load().shortCode,
            wristMount: wristMount,
            courseName: courseName
        )
        // Attach body-relative path score / label / stroke count for the Watch face.
        guard !swings.isEmpty else { return base }
        let journal = StrokeScoreShotChain.buildJournal(
            roundID: UUID(),
            courseName: courseName ?? "live",
            startedAt: swings.map(\.capturedAt).min() ?? Date(),
            swings: swings,
            holeForSwing: { _ in holeNumber },
            wrist: wristMount
        )
        var enriched = StrokeScoreShotChain.enrichLiveFace(base, journal: journal)
        if let last = swings.sorted(by: { $0.capturedAt < $1.capturedAt }).last {
            let dossier = ComprehensiveShotIntelligence.dossier(
                for: last,
                sequence: swings.count,
                wrist: wristMount
            )
            enriched.lastBallStartLabel = dossier.ballStartBias.shortLabel
            if let club = dossier.club {
                enriched.activeClubCode = club.shortCode
            }
        }
        return enriched
    }

    /// Explicit fail-closed: MapKit / facility search never becomes a green map
    /// and never contributes stroke yards.
    static func greenTargetsFromFacilitySearch(_: GolfCourseCandidate) -> GolfHoleGreenTargets? {
        nil
    }

    private static func roundedYards(
        from fix: LocationFix,
        toLatitude: Double,
        toLongitude: Double
    ) -> Int? {
        guard let yards = ShotDistanceCalculator.displacementYards(
            fromLatitude: fix.latitude,
            fromLongitude: fix.longitude,
            toLatitude: toLatitude,
            toLongitude: toLongitude
        ), yards.isFinite, yards >= 0 else {
            return nil
        }
        return Int(yards.rounded())
    }
}

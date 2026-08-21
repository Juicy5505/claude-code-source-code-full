import Foundation

enum ShotDistanceCalculator {
    private static let earthRadiusMeters = 6_371_008.8
    private static let metersPerYard = 0.9144

    static func displacementYards(from first: LocationFix, to second: LocationFix) -> Double? {
        guard first.isUsableForShotDistance, second.isUsableForShotDistance else { return nil }
        return displacementYards(
            fromLatitude: first.latitude,
            fromLongitude: first.longitude,
            toLatitude: second.latitude,
            toLongitude: second.longitude
        )
    }

    /// Haversine yards between two WGS84 coordinates. Callers must quality-gate
    /// GPS origins separately; licensed green targets are exact points and do
    /// not carry horizontal accuracy.
    static func displacementYards(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double? {
        guard fromLatitude.isFinite, fromLongitude.isFinite,
              toLatitude.isFinite, toLongitude.isFinite,
              (-90...90).contains(fromLatitude), (-180...180).contains(fromLongitude),
              (-90...90).contains(toLatitude), (-180...180).contains(toLongitude)
        else {
            return nil
        }
        let latitude1 = fromLatitude * .pi / 180
        let latitude2 = toLatitude * .pi / 180
        let deltaLatitude = (toLatitude - fromLatitude) * .pi / 180
        let deltaLongitude = (toLongitude - fromLongitude) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
            cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let meters = earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
        return meters / metersPerYard
    }

    static func uncertaintyYards(first: LocationFix, second: LocationFix) -> Double {
        hypot(first.horizontalAccuracyMeters, second.horizontalAccuracyMeters) / metersPerYard
    }
}


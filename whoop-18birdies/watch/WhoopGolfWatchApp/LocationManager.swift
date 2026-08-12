import Foundation
import CoreLocation

/// Provides the latest GPS fix so each swing can be tagged for shot-to-shot
/// distance (the Arccos/Shot Scope method the Python shot_model already
/// implements). Series 5 has built-in GPS, so this needs no iPhone nearby.
///
/// Round mode only — at a range you never move, so distance is meaningless and
/// the app skips location entirely.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var latest: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// The current fix as the Codable point the session encodes, or nil when no
    /// usable fix is available — never a guessed coordinate.
    func currentPoint() -> GeoPoint? {
        guard let loc = latest, loc.horizontalAccuracy >= 0 else { return nil }
        return GeoPoint(latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        altitude: loc.altitude,
                        horizontal_accuracy: loc.horizontalAccuracy)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.latest = loc }
    }
}

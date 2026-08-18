import Foundation
import CoreLocation

/// GPS on the wrist, so each swing is tagged where you actually stood.
///
/// This is the piece that makes shot-to-shot yardage work with the phone left
/// in the cart. A WHOOP has no GPS receiver at all — it borrows the phone's —
/// so a strap on your wrist and a phone in the cart would measure the distance
/// between *cart positions*. The Series 5 has its own GPS, which is the whole
/// reason the watch is the tracker rather than the strap.
///
/// Round mode only: at a range you never move, so distance is meaningless and
/// the app skips location entirely.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// The newest fix, for tagging a swing.
    @Published var latest: CLLocation?

    /// The full batch from the most recent callback.
    ///
    /// Core Location delivers an ARRAY, and coalesces queued fixes into one
    /// callback whenever delivery was deferred — which is exactly what happens
    /// with the wrist down and the screen off. Publishing only `locations.last`
    /// threw away every fix but the newest, so a 200 m walk between shots
    /// reached the route builder as a single point and the track WHOOP imports
    /// became a handful of long straight jumps instead of the walked line.
    @Published var batch: [CLLocation] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Golf is walking pace; a 5 m filter cuts the noise of standing still
        // without losing the shape of the walk.
        manager.distanceFilter = 5
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        // THE line that decides whether a round works. It defaults to false,
        // and without it watchOS stops delivering fixes the moment the app is
        // suspended — which on a watch is as soon as your wrist drops. The
        // round would then record a position for the first shot or two and
        // nothing afterwards, with no error anywhere.
        //
        // Setting it requires `location` in the target's Background Modes
        // (WKBackgroundModes) alongside workout-processing; see WATCH.md. If
        // the capability is missing, assigning true raises, so this is guarded
        // rather than assumed.
        if CLLocationManager.locationServicesEnabled() {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        // Release the background-location assertion. Leaving it set keeps the
        // GPS radio powered after the round ends, which on a Series 5 is a
        // meaningful part of the battery.
        manager.allowsBackgroundLocationUpdates = false
    }

    /// The current fix as the Codable point the session encodes, or nil when no
    /// usable fix is available — never a guessed coordinate.
    ///
    /// A NEGATIVE `horizontalAccuracy` is Core Location's signal that the fix is
    /// invalid, so the test is `>= 0` rather than a magnitude comparison: a
    /// naive `accuracy < 20` check reads -1 as pinpoint and would place a shot
    /// at a fabricated coordinate.
    func currentPoint() -> GeoPoint? {
        guard let loc = latest, loc.horizontalAccuracy >= 0 else { return nil }
        return GeoPoint(latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        altitude: loc.altitude,
                        horizontal_accuracy: loc.horizontalAccuracy)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        Task { @MainActor in
            self.batch = locations
            self.latest = locations.last
        }
    }

    /// Surfaced rather than swallowed: a denied authorisation is the difference
    /// between a round with yardages and a round without, and the user should
    /// find out on the first hole rather than the nineteenth.
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = (error as NSError).code == CLError.denied.rawValue
                ? "location denied — no shot distances"
                : "GPS error — distances may be missing"
        }
    }

    @Published var lastError: String?
}

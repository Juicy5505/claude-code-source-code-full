import CoreLocation
import Foundation

@MainActor
final class LocationRoundService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case needsPermission
        case acquiring
        case ready(accuracyMeters: Double)
        case reducedAccuracy
        case denied
        case failed(String)
    }

    /// Authorization is kept separate from GPS acquisition so the UI can say
    /// exactly what iOS has granted. `whenInUseNeedsSettings` means this app
    /// already made its one allowed in-app Always request and the remaining
    /// repair path is the system Settings screen.
    enum PermissionState: Equatable {
        case notRequested
        case requestingWhenInUse
        case whenInUse
        case requestingAlways
        case whenInUseNeedsSettings
        case always
        case denied
        case restricted
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var permissionState: PermissionState = .notRequested
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published private(set) var latestFix: LocationFix?
    @Published private(set) var activeRoundID: UUID?

    private var manager: CLLocationManager?
    private let managerFactory: () -> CLLocationManager
    private let defaults: UserDefaults
    private var recording = false
    private var oneShotRequested = false
    private let journal: RoundLocationJournal
    private var journalOperation: Task<Void, Never>?
    private var journalOperationGeneration: UInt64 = 0

    private static let didRequestAlwaysKey = "whoop-golf-location-did-request-always"

    init(
        journal: RoundLocationJournal = RoundLocationJournal(),
        managerFactory: @escaping () -> CLLocationManager = { CLLocationManager() },
        defaults: UserDefaults = .standard
    ) {
        self.journal = journal
        self.managerFactory = managerFactory
        self.defaults = defaults
        super.init()
    }

    private func configuredManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = managerFactory()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
        self.manager = manager
        reflectAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        return manager
    }

    /// Existing callers use this to obtain a one-time course fix or to begin
    /// an already-persisted active round. It never asks for Always access and
    /// never starts continuous updates without an active round identifier.
    func requestPermission() {
        let manager = configuredManager()
        switch manager.authorizationStatus {
        case .notDetermined:
            oneShotRequested = !recording
            permissionState = .requestingWhenInUse
            state = .needsPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if recording, activeRoundID != nil {
                startContinuousUpdates(using: manager)
            } else {
                requestOneShotLocation(using: manager)
            }
        case .denied:
            state = .denied
            permissionState = .denied
        case .restricted:
            state = .denied
            permissionState = .restricted
        @unknown default:
            state = .failed("Unknown location authorization state")
        }
    }

    /// First-step permission action for Settings. It can only present Apple's
    /// While Using prompt; granting it does not start a location session.
    func requestWhenInUsePermission() {
        let manager = configuredManager()
        switch manager.authorizationStatus {
        case .notDetermined:
            permissionState = .requestingWhenInUse
            state = .needsPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            reflectAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        case .denied:
            state = .denied
            permissionState = .denied
        case .restricted:
            state = .denied
            permissionState = .restricted
        @unknown default:
            state = .failed("Unknown location authorization state")
        }
    }

    /// Second-step permission action. The app calls this only after iOS has
    /// granted While Using and only from an explicit user action in Settings.
    /// It never chains automatically from the first permission callback.
    func requestAlwaysPermission() {
        let manager = configuredManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            guard !defaults.bool(forKey: Self.didRequestAlwaysKey) else {
                permissionState = .whenInUseNeedsSettings
                return
            }
            defaults.set(true, forKey: Self.didRequestAlwaysKey)
            permissionState = .requestingAlways
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            permissionState = .always
        case .notDetermined:
            // Always must never be the first prompt. The next explicit action
            // remains the ordinary While Using request.
            requestWhenInUsePermission()
        case .denied:
            permissionState = .denied
        case .restricted:
            permissionState = .restricted
        @unknown default:
            state = .failed("Unknown location authorization state")
        }
    }

    /// Reconciles authorization after returning from iOS Settings. It may
    /// resume an active round, but it never starts tracking on its own.
    func refreshPermissionState() {
        let manager = configuredManager()
        reflectAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        guard recording, activeRoundID != nil else {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if state == .denied || state == .needsPermission { state = .idle }
            case .denied, .restricted:
                state = .denied
            case .notDetermined:
                if permissionState != .requestingWhenInUse { state = .idle }
            @unknown default:
                state = .failed("Unknown location authorization state")
            }
            return
        }
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            startContinuousUpdates(using: manager)
        }
    }

    /// Starts continuous GPS for a persisted round. This must be called while
    /// the app is in the foreground so iOS can authorize and begin the session.
    func startRoundTracking(roundID: UUID) {
        if let previousRoundID = activeRoundID, previousRoundID != roundID {
            enqueueJournalStop(roundID: previousRoundID)
        }
        activeRoundID = roundID
        enqueueJournalStart(roundID: roundID)
        beginContinuousUpdates()
    }

    /// Reopens the same protected timeline after app relaunch without truncating it.
    func resumeRoundTracking(roundID: UUID) {
        startRoundTracking(roundID: roundID)
    }

    /// Compatibility entry point retained for older callers. Tracking without
    /// a persisted round identifier is intentionally refused.
    func startRoundTracking() {
        recording = false
        state = .failed("A saved active round is required before GPS tracking can start.")
    }

    private func beginContinuousUpdates() {
        guard activeRoundID != nil else {
            state = .failed("A saved active round is required before GPS tracking can start.")
            return
        }
        recording = true
        requestPermission()
    }

    private func startContinuousUpdates(using manager: CLLocationManager) {
        guard recording, activeRoundID != nil else { return }
        oneShotRequested = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        state = .acquiring
        manager.startUpdatingLocation()
    }

    private func requestOneShotLocation(using manager: CLLocationManager) {
        guard !recording, activeRoundID == nil else { return }
        oneShotRequested = true
        state = .acquiring
        manager.requestLocation()
    }

    func stopRoundTracking() {
        if let activeRoundID {
            enqueueJournalStop(roundID: activeRoundID)
        }
        activeRoundID = nil
        recording = false
        oneShotRequested = false
        manager?.allowsBackgroundLocationUpdates = false
        manager?.showsBackgroundLocationIndicator = false
        manager?.pausesLocationUpdatesAutomatically = true
        manager?.stopUpdatingLocation()
        state = .idle
    }

    func stopRoundTracking(roundID: UUID) {
        guard activeRoundID == roundID else { return }
        stopRoundTracking()
    }

    func currentShotFix(maximumAge: TimeInterval = 10) -> LocationFix? {
        guard let fix = latestFix,
              Date().timeIntervalSince(fix.capturedAt) <= maximumAge,
              fix.isUsableForShotDistance
        else { return nil }
        return fix
    }

    /// Returns a quality-gated GPS estimate for a delayed WHOOP event. The
    /// result remains an estimate and must not be presented as exact ball GPS.
    func estimatedLocation(
        roundID: UUID,
        at swingTimestamp: Date,
        maximumTimeGap: TimeInterval = 15,
        maximumHorizontalAccuracy: Double = 25
    ) async throws -> RoundLocationCorrelation? {
        // Core Location callbacks enqueue protected file writes so the main
        // actor never blocks on I/O. A delayed WHOOP import must nevertheless
        // observe every write that was already queued; otherwise a valid fix
        // can look absent and the immutable batch can be terminally imported
        // without its shot location. Loop on the generation because another
        // callback can append while an earlier operation is being awaited.
        while let pending = journalOperation {
            let generation = journalOperationGeneration
            await pending.value
            if generation == journalOperationGeneration { break }
        }
        return try await journal.correlate(
            roundID: roundID,
            at: swingTimestamp,
            maximumTimeGap: maximumTimeGap,
            maximumHorizontalAccuracy: maximumHorizontalAccuracy
        )
    }

    private func accept(_ location: CLLocation) {
        // Ignore buffered callbacks after a round or one-shot request ends.
        // This prevents a stopped app session from silently becoming a tracker.
        guard (recording && activeRoundID != nil) || oneShotRequested else { return }
        let coordinate = location.coordinate
        let timestamp = location.timestamp
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude),
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 10_000,
              timestamp.timeIntervalSince1970.isFinite,
              timestamp.timeIntervalSince1970 >= 0,
              timestamp <= Date().addingTimeInterval(5 * 60)
        else { return }

        let fix = LocationFix(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeMeters: location.verticalAccuracy >= 0 && location.altitude.isFinite
                ? location.altitude
                : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            capturedAt: timestamp,
            provenance: DataProvenance(
                source: .iphoneGPS,
                observedAt: timestamp,
                quality: location.horizontalAccuracy <= 25 ? .verified : .estimated
            )
        )

        if recording, let activeRoundID {
            enqueueJournalAppend(fix, roundID: activeRoundID)
        }

        // Buffered background callbacks can contain older observations. They
        // belong in the durable timeline but must not replace a newer live fix.
        if let latestFix, timestamp < latestFix.capturedAt { return }

        accuracyAuthorization = manager?.accuracyAuthorization ?? .fullAccuracy
        if accuracyAuthorization == .reducedAccuracy {
            state = .reducedAccuracy
        } else {
            state = location.horizontalAccuracy <= 25
                ? .ready(accuracyMeters: location.horizontalAccuracy)
                : .acquiring
        }

        latestFix = fix

        if !recording {
            oneShotRequested = false
            manager?.stopUpdatingLocation()
        }
    }

    private func reflectAuthorization(
        _ authorization: CLAuthorizationStatus,
        accuracy: CLAccuracyAuthorization
    ) {
        accuracyAuthorization = accuracy
        switch authorization {
        case .notDetermined:
            if permissionState != .requestingWhenInUse {
                permissionState = .notRequested
            }
        case .authorizedWhenInUse:
            permissionState = defaults.bool(forKey: Self.didRequestAlwaysKey)
                ? .whenInUseNeedsSettings
                : .whenInUse
        case .authorizedAlways:
            permissionState = .always
        case .denied:
            permissionState = .denied
        case .restricted:
            permissionState = .restricted
        @unknown default:
            state = .failed("Unknown location authorization state")
        }
    }

    func enqueueJournalStart(roundID: UUID) {
        let previous = journalOperation
        let journal = journal
        journalOperationGeneration &+= 1
        journalOperation = Task { [weak self] in
            await previous?.value
            do {
                try await journal.start(roundID: roundID)
            } catch {
                self?.recordJournalFailure(error)
            }
        }
    }

    func enqueueJournalAppend(_ fix: LocationFix, roundID: UUID) {
        let previous = journalOperation
        let journal = journal
        journalOperationGeneration &+= 1
        journalOperation = Task { [weak self] in
            await previous?.value
            do {
                try await journal.append(fix, roundID: roundID)
            } catch {
                self?.recordJournalFailure(error)
            }
        }
    }

    func enqueueJournalStop(roundID: UUID) {
        let previous = journalOperation
        let journal = journal
        journalOperationGeneration &+= 1
        journalOperation = Task { [weak self] in
            await previous?.value
            do {
                try await journal.stop(roundID: roundID)
            } catch {
                self?.recordJournalFailure(error)
            }
        }
    }

    private func recordJournalFailure(_ error: Error) {
        guard recording else { return }
        state = .failed("GPS timeline could not be saved: \(error.localizedDescription)")
    }
}

extension LocationRoundService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        reflectAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        switch manager.authorizationStatus {
        case .notDetermined:
            if permissionState == .requestingWhenInUse { state = .needsPermission }
        case .authorizedAlways, .authorizedWhenInUse:
            if recording, activeRoundID != nil {
                startContinuousUpdates(using: manager)
            } else if oneShotRequested {
                requestOneShotLocation(using: manager)
            } else {
                state = .idle
            }
        case .denied, .restricted:
            oneShotRequested = false
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.pausesLocationUpdatesAutomatically = true
            manager.stopUpdatingLocation()
            state = .denied
        @unknown default:
            state = .failed("Unknown location authorization state")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                accept(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            oneShotRequested = false
            state = .failed(error.localizedDescription)
        }
    }
}

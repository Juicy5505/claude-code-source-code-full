import CoreLocation
import Foundation
import HealthKit

/// Runs a HealthKit workout session for the round.
///
/// Two jobs, both things a phone could not do:
///  1. Background execution — a running HKWorkoutSession keeps the app (and the
///     motion loop) alive with the wrist down and the screen off. This is the
///     whole reason the watch beats the phone for golf.
///  2. Live heart rate — from the watch's own sensor, delivered per sample,
///     with no dependency on a WHOOP being in Bluetooth range.
///
/// Saving the workout as a GOLF activity is also how the round reaches WHOOP.
/// WHOOP imports activities from Apple Health — using the start/end window and
/// classification alongside its own heart-rate data — so finishing this session
/// makes the round appear in WHOOP with strain, with no write API involved.
/// WHOOP only picks up the GPS track if the workout carries a route, hence the
/// route builder below.
///
/// Requires the HealthKit capability and, in Info.plist, the workout-processing
/// background mode plus the health usage-description keys (see WATCH.md).
/// Entitlements already present: `com.apple.developer.healthkit` on
/// `WatchSupport/WhoopGolfWatch.entitlements` (do not invent extra HealthKit
/// access flags for Personal Team signing).
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var heartRateSamples: [Int] = []

    /// Latest heart rate in bpm, or nil until the first sample arrives.
    @Published private(set) var heartRate: Int?

    /// Mean of samples collected during this workout, for end-of-round summary.
    @Published private(set) var averageHeartRate: Int?

    /// True while an HKWorkoutSession is running (including after start returns).
    @Published private(set) var isSessionRunning = false

    /// Last HealthKit failure string, if the session dies after a successful start.
    @Published private(set) var lastFailure: String?

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // workoutRoute must be shareable or WHOOP cannot import the GPS track.
        let share: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        // Built with quantityType(forIdentifier:) rather than the shorter
        // HKQuantityType(.heartRate) initialiser, which needs watchOS 9. An
        // Apple Watch Series 5 tops out at watchOS 10 and may still be on 8,
        // so the older call keeps the deployment floor as low as possible.
        let read = Set(
            [
                HKQuantityTypeIdentifier.heartRate,
                .activeEnergyBurned,
                .distanceWalkingRunning,
            ].compactMap { HKObjectType.quantityType(forIdentifier: $0) as HKObjectType? }
        )
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// Feed GPS fixes in as they arrive so the finished workout carries a route.
    func append(locations: [CLLocation]) {
        guard let routeBuilder, !locations.isEmpty else { return }
        routeBuilder.insertRouteData(locations) { _, _ in }
    }

    /// Returns false when the session could not start.
    ///
    /// The caller needs this. Without a running workout session watchOS
    /// suspends the app as soon as the wrist drops, so detection stops a minute
    /// into the round — and the failure used to be swallowed here while the UI
    /// went on displaying "watching". The round then looked healthy right up
    /// until the log came back with three swings in it.
    @discardableResult
    func start(trackRoute: Bool) -> Bool {
        // Idempotent restart: never leave a prior session half-alive.
        if session != nil || builder != nil {
            session?.end()
            session = nil
            builder = nil
            routeBuilder = nil
        }
        heartRate = nil
        averageHeartRate = nil
        heartRateSamples = []
        lastFailure = nil
        isSessionRunning = false

        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )
            // Golf's default collected types are not guaranteed to include HR on
            // every watchOS build. Explicit enable keeps live bpm flowing for
            // SessionView + per-swing `hr_bpm` tags that sync to the phone.
            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                dataSource.enableCollection(for: hrType, predicate: nil)
            }
            if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                dataSource.enableCollection(for: energyType, predicate: nil)
            }
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            // Range mode never moves, so a route there would be GPS noise.
            self.routeBuilder = trackRoute
                ? HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                : nil

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] success, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.lastFailure = error.localizedDescription
                        self.isSessionRunning = false
                        return
                    }
                    self.isSessionRunning = success
                    if !success {
                        self.lastFailure = "workout collection did not begin"
                    }
                }
            }
            isSessionRunning = true
            return true
        } catch {
            // Without a session the motion loop still runs while the app is in
            // the FOREGROUND; it loses background execution entirely, which on
            // a watch means it stops when your wrist drops.
            lastFailure = error.localizedDescription
            isSessionRunning = false
            return false
        }
    }

    /// Ends the session and saves the workout. The route is attached to the
    /// finished workout — it must be finished AFTER the workout exists, or the
    /// track is orphaned and WHOOP imports the round without its GPS.
    ///
    /// Async, and awaited by the caller before it dismisses the view. The
    /// callback version of this looked correct and was not: the view dismissed
    /// as soon as `stop()` returned, the manager deallocated, and the weakly
    /// captured `self` inside HealthKit's completion handler was already nil by
    /// the time the workout finished — so `finishRoute` never ran and every
    /// round imported into WHOOP without its GPS track. Holding the builders in
    /// locals rather than reading them back off `self` is the other half of the
    /// fix; they must outlive the object.
    func stop() async {
        // Idempotent: clear the handles first so a second call returns at once
        // rather than finishing an already-finished builder.
        guard let builder = self.builder else {
            isSessionRunning = false
            return
        }
        let route = routeBuilder
        self.builder = nil
        self.routeBuilder = nil
        session?.end()
        self.session = nil
        isSessionRunning = false
        publishAverageHeartRate()

        let workout: HKWorkout? = await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { workout, _ in
                    continuation.resume(returning: workout)
                }
            }
        }

        guard let workout, let route else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            route.finishRoute(with: workout, metadata: nil) { _, _ in
                continuation.resume()
            }
        }
    }

    private func ingestHeartRate(_ bpm: Int) {
        guard (1...300).contains(bpm) else { return }
        heartRate = bpm
        heartRateSamples.append(bpm)
        publishAverageHeartRate()
    }

    private func publishAverageHeartRate() {
        guard !heartRateSamples.isEmpty else {
            averageHeartRate = nil
            return
        }
        let sum = heartRateSamples.reduce(0, +)
        averageHeartRate = Int((Double(sum) / Double(heartRateSamples.count)).rounded())
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.isSessionRunning = true
            case .ended, .stopped:
                self.isSessionRunning = false
            case .notStarted, .prepared, .paused:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            self.lastFailure = error.localizedDescription
            self.isSessionRunning = false
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in self.ingestHeartRate(bpm) }
    }
}

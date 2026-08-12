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
/// Requires the HealthKit capability and, in Info.plist, the workout-processing
/// background mode plus the health usage-description keys (see WATCH.md).
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Latest heart rate in bpm, or nil until the first sample arrives.
    @Published var heartRate: Int?

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    func start() {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
        } catch {
            // Without a session the motion loop still runs while the app is in
            // the foreground; it just loses background execution.
        }
    }

    func stop() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {}
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
        Task { @MainActor in self.heartRate = bpm }
    }
}

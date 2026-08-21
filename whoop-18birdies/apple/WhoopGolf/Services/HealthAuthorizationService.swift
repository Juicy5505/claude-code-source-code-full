import Foundation
import HealthKit

@MainActor
final class HealthAuthorizationService: ObservableObject {
    enum State: Equatable {
        case notRequested
        case requesting
        case ready
        case denied
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .notRequested
    @Published private(set) var lastSavedWorkoutAt: Date?

    private let store = HKHealthStore()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        state = .requesting
        let workout = HKObjectType.workoutType()
        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)
        var read: Set<HKObjectType> = [workout]
        if let heartRate { read.insert(heartRate) }
        let write: Set<HKSampleType> = [workout]
        do {
            try await store.requestAuthorization(toShare: write, read: read)
            state = store.authorizationStatus(for: workout) == .sharingAuthorized
                ? .ready
                : .denied
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func saveWorkout(for round: GolfRound) async throws {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthAuthorizationError.workoutWriteNotAuthorised
        }
        let end = round.endedAt ?? .now
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .golf
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: round.startedAt)
        try await builder.addMetadata([
            HKMetadataKeyIndoorWorkout: false,
            "WhoopGolfRoundID": round.id.uuidString
        ])
        try await builder.endCollection(at: end)
        guard try await builder.finishWorkout() != nil else {
            throw HealthAuthorizationError.workoutSaveFailed
        }

        // Marked ball positions are not a continuous workout route. The phone
        // fallback stores only the golf workout; the Watch owns genuine route
        // recording when it is the active recorder.
        lastSavedWorkoutAt = .now
    }
}

enum HealthAuthorizationError: LocalizedError {
    case workoutWriteNotAuthorised
    case workoutSaveFailed

    var errorDescription: String? {
        switch self {
        case .workoutWriteNotAuthorised:
            "Apple Health has not authorised golf-workout writes."
        case .workoutSaveFailed:
            "Apple Health did not return a saved golf workout."
        }
    }
}

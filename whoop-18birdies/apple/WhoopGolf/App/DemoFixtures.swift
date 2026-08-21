import Foundation

#if DEBUG
enum DemoFixtures {
    static let readiness = ReadinessSnapshot(
        score: 82,
        verdict: "Prime",
        recoveryPercent: 87,
        sleepHours: 7.8,
        dayStrain: 4.6,
        advice: "Demo preview: recovery and sleep inputs support a normal warm-up and full round.",
        syncedAt: .now.addingTimeInterval(-1_440),
        isStale: false,
        personalised: false,
        provenance: DataProvenance(
            source: .demo,
            observedAt: .now,
            quality: .estimated,
            algorithmVersion: "preview-only",
            inputSources: [.demo]
        )
    )
}
#endif


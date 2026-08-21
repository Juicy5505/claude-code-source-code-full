import Foundation

struct DayResponse: Codable, Sendable {
    let apiVersion: Int
    let date: String
    let generatedAt: Date
    let freshness: Freshness
    let physiology: Physiology
    let golfReadiness: GolfReadiness

    struct Freshness: Codable, Sendable {
        let lastCompleteSyncAt: Date?
        let stale: Bool
        let staleAfterSeconds: Int
    }

    struct Physiology: Codable, Sendable {
        let status: String
        let recoveryPercent: Double?
        let hrvRmssdMs: Double?
        let restingHeartRateBpm: Double?
        let spo2Percent: Double?
        let skinTemperatureCelsius: Double?
        let sleepHours: Double?
        let sleepPerformancePercent: Double?
        let sleepEfficiencyPercent: Double?
        let dayStrain: Double?
        let priorDayStrain: Double?
        let provenance: APIProvenance
    }

    struct GolfReadiness: Codable, Sendable {
        let available: Bool
        let score: Double?
        let verdict: String?
        let personalised: Bool
        let components: [Component]
        let advice: [String]
        let reason: String?
        let provenance: APIProvenance
    }

    struct Component: Codable, Identifiable, Sendable {
        var id: String { label }
        let label: String
        let value: Double?
        let weight: Double
        let detail: String
    }

    struct APIProvenance: Codable, Sendable {
        let kind: String
        let provider: String?
        let source: String?
        let producer: String?
        let model: String?
        let isWhoopMetric: Bool?
        let note: String?
    }
}

struct ReadinessSnapshot: Sendable {
    let score: Double?
    let verdict: String
    let recoveryPercent: Double?
    let sleepHours: Double?
    let dayStrain: Double?
    let advice: String
    let syncedAt: Date?
    let isStale: Bool
    let personalised: Bool
    let provenance: DataProvenance

    static func from(_ response: DayResponse) -> ReadinessSnapshot {
        // Golf readiness is always an in-house derived estimate. Fresh WHOOP
        // inputs make it current, not provider-verified.
        let quality: DataQuality = response.freshness.stale ? .stale : .estimated
        let verdict = boundedText(
            response.golfReadiness.verdict?.replacingOccurrences(of: "_", with: " "),
            maximumCharacters: 64
        )?.capitalized ?? "Pending"
        let advice = boundedText(
            response.golfReadiness.advice.first,
            maximumCharacters: 800
        ) ?? "Not enough cached WHOOP inputs to calculate golf readiness."
        return ReadinessSnapshot(
            score: bounded(response.golfReadiness.score, range: 0...100),
            verdict: verdict,
            recoveryPercent: bounded(response.physiology.recoveryPercent, range: 0...100),
            sleepHours: bounded(response.physiology.sleepHours, range: 0...48),
            dayStrain: bounded(response.physiology.dayStrain, range: 0...21),
            advice: advice,
            syncedAt: supportedDate(response.freshness.lastCompleteSyncAt),
            isStale: response.freshness.stale,
            personalised: response.golfReadiness.personalised,
            provenance: DataProvenance(
                source: .derived,
                observedAt: supportedDate(response.generatedAt) ?? .now,
                quality: quality,
                algorithmVersion: response.golfReadiness.provenance.model,
                inputSources: [.whoopCloud]
            )
        )
    }

    private static func bounded(_ value: Double?, range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func boundedText(_ value: String?, maximumCharacters: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return String(trimmed.prefix(maximumCharacters))
    }

    private static func supportedDate(_ value: Date?) -> Date? {
        guard let value,
              value.timeIntervalSinceReferenceDate.isFinite,
              value >= .distantPast,
              value <= .distantFuture
        else { return nil }
        return value
    }
}

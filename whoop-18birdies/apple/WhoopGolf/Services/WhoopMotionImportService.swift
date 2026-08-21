import CryptoKit
import Foundation

protocol WhoopMotionLocationCorrelating {
    func estimatedLocation(
        roundID: UUID,
        at swingTimestamp: Date,
        maximumTimeGap: TimeInterval,
        maximumHorizontalAccuracy: Double
    ) async throws -> RoundLocationCorrelation?
}

extension LocationRoundService: WhoopMotionLocationCorrelating {}

enum WhoopMotionImportOutcome: Equatable, Sendable {
    case imported(batchID: String, roundID: UUID, swingCount: Int, needsReviewCount: Int)
    case stagedCrossSourceConflict(batchID: String, roundID: UUID)
    case stagedNeedsReview(batchID: String, roundID: UUID, count: Int)
    case stagedRoundUnavailable(batchID: String, roundID: UUID)
    case stagedLocationUnavailable(batchID: String, roundID: UUID)
    case duplicate(batchID: String, roundID: UUID)
    case invalid(batchID: String?, reason: String)
}

struct PendingWhoopMotionBatch: Equatable, Sendable {
    let batchID: String
    let roundID: UUID
    let acceptedCount: Int
    let needsReviewCount: Int
    let reason: String
}

enum WhoopMotionUserReviewDecision: String, Codable, Equatable, Sendable {
    case accept
    case reject
}

enum WhoopMotionReviewPendingReason: String, Equatable, Sendable {
    case crossSourceConflict
    case needsReview
    case roundUnavailable
    case locationUnavailable
}

struct PendingWhoopMotionEventDetail: Equatable, Sendable, Identifiable {
    var id: String { event.eventID }

    let batchID: String
    let roundID: UUID
    let event: WhoopMotionEvent
    let userDecision: WhoopMotionUserReviewDecision?
}

struct PendingWhoopMotionReviewBatch: Equatable, Sendable, Identifiable {
    var id: String { batchID }

    let batchID: String
    let roundID: UUID
    let generatedAt: Date
    let source: WhoopMotionSource
    let coverage: WhoopMotionCoverage
    let reason: WhoopMotionReviewPendingReason
    let detectorAcceptedCount: Int
    let events: [PendingWhoopMotionEventDetail]

    var undecidedCount: Int {
        events.lazy.filter { $0.userDecision == nil }.count
    }
}

enum WhoopMotionReviewOutcome: Equatable, Sendable {
    case recorded(batchID: String, eventID: String, remainingDecisionCount: Int)
    case resolved(
        batchID: String,
        roundID: UUID,
        acceptedReviewCount: Int,
        rejectedReviewCount: Int
    )
    case stagedCrossSourceConflict(batchID: String, roundID: UUID)
    case stagedRoundUnavailable(batchID: String, roundID: UUID)
    case stagedLocationUnavailable(batchID: String, roundID: UUID)
    case duplicate(batchID: String, eventID: String)
    case invalid(batchID: String?, eventID: String?, reason: String)
}

private enum WhoopMotionImportState: String, Codable {
    case stagedCrossSourceConflict
    case stagedNeedsReview
    case stagedRoundUnavailable
    case stagedLocationUnavailable
    case imported
    case importedWithNeedsReview
    case reviewed
}

private struct WhoopMotionImportRegistryEntry: Codable {
    let batchID: String
    let roundID: UUID
    let schemaVersion: Int
    let payloadSHA256: String
    let inboxFileName: String
    let acceptedCount: Int
    let needsReviewCount: Int
    let firstSeenAt: Date
    var updatedAt: Date
    var state: WhoopMotionImportState
}

private struct WhoopMotionImportRegistry: Codable {
    var schemaVersion = 1
    var entries: [String: WhoopMotionImportRegistryEntry] = [:]
}

private struct WhoopMotionReviewDecisionRecord: Codable, Equatable {
    static let actor = "localUser"

    let batchID: String
    let roundID: UUID
    let eventID: String
    let payloadSHA256: String
    let decision: WhoopMotionUserReviewDecision
    let recordedAt: Date
    let recordedBy: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case batchID
        case roundID
        case eventID
        case payloadSHA256
        case decision
        case recordedAt
        case recordedBy
    }

    init(
        batchID: String,
        roundID: UUID,
        eventID: String,
        payloadSHA256: String,
        decision: WhoopMotionUserReviewDecision,
        recordedAt: Date
    ) {
        self.batchID = batchID
        self.roundID = roundID
        self.eventID = eventID
        self.payloadSHA256 = payloadSHA256
        self.decision = decision
        self.recordedAt = recordedAt
        self.recordedBy = Self.actor
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionReviewStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        batchID = try values.decode(String.self, forKey: .batchID)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        eventID = try values.decode(String.self, forKey: .eventID)
        payloadSHA256 = try values.decode(String.self, forKey: .payloadSHA256)
        decision = try values.decode(WhoopMotionUserReviewDecision.self, forKey: .decision)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        recordedBy = try values.decode(String.self, forKey: .recordedBy)
    }
}

private struct WhoopMotionReviewDecisionLedger: Codable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let batchID: String
    let roundID: UUID
    let payloadSHA256: String
    var records: [String: WhoopMotionReviewDecisionRecord]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case batchID
        case roundID
        case payloadSHA256
        case records
    }

    init(
        batchID: String,
        roundID: UUID,
        payloadSHA256: String,
        records: [String: WhoopMotionReviewDecisionRecord] = [:]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.batchID = batchID
        self.roundID = roundID
        self.payloadSHA256 = payloadSHA256
        self.records = records
    }

    init(from decoder: Decoder) throws {
        try WhoopMotionReviewStrictDecoding.requireExactKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        batchID = try values.decode(String.self, forKey: .batchID)
        roundID = try values.decode(UUID.self, forKey: .roundID)
        payloadSHA256 = try values.decode(String.self, forKey: .payloadSHA256)
        records = try values.decode(
            [String: WhoopMotionReviewDecisionRecord].self,
            forKey: .records
        )
    }
}

private enum WhoopMotionReviewStrictDecoding {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    static func requireExactKeys(
        _ decoder: Decoder,
        expected: Set<String>
    ) throws {
        let keys = Set(
            try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        )
        guard keys == expected else {
            throw WhoopMotionImportError.reviewLedgerCorrupt
        }
    }
}

private enum WhoopMotionImportError: LocalizedError {
    case payloadTooLarge
    case identityCollision
    case registryCorrupt
    case registryUnsupported(Int)
    case roundCoverageMismatch
    case locationUnavailable
    case unknownBatch
    case unknownReviewEvent
    case reviewDecisionCollision
    case inboxMissing
    case inboxCorrupt
    case reviewLedgerCorrupt

    var errorDescription: String? {
        switch self {
        case .payloadTooLarge:
            "the motion batch exceeded the one-megabyte import limit"
        case .identityCollision:
            "a different payload already uses this motion batch identity"
        case .registryCorrupt:
            "the protected motion import registry could not be decoded"
        case .registryUnsupported(let version):
            "motion import registry schema \(version) is unsupported"
        case .roundCoverageMismatch:
            "the motion batch time range does not match the protected local round"
        case .locationUnavailable:
            "the protected GPS timeline has no quality-gated fix for a swing"
        case .unknownBatch:
            "the protected motion batch is not registered"
        case .unknownReviewEvent:
            "the event is not a reviewable candidate in the protected motion batch"
        case .reviewDecisionCollision:
            "a different user decision is already recorded for this motion event"
        case .inboxMissing:
            "the protected motion inbox payload is unavailable"
        case .inboxCorrupt:
            "the protected motion inbox payload does not match its registry identity"
        case .reviewLedgerCorrupt:
            "the protected motion review decision record is invalid"
        }
    }
}

/// Imports only derived WHOOP swing events. Raw frames, GPS, band identifiers,
/// and credentials are deliberately absent from the transfer envelope.
///
/// The raw envelope reaches protected storage before any round mutation. The
/// round is then atomically saved before the registry becomes terminal. If the
/// process stops between those writes, deterministic swing IDs make retrying
/// safe and prevent duplicates.
actor WhoopMotionImportService {
    static let maximumPayloadBytes = 1_048_576
    static let maximumLocationTimeGap: TimeInterval = 10
    static let maximumHorizontalAccuracy = 25.0

    private let roundStore: RoundFileStore
    private let locationCorrelator: any WhoopMotionLocationCorrelating
    private let fileManager: FileManager
    private let storageDirectory: URL
    private let inboxDirectory: URL
    private let reviewDirectory: URL
    private let registryURL: URL
    private let now: @Sendable () -> Date
    private let decoder: JSONDecoder

    init(
        roundStore: RoundFileStore = RoundFileStore(),
        locationCorrelator: any WhoopMotionLocationCorrelating,
        storageDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.roundStore = roundStore
        self.locationCorrelator = locationCorrelator
        self.fileManager = fileManager
        self.now = now

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let resolved = storageDirectory ?? applicationSupport
            .appendingPathComponent("WhoopGolf", isDirectory: true)
            .appendingPathComponent("WhoopMotionImports", isDirectory: true)
        self.storageDirectory = resolved
        self.inboxDirectory = resolved.appendingPathComponent("Inbox", isDirectory: true)
        self.reviewDirectory = resolved.appendingPathComponent("Reviews", isDirectory: true)
        self.registryURL = resolved.appendingPathComponent("registry.json")
        self.decoder = Self.makeDecoder()
    }

    func importBatch(
        _ data: Data,
        allowingCrossSourceMerge: Bool = false
    ) async -> WhoopMotionImportOutcome {
        var decodedBatchID: String?
        do {
            guard data.count <= Self.maximumPayloadBytes else {
                throw WhoopMotionImportError.payloadTooLarge
            }
            let envelope = try decoder.decode(WhoopMotionEnvelope.self, from: data)
            decodedBatchID = envelope.batchID
            let digest = Self.sha256Hex(data)
            try storeInInbox(data, envelope: envelope, digest: digest)

            var registry = try loadRegistry()
            let existing = registry.entries[envelope.batchID]
            if let existing {
                guard existing.payloadSHA256 == digest,
                      existing.roundID == envelope.roundID,
                      existing.schemaVersion == envelope.schemaVersion else {
                    throw WhoopMotionImportError.identityCollision
                }
                if existing.state == .imported
                    || existing.state == .importedWithNeedsReview
                    || existing.state == .reviewed {
                    return .duplicate(batchID: envelope.batchID, roundID: envelope.roundID)
                }
            }

            let acceptedEvents = envelope.events.filter {
                $0.classification.decision == .accepted
            }
            let needsReviewCount = envelope.events.count - acceptedEvents.count

            let rounds = try await roundStore.rounds()
            guard var round = rounds.first(where: { $0.id == envelope.roundID }) else {
                registry.entries[envelope.batchID] = registryEntry(
                    envelope: envelope,
                    digest: digest,
                    acceptedCount: acceptedEvents.count,
                    needsReviewCount: needsReviewCount,
                    state: .stagedRoundUnavailable,
                    existing: existing
                )
                try saveRegistry(registry)
                return .stagedRoundUnavailable(
                    batchID: envelope.batchID,
                    roundID: envelope.roundID
                )
            }
            try validateCoverage(envelope.coverage, against: round)

            let hasGuardedSource = round.swings.contains {
                $0.provenance.source == .appleWatch || $0.provenance.source == .manual
            }
            if hasGuardedSource && !allowingCrossSourceMerge {
                registry.entries[envelope.batchID] = registryEntry(
                    envelope: envelope,
                    digest: digest,
                    acceptedCount: acceptedEvents.count,
                    needsReviewCount: needsReviewCount,
                    state: .stagedCrossSourceConflict,
                    existing: existing
                )
                try saveRegistry(registry)
                return .stagedCrossSourceConflict(
                    batchID: envelope.batchID,
                    roundID: envelope.roundID
                )
            }

            guard !acceptedEvents.isEmpty else {
                registry.entries[envelope.batchID] = registryEntry(
                    envelope: envelope,
                    digest: digest,
                    acceptedCount: 0,
                    needsReviewCount: needsReviewCount,
                    state: .stagedNeedsReview,
                    existing: existing
                )
                try saveRegistry(registry)
                return .stagedNeedsReview(
                    batchID: envelope.batchID,
                    roundID: envelope.roundID,
                    count: needsReviewCount
                )
            }

            let importedSwings: [GolfSwingMetrics]
            do {
                importedSwings = try await makeSwings(
                    events: acceptedEvents,
                    envelope: envelope,
                    receivedAt: now()
                )
            } catch {
                registry.entries[envelope.batchID] = registryEntry(
                    envelope: envelope,
                    digest: digest,
                    acceptedCount: acceptedEvents.count,
                    needsReviewCount: needsReviewCount,
                    state: .stagedLocationUnavailable,
                    existing: existing
                )
                try saveRegistry(registry)
                return .stagedLocationUnavailable(
                    batchID: envelope.batchID,
                    roundID: envelope.roundID
                )
            }

            let existingSwingIDs = Set(round.swings.map(\.id))
            let missingSwings = importedSwings.filter {
                !existingSwingIDs.contains($0.id)
            }
            if hasGuardedSource {
                guard allowingCrossSourceMerge,
                      round.recordingDevice == .hybrid,
                      mergeHybridSwings(missingSwings, into: &round) else {
                    registry.entries[envelope.batchID] = registryEntry(
                        envelope: envelope,
                        digest: digest,
                        acceptedCount: acceptedEvents.count,
                        needsReviewCount: needsReviewCount,
                        state: .stagedCrossSourceConflict,
                        existing: existing
                    )
                    try saveRegistry(registry)
                    return .stagedCrossSourceConflict(
                        batchID: envelope.batchID,
                        roundID: envelope.roundID
                    )
                }
            } else {
                round.swings.append(contentsOf: missingSwings)
            }
            round.finalizeWHOOPTriggeredShotIntervals()

            // Persistence ordering is intentional: registry terminality cannot
            // precede the atomic round write.
            try await roundStore.save(round)

            registry.entries[envelope.batchID] = registryEntry(
                envelope: envelope,
                digest: digest,
                acceptedCount: acceptedEvents.count,
                needsReviewCount: needsReviewCount,
                state: needsReviewCount > 0 ? .importedWithNeedsReview : .imported,
                existing: existing
            )
            try saveRegistry(registry)
            return .imported(
                batchID: envelope.batchID,
                roundID: envelope.roundID,
                swingCount: acceptedEvents.count,
                needsReviewCount: needsReviewCount
            )
        } catch {
            return .invalid(batchID: decodedBatchID, reason: error.localizedDescription)
        }
    }

    func pendingBatches() throws -> [PendingWhoopMotionBatch] {
        try loadRegistry().entries.values.compactMap { entry in
            let reason: String
            switch entry.state {
            case .stagedCrossSourceConflict:
                reason = "crossSourceConflict"
            case .stagedNeedsReview:
                reason = "needsReview"
            case .stagedRoundUnavailable:
                reason = "roundUnavailable"
            case .stagedLocationUnavailable:
                reason = "locationUnavailable"
            case .imported:
                return nil
            case .importedWithNeedsReview:
                reason = "needsReviewAfterAcceptedImport"
            case .reviewed:
                return nil
            }
            return PendingWhoopMotionBatch(
                batchID: entry.batchID,
                roundID: entry.roundID,
                acceptedCount: entry.acceptedCount,
                needsReviewCount: entry.needsReviewCount,
                reason: reason
            )
        }.sorted { $0.batchID < $1.batchID }
    }

    /// Returns reviewable event detail only after re-reading and validating the
    /// immutable protected inbox payload against its registry digest. Decisions
    /// are joined from a separate protected ledger; the source batch is never
    /// rewritten to reflect UI state.
    func pendingReviewBatches() throws -> [PendingWhoopMotionReviewBatch] {
        let registry = try loadRegistry()
        return try registry.entries.values.compactMap { entry in
            guard entry.needsReviewCount > 0,
                  entry.state != .imported,
                  entry.state != .reviewed else {
                return nil
            }
            let envelope = try loadProtectedEnvelope(for: entry)
            let reviewEvents = reviewEvents(in: envelope)
            let ledger = try loadReviewLedger(entry: entry, reviewEvents: reviewEvents)
            let details = reviewEvents.map { event in
                PendingWhoopMotionEventDetail(
                    batchID: entry.batchID,
                    roundID: entry.roundID,
                    event: event,
                    userDecision: ledger.records[event.eventID]?.decision
                )
            }
            return PendingWhoopMotionReviewBatch(
                batchID: entry.batchID,
                roundID: entry.roundID,
                generatedAt: envelope.generatedAt,
                source: envelope.source,
                coverage: envelope.coverage,
                reason: reviewPendingReason(for: entry.state),
                detectorAcceptedCount: entry.acceptedCount,
                events: details
            )
        }.sorted { $0.batchID < $1.batchID }
    }

    /// Records one immutable local-user decision. A batch resolves only when
    /// every detector `needsReview` event has an explicit accept/reject record.
    /// Repeating the same decision is idempotent; a contradictory decision is
    /// treated as an identity collision rather than overwriting audit history.
    func recordReviewDecision(
        batchID: String,
        eventID: String,
        decision: WhoopMotionUserReviewDecision,
        allowingCrossSourceMerge: Bool = false
    ) async -> WhoopMotionReviewOutcome {
        do {
            var registry = try loadRegistry()
            guard let entry = registry.entries[batchID] else {
                throw WhoopMotionImportError.unknownBatch
            }
            let envelope = try loadProtectedEnvelope(for: entry)
            let reviewEvents = reviewEvents(in: envelope)
            guard reviewEvents.contains(where: { $0.eventID == eventID }) else {
                throw WhoopMotionImportError.unknownReviewEvent
            }
            var ledger = try loadReviewLedger(entry: entry, reviewEvents: reviewEvents)

            if entry.state == .reviewed {
                guard ledger.records.count == reviewEvents.count,
                      let existing = ledger.records[eventID] else {
                    throw WhoopMotionImportError.reviewLedgerCorrupt
                }
                guard existing.decision == decision else {
                    throw WhoopMotionImportError.reviewDecisionCollision
                }
                return .duplicate(batchID: batchID, eventID: eventID)
            }

            let wasAlreadyRecorded: Bool
            if let existing = ledger.records[eventID] {
                guard existing.decision == decision else {
                    throw WhoopMotionImportError.reviewDecisionCollision
                }
                wasAlreadyRecorded = true
            } else {
                wasAlreadyRecorded = false
                ledger.records[eventID] = WhoopMotionReviewDecisionRecord(
                    batchID: entry.batchID,
                    roundID: entry.roundID,
                    eventID: eventID,
                    payloadSHA256: entry.payloadSHA256,
                    decision: decision,
                    recordedAt: now()
                )
                try saveReviewLedger(ledger)
            }

            let remaining = reviewEvents.count - ledger.records.count
            guard remaining == 0 else {
                return wasAlreadyRecorded
                    ? .duplicate(batchID: batchID, eventID: eventID)
                    : .recorded(
                        batchID: batchID,
                        eventID: eventID,
                        remainingDecisionCount: remaining
                    )
            }

            let rounds = try await roundStore.rounds()
            guard var round = rounds.first(where: { $0.id == envelope.roundID }) else {
                registry.entries[batchID] = registryEntry(
                    envelope: envelope,
                    digest: entry.payloadSHA256,
                    acceptedCount: entry.acceptedCount,
                    needsReviewCount: entry.needsReviewCount,
                    state: .stagedRoundUnavailable,
                    existing: entry
                )
                try saveRegistry(registry)
                return .stagedRoundUnavailable(batchID: batchID, roundID: envelope.roundID)
            }
            try validateCoverage(envelope.coverage, against: round)

            let hasGuardedSource = round.swings.contains {
                $0.provenance.source == .appleWatch || $0.provenance.source == .manual
            }
            if hasGuardedSource && !allowingCrossSourceMerge {
                registry.entries[batchID] = registryEntry(
                    envelope: envelope,
                    digest: entry.payloadSHA256,
                    acceptedCount: entry.acceptedCount,
                    needsReviewCount: entry.needsReviewCount,
                    state: .stagedCrossSourceConflict,
                    existing: entry
                )
                try saveRegistry(registry)
                return .stagedCrossSourceConflict(batchID: batchID, roundID: envelope.roundID)
            }

            let acceptedReviewEvents = reviewEvents.filter {
                ledger.records[$0.eventID]?.decision == .accept
            }
            let rejectedReviewCount = reviewEvents.count - acceptedReviewEvents.count
            let detectorAcceptedEvents = envelope.events.filter {
                $0.classification.decision == .accepted
            }
            let existingSwingIDs = Set(round.swings.map(\.id))
            let eventsMissingFromRound = (detectorAcceptedEvents + acceptedReviewEvents)
                .filter { !existingSwingIDs.contains($0.swingUUID) }

            let importedSwings: [GolfSwingMetrics]
            do {
                importedSwings = try await makeSwings(
                    events: eventsMissingFromRound,
                    envelope: envelope,
                    receivedAt: now()
                )
            } catch {
                registry.entries[batchID] = registryEntry(
                    envelope: envelope,
                    digest: entry.payloadSHA256,
                    acceptedCount: entry.acceptedCount,
                    needsReviewCount: entry.needsReviewCount,
                    state: .stagedLocationUnavailable,
                    existing: entry
                )
                try saveRegistry(registry)
                return .stagedLocationUnavailable(batchID: batchID, roundID: envelope.roundID)
            }

            if hasGuardedSource {
                guard allowingCrossSourceMerge,
                      round.recordingDevice == .hybrid,
                      mergeHybridSwings(importedSwings, into: &round) else {
                    registry.entries[batchID] = registryEntry(
                        envelope: envelope,
                        digest: entry.payloadSHA256,
                        acceptedCount: entry.acceptedCount,
                        needsReviewCount: entry.needsReviewCount,
                        state: .stagedCrossSourceConflict,
                        existing: entry
                    )
                    try saveRegistry(registry)
                    return .stagedCrossSourceConflict(
                        batchID: batchID,
                        roundID: envelope.roundID
                    )
                }
            } else {
                round.swings.append(contentsOf: importedSwings)
            }
            round.finalizeWHOOPTriggeredShotIntervals()

            // A fully reviewed batch becomes terminal only after this atomic
            // round write. If the following registry write fails, deterministic
            // swing IDs make the next resolution attempt safe.
            try await roundStore.save(round)

            registry.entries[batchID] = registryEntry(
                envelope: envelope,
                digest: entry.payloadSHA256,
                acceptedCount: entry.acceptedCount,
                needsReviewCount: entry.needsReviewCount,
                state: .reviewed,
                existing: entry
            )
            try saveRegistry(registry)
            return .resolved(
                batchID: batchID,
                roundID: envelope.roundID,
                acceptedReviewCount: acceptedReviewEvents.count,
                rejectedReviewCount: rejectedReviewCount
            )
        } catch {
            return .invalid(
                batchID: batchID.isEmpty ? nil : batchID,
                eventID: eventID.isEmpty ? nil : eventID,
                reason: error.localizedDescription
            )
        }
    }

    private func makeSwings(
        events: [WhoopMotionEvent],
        envelope: WhoopMotionEnvelope,
        receivedAt: Date
    ) async throws -> [GolfSwingMetrics] {
        var swings: [GolfSwingMetrics] = []
        swings.reserveCapacity(events.count)
        for event in events.sorted(by: {
            if $0.observedAt == $1.observedAt { return $0.eventID < $1.eventID }
            return $0.observedAt < $1.observedAt
        }) {
            let correlation = try await locationCorrelator.estimatedLocation(
                roundID: envelope.roundID,
                at: event.observedAt,
                maximumTimeGap: Self.maximumLocationTimeGap,
                maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy
            )
            // Shot displacement is the product contract for automatic WHOOP
            // events. A nil correlation is recoverable (for example, a queued
            // journal write may not have arrived yet), so keep the immutable
            // batch staged instead of terminally importing a locationless shot.
            guard let correlation else { throw WhoopMotionImportError.locationUnavailable }
            let location = SwingLocationObservation(
                latitude: correlation.estimatedFix.latitude,
                longitude: correlation.estimatedFix.longitude,
                altitudeMeters: correlation.estimatedFix.altitudeMeters,
                horizontalAccuracyMeters: correlation.estimatedFix.horizontalAccuracyMeters,
                capturedAt: correlation.estimatedFix.capturedAt,
                provenance: correlation.estimatedFix.provenance
            )
            let heartRateSource = event.metrics.heartRate?.source.metricSource
            swings.append(
                GolfSwingMetrics(
                    id: event.swingUUID,
                    capturedAt: event.observedAt,
                    peakG: event.metrics.peakG,
                    backswingSeconds: event.metrics.backswingSeconds,
                    downswingSeconds: event.metrics.downswingSeconds,
                    tempoRatio: event.metrics.tempoRatio,
                    heartRateBPM: event.metrics.heartRate?.bpm,
                    detectionConfidence: event.classification.confidence,
                    wristAnalysis: event.wristAnalysis,
                    provenance: DataProvenance(
                        source: .whoopMotion,
                        observedAt: event.observedAt,
                        receivedAt: receivedAt,
                        quality: .estimated,
                        algorithmVersion: "\(envelope.source.detector.name)-\(envelope.source.detector.version)",
                        inputSources: heartRateSource.map { [.whoopMotion, $0] } ?? [.whoopMotion]
                    ),
                    location: location,
                    locationCorrelationMethod: correlation.method
                )
            )
        }
        return swings
    }

    /// Hybrid mode counts only the Apple Watch observation. A uniquely matched
    /// WHOOP event may enrich it with delayed wrist analytics, but never adds a
    /// second shot. Any ambiguous, unsupported, duplicate, or unmatched WHOOP
    /// candidate keeps the immutable batch staged for explicit reconciliation.
    private func mergeHybridSwings(
        _ importedWHOOPSwings: [GolfSwingMetrics],
        into round: inout GolfRound
    ) -> Bool {
        let result = HybridSwingReconciler.reconcile(round.swings + importedWHOOPSwings)
        guard result.review.isEmpty else { return false }
        round.swings = result.canonicalSwings
        return true
    }

    private func validateCoverage(_ coverage: WhoopMotionCoverage, against round: GolfRound) throws {
        // RoundFileStore's existing ISO-8601 persistence normalizes to whole
        // seconds. Accept only the same second-sized serialization seam; a
        // different round window still cannot pass this sub-second gate.
        guard abs(coverage.roundStartedAt.timeIntervalSince(round.startedAt)) < 1,
              let endedAt = round.endedAt,
              abs(coverage.roundEndedAt.timeIntervalSince(endedAt)) < 1 else {
            throw WhoopMotionImportError.roundCoverageMismatch
        }
    }

    private func reviewEvents(in envelope: WhoopMotionEnvelope) -> [WhoopMotionEvent] {
        envelope.events.filter { $0.classification.decision == .needsReview }
    }

    private func reviewPendingReason(
        for state: WhoopMotionImportState
    ) -> WhoopMotionReviewPendingReason {
        switch state {
        case .stagedCrossSourceConflict:
            .crossSourceConflict
        case .stagedRoundUnavailable:
            .roundUnavailable
        case .stagedLocationUnavailable:
            .locationUnavailable
        case .stagedNeedsReview, .importedWithNeedsReview, .imported, .reviewed:
            .needsReview
        }
    }

    private func loadProtectedEnvelope(
        for entry: WhoopMotionImportRegistryEntry
    ) throws -> WhoopMotionEnvelope {
        let url = inboxDirectory.appendingPathComponent(entry.inboxFileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw WhoopMotionImportError.inboxMissing
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= Self.maximumPayloadBytes,
                  Self.sha256Hex(data) == entry.payloadSHA256 else {
                throw WhoopMotionImportError.inboxCorrupt
            }
            let envelope = try decoder.decode(WhoopMotionEnvelope.self, from: data)
            let acceptedCount = envelope.events.lazy.filter {
                $0.classification.decision == .accepted
            }.count
            let needsReviewCount = envelope.events.count - acceptedCount
            guard envelope.batchID == entry.batchID,
                  envelope.roundID == entry.roundID,
                  entry.schemaVersion == envelope.schemaVersion,
                  acceptedCount == entry.acceptedCount,
                  needsReviewCount == entry.needsReviewCount else {
                throw WhoopMotionImportError.inboxCorrupt
            }
            try protectItem(url)
            return envelope
        } catch let error as WhoopMotionImportError {
            throw error
        } catch {
            throw WhoopMotionImportError.inboxCorrupt
        }
    }

    private func loadReviewLedger(
        entry: WhoopMotionImportRegistryEntry,
        reviewEvents: [WhoopMotionEvent]
    ) throws -> WhoopMotionReviewDecisionLedger {
        let url = reviewLedgerURL(batchID: entry.batchID)
        guard fileManager.fileExists(atPath: url.path) else {
            return WhoopMotionReviewDecisionLedger(
                batchID: entry.batchID,
                roundID: entry.roundID,
                payloadSHA256: entry.payloadSHA256
            )
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= Self.maximumPayloadBytes else {
                throw WhoopMotionImportError.reviewLedgerCorrupt
            }
            let ledger = try decoder.decode(WhoopMotionReviewDecisionLedger.self, from: data)
            let expectedEventIDs = Set(reviewEvents.map(\.eventID))
            guard ledger.schemaVersion == WhoopMotionReviewDecisionLedger.schemaVersion,
                  ledger.batchID == entry.batchID,
                  ledger.roundID == entry.roundID,
                  ledger.payloadSHA256 == entry.payloadSHA256,
                  ledger.records.count <= reviewEvents.count,
                  ledger.records.allSatisfy({ key, record in
                      key == record.eventID
                          && record.batchID == entry.batchID
                          && record.roundID == entry.roundID
                          && record.payloadSHA256 == entry.payloadSHA256
                          && record.recordedBy == WhoopMotionReviewDecisionRecord.actor
                          && record.recordedAt.timeIntervalSince1970.isFinite
                          && expectedEventIDs.contains(key)
                  }) else {
                throw WhoopMotionImportError.reviewLedgerCorrupt
            }
            try protectItem(url)
            return ledger
        } catch let error as WhoopMotionImportError {
            throw error
        } catch {
            throw WhoopMotionImportError.reviewLedgerCorrupt
        }
    }

    private func saveReviewLedger(_ ledger: WhoopMotionReviewDecisionLedger) throws {
        try prepareProtectedDirectory(reviewDirectory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = reviewLedgerURL(batchID: ledger.batchID)
        try encoder.encode(ledger).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try protectItem(url)
    }

    private func reviewLedgerURL(batchID: String) -> URL {
        reviewDirectory
            .appendingPathComponent(batchID)
            .appendingPathExtension("json")
    }

    private func registryEntry(
        envelope: WhoopMotionEnvelope,
        digest: String,
        acceptedCount: Int,
        needsReviewCount: Int,
        state: WhoopMotionImportState,
        existing: WhoopMotionImportRegistryEntry?
    ) -> WhoopMotionImportRegistryEntry {
        let timestamp = now()
        return WhoopMotionImportRegistryEntry(
            batchID: envelope.batchID,
            roundID: envelope.roundID,
            schemaVersion: envelope.schemaVersion,
            payloadSHA256: digest,
            inboxFileName: envelope.batchID + ".json",
            acceptedCount: acceptedCount,
            needsReviewCount: needsReviewCount,
            firstSeenAt: existing?.firstSeenAt ?? timestamp,
            updatedAt: timestamp,
            state: state
        )
    }

    private func storeInInbox(
        _ data: Data,
        envelope: WhoopMotionEnvelope,
        digest: String
    ) throws {
        try prepareProtectedDirectory(inboxDirectory)
        let destination = inboxDirectory
            .appendingPathComponent(envelope.batchID)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination, options: .mappedIfSafe)
            guard Self.sha256Hex(existing) == digest, existing == data else {
                throw WhoopMotionImportError.identityCollision
            }
            try protectItem(destination)
            return
        }
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try protectItem(destination)
    }

    private func loadRegistry() throws -> WhoopMotionImportRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return WhoopMotionImportRegistry()
        }
        do {
            let data = try Data(contentsOf: registryURL, options: .mappedIfSafe)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let registry = try decoder.decode(WhoopMotionImportRegistry.self, from: data)
            guard registry.schemaVersion == 1 else {
                throw WhoopMotionImportError.registryUnsupported(registry.schemaVersion)
            }
            guard registry.entries.allSatisfy({ key, entry in
                key == entry.batchID
                    && WhoopMotionEnvelope.isLowercaseSHA256(entry.batchID)
                    && WhoopMotionEnvelope.isLowercaseSHA256(entry.payloadSHA256)
                    && entry.inboxFileName == entry.batchID + ".json"
                    && WhoopMotionEnvelope.supportedSchemaVersions.contains(entry.schemaVersion)
                    && (0...WhoopMotionEnvelope.maximumEvents).contains(entry.acceptedCount)
                    && (0...WhoopMotionEnvelope.maximumEvents).contains(entry.needsReviewCount)
                    && entry.acceptedCount + entry.needsReviewCount <= WhoopMotionEnvelope.maximumEvents
                    && (entry.state != .imported || entry.needsReviewCount == 0)
                    && (entry.state != .importedWithNeedsReview || entry.needsReviewCount > 0)
                    && (entry.state != .reviewed || entry.needsReviewCount > 0)
            }) else { throw WhoopMotionImportError.registryCorrupt }
            return registry
        } catch let error as WhoopMotionImportError {
            throw error
        } catch {
            throw WhoopMotionImportError.registryCorrupt
        }
    }

    private func saveRegistry(_ registry: WhoopMotionImportRegistry) throws {
        try prepareProtectedDirectory(storageDirectory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(
            to: registryURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try protectItem(registryURL)
    }

    private func prepareProtectedDirectory(_ directory: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            .posixPermissions: 0o700
        ]
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: attributes
        )
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
    }

    private func protectItem(_ url: URL) throws {
        try fileManager.setAttributes(
            [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                .posixPermissions: 0o600,
            ],
            ofItemAtPath: url.path
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: string) ?? standard.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }
}

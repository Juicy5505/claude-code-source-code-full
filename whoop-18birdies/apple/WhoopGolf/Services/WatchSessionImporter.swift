import CryptoKit
import Foundation

enum WatchSessionImportOutcome: Equatable, Sendable {
    case imported(sessionID: String, roundID: UUID, swingCount: Int)
    case pendingUserLink(sessionID: String)
    case duplicate(sessionID: String)
    case rangeStored(sessionID: String, swingCount: Int)
    case invalid(sessionID: String?, reason: String)
}

struct PendingWatchSession: Equatable, Sendable {
    let sessionID: String
    let startedAt: Date
    let completedAt: Date?
    let swingCount: Int
    let requestedRoundID: UUID?
}

/// Stable identity used when a watch swing is represented by GolfSwingMetrics,
/// whose existing persistence model requires a UUID. The custom version-8 UUID
/// is a SHA-256 projection of the exact `sessionID + index` identity.
struct WatchSwingIdentity: Hashable, Sendable {
    let sessionID: String
    let index: Int

    var rawValue: String { "\(sessionID)#\(index)" }

    var uuid: UUID {
        var bytes = Array(SHA256.hash(data: Data(rawValue.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private enum WatchImportRegistryState: String, Codable {
    case pendingUserLink
    case imported
    case rangeStored
}

private struct WatchImportRegistryEntry: Codable {
    let sessionID: String
    let schemaVersion: Int
    let mode: WatchSessionMode
    let embeddedRoundID: UUID?
    let payloadSHA256: String
    let rawFileName: String
    let startedAt: Date
    let completedAt: Date?
    let swingCount: Int
    let firstSeenAt: Date
    var updatedAt: Date
    var requestedRoundID: UUID?
    var state: WatchImportRegistryState
}

private struct WatchImportRegistry: Codable {
    var schemaVersion = 1
    var entries: [String: WatchImportRegistryEntry] = [:]
}

private enum WatchSessionImporterError: LocalizedError {
    case receivedIdentityMismatch
    case identityCollision
    case registryUnsupported(Int)
    case rangeCannotLink
    case embeddedRoundConflict
    case pendingSessionMissing
    case pendingRawFileMissing

    var errorDescription: String? {
        switch self {
        case .receivedIdentityMismatch:
            return "the received watch-session identity does not match its typed payload"
        case .identityCollision:
            return "a different payload is already registered for this watch-session identity"
        case .registryUnsupported(let version):
            return "watch import registry schema \(version) is unsupported"
        case .rangeCannotLink:
            return "range sessions are stored separately and cannot be linked to a round"
        case .embeddedRoundConflict:
            return "the user-selected round conflicts with the round identified by the watch"
        case .pendingSessionMissing:
            return "the pending watch session is not registered"
        case .pendingRawFileMissing:
            return "the pending watch session's protected raw file is unavailable"
        }
    }
}

/// Imports protected WatchConnectivity payloads without guessing round links.
///
/// Terminal registry entries make delivery idempotent across launches. A
/// pending entry remains eligible for an explicit user-selected link, and the
/// deterministic swing UUIDs also make a retry safe if the app terminated
/// after saving the round but before committing the registry update.
actor WatchSessionImporter {
    private let roundStore: RoundFileStore
    private let fileManager: FileManager
    private let storageDirectory: URL
    private let rawSessionsDirectory: URL
    private let rangeSessionsDirectory: URL
    private let registryURL: URL

    init(
        roundStore: RoundFileStore = RoundFileStore(),
        storageDirectory: URL? = nil,
        rawSessionsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.roundStore = roundStore
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let defaultStorage = applicationSupport
            .appendingPathComponent("WhoopGolf", isDirectory: true)
            .appendingPathComponent("WatchImports", isDirectory: true)
        let resolvedStorage = storageDirectory ?? defaultStorage
        self.storageDirectory = resolvedStorage
        self.rawSessionsDirectory = rawSessionsDirectory
            ?? applicationSupport.appendingPathComponent("WatchSessions", isDirectory: true)
        self.rangeSessionsDirectory = resolvedStorage
            .appendingPathComponent("RangeSessions", isDirectory: true)
        self.registryURL = resolvedStorage.appendingPathComponent("registry.json")
    }

    func importSession(
        _ received: ReceivedWatchSession,
        userSelectedRoundID: UUID? = nil
    ) async -> WatchSessionImportOutcome {
        await process(received, userSelectedRoundID: userSelectedRoundID)
    }

    /// Resumes a persisted legacy/ambiguous round only after the user has
    /// explicitly selected its destination round.
    func linkPendingSession(
        sessionID: String,
        to roundID: UUID
    ) async -> WatchSessionImportOutcome {
        do {
            let registry = try loadRegistry()
            guard let entry = registry.entries[sessionID] else {
                throw WatchSessionImporterError.pendingSessionMissing
            }
            if entry.state != .pendingUserLink {
                return .duplicate(sessionID: sessionID)
            }
            guard entry.mode == .round else {
                throw WatchSessionImporterError.rangeCannotLink
            }
            guard URL(fileURLWithPath: entry.rawFileName).lastPathComponent == entry.rawFileName else {
                throw WatchSessionImporterError.pendingRawFileMissing
            }

            let rawURL = rawSessionsDirectory.appendingPathComponent(entry.rawFileName)
            guard fileManager.fileExists(atPath: rawURL.path) else {
                throw WatchSessionImporterError.pendingRawFileMissing
            }
            let received = ReceivedWatchSession(
                id: entry.sessionID,
                schemaVersion: entry.schemaVersion,
                mode: entry.mode,
                roundID: entry.embeddedRoundID,
                fileURL: rawURL,
                receivedAt: entry.firstSeenAt
            )
            return await process(received, userSelectedRoundID: roundID)
        } catch {
            return .invalid(sessionID: sessionID, reason: error.localizedDescription)
        }
    }

    func pendingSessions() throws -> [PendingWatchSession] {
        try loadRegistry().entries.values
            .filter { $0.state == .pendingUserLink }
            .map {
                PendingWatchSession(
                    sessionID: $0.sessionID,
                    startedAt: $0.startedAt,
                    completedAt: $0.completedAt,
                    swingCount: $0.swingCount,
                    requestedRoundID: $0.requestedRoundID
                )
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func process(
        _ received: ReceivedWatchSession,
        userSelectedRoundID: UUID?
    ) async -> WatchSessionImportOutcome {
        do {
            let data = try Data(contentsOf: received.fileURL, options: .mappedIfSafe)
            let payload = try WatchSessionPayloadDecoder.decode(data)
            guard received.id == payload.sessionID,
                  received.schemaVersion == payload.schemaVersion,
                  received.mode == payload.mode,
                  received.roundID == payload.roundID else {
                throw WatchSessionImporterError.receivedIdentityMismatch
            }

            let digest = Self.sha256Hex(data)
            var registry = try loadRegistry()
            let existing = registry.entries[payload.sessionID]
            if let existing {
                guard existing.payloadSHA256 == digest,
                      existing.schemaVersion == payload.schemaVersion,
                      existing.mode == payload.mode,
                      existing.embeddedRoundID == payload.roundID else {
                    throw WatchSessionImporterError.identityCollision
                }
                if existing.state == .imported || existing.state == .rangeStored {
                    return .duplicate(sessionID: payload.sessionID)
                }
            }

            switch payload.mode {
            case .range:
                guard userSelectedRoundID == nil else {
                    throw WatchSessionImporterError.rangeCannotLink
                }
                try storeRangePayload(data, sessionID: payload.sessionID)
                registry.entries[payload.sessionID] = registryEntry(
                    payload: payload,
                    received: received,
                    digest: digest,
                    state: .rangeStored,
                    requestedRoundID: nil,
                    existing: existing
                )
                try saveRegistry(registry)
                return .rangeStored(
                    sessionID: payload.sessionID,
                    swingCount: payload.swings.count
                )

            case .round:
                if let embedded = payload.roundID,
                   let selected = userSelectedRoundID,
                   embedded != selected {
                    throw WatchSessionImporterError.embeddedRoundConflict
                }
                let destinationRoundID = userSelectedRoundID ?? payload.roundID
                guard let destinationRoundID else {
                    registry.entries[payload.sessionID] = registryEntry(
                        payload: payload,
                        received: received,
                        digest: digest,
                        state: .pendingUserLink,
                        requestedRoundID: nil,
                        existing: existing
                    )
                    try saveRegistry(registry)
                    return .pendingUserLink(sessionID: payload.sessionID)
                }

                let rounds = try await roundStore.rounds()
                guard var round = rounds.first(where: { $0.id == destinationRoundID }) else {
                    registry.entries[payload.sessionID] = registryEntry(
                        payload: payload,
                        received: received,
                        digest: digest,
                        state: .pendingUserLink,
                        requestedRoundID: destinationRoundID,
                        existing: existing
                    )
                    try saveRegistry(registry)
                    return .pendingUserLink(sessionID: payload.sessionID)
                }

                let importedSwings = StrokeScoreShotChain.enrichSwingMetrics(
                    SwingShotIntervalCalculator.finalizingIntervals(
                        in: payload.swings
                        .map { swing in
                            let location = swing.location.map { location in
                                SwingLocationObservation(
                                    latitude: location.latitude,
                                    longitude: location.longitude,
                                    altitudeMeters: location.altitude,
                                    horizontalAccuracyMeters: location.horizontalAccuracy,
                                    // Watch session schema 1 does not carry a
                                    // separate GPS timestamp, so the adapter
                                    // records its explicit same-swing timestamp.
                                    capturedAt: swing.timestamp,
                                    provenance: DataProvenance(
                                        source: .appleWatch,
                                        observedAt: swing.timestamp,
                                        receivedAt: received.receivedAt,
                                        quality: location.horizontalAccuracy.map {
                                            $0 <= SwingShotIntervalCalculator.maximumHorizontalAccuracyMeters
                                                ? .verified : .unavailable
                                        } ?? .unavailable,
                                        algorithmVersion: "watch-session-schema-\(payload.schemaVersion)"
                                    )
                                )
                            }
                            return GolfSwingMetrics(
                                id: WatchSwingIdentity(
                                    sessionID: payload.sessionID,
                                    index: swing.index
                                ).uuid,
                                capturedAt: swing.timestamp,
                                peakG: swing.peakG,
                                backswingSeconds: swing.backswingSeconds,
                                downswingSeconds: swing.downswingSeconds,
                                tempoRatio: swing.tempoRatio,
                                heartRateBPM: swing.heartRateBPM,
                                pathYawDegrees: swing.pathYawDegrees,
                                pathClass: swing.pathClass,
                                provenance: DataProvenance(
                                    source: .appleWatch,
                                    observedAt: swing.timestamp,
                                    receivedAt: received.receivedAt,
                                    quality: .verified,
                                    algorithmVersion: "watch-session-schema-\(payload.schemaVersion)"
                                ),
                                location: location,
                                locationCorrelationMethod: location == nil
                                    ? nil : .sensorSynchronized
                            )
                        }
                    ),
                    wrist: WatchWristMount.load()
                )
                let existingSwingIDs = Set(round.swings.map(\.id))
                round.swings.append(
                    contentsOf: importedSwings.filter { !existingSwingIDs.contains($0.id) }
                )
                try await roundStore.save(round)

                registry.entries[payload.sessionID] = registryEntry(
                    payload: payload,
                    received: received,
                    digest: digest,
                    state: .imported,
                    requestedRoundID: destinationRoundID,
                    existing: existing
                )
                try saveRegistry(registry)
                return .imported(
                    sessionID: payload.sessionID,
                    roundID: destinationRoundID,
                    swingCount: payload.swings.count
                )
            }
        } catch {
            return .invalid(sessionID: received.id, reason: error.localizedDescription)
        }
    }

    private func registryEntry(
        payload: WatchSessionPayload,
        received: ReceivedWatchSession,
        digest: String,
        state: WatchImportRegistryState,
        requestedRoundID: UUID?,
        existing: WatchImportRegistryEntry?
    ) -> WatchImportRegistryEntry {
        WatchImportRegistryEntry(
            sessionID: payload.sessionID,
            schemaVersion: payload.schemaVersion,
            mode: payload.mode,
            embeddedRoundID: payload.roundID,
            payloadSHA256: digest,
            rawFileName: received.fileURL.lastPathComponent,
            startedAt: payload.startedAt,
            completedAt: payload.completedAt,
            swingCount: payload.swings.count,
            firstSeenAt: existing?.firstSeenAt ?? received.receivedAt,
            updatedAt: Date(),
            requestedRoundID: requestedRoundID,
            state: state
        )
    }

    private func loadRegistry() throws -> WatchImportRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return WatchImportRegistry()
        }
        let data = try Data(contentsOf: registryURL, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let registry = try decoder.decode(WatchImportRegistry.self, from: data)
        guard registry.schemaVersion == 1 else {
            throw WatchSessionImporterError.registryUnsupported(registry.schemaVersion)
        }
        return registry
    }

    private func saveRegistry(_ registry: WatchImportRegistry) throws {
        try prepareProtectedDirectory(storageDirectory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(
            to: registryURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func storeRangePayload(_ data: Data, sessionID: String) throws {
        try prepareProtectedDirectory(rangeSessionsDirectory)
        let destination = rangeSessionsDirectory
            .appendingPathComponent(sessionID)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else {
                throw WatchSessionImporterError.identityCollision
            }
            try protectItem(destination)
            return
        }
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func prepareProtectedDirectory(_ directory: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
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
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

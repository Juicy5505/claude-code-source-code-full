import Combine
import Foundation
import WatchConnectivity

enum WatchSessionMode: String, Codable, Sendable {
    case round
    case range
}

struct WatchSessionLocationPayload: Decodable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy = "horizontal_accuracy"
    }
}

struct WatchSessionSwingPayload: Decodable, Equatable, Sendable {
    let index: Int
    let timestamp: Date
    let peakG: Double
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?
    let tempoFrames: String?
    let heartRateBPM: Int?
    let location: WatchSessionLocationPayload?
    /// Mount-corrected yaw from Watch `SwingAnalysis` (optional on older sessions).
    let pathYawDegrees: Double?
    /// `SwingPathClass.rawValue` when the Watch recorded a path cue.
    let pathClass: String?

    private enum CodingKeys: String, CodingKey {
        case index
        case timestamp
        case peakG = "peak_g"
        case backswingSeconds = "backswing_s"
        case downswingSeconds = "downswing_s"
        case tempoRatio = "tempo_ratio"
        case tempoFrames = "tempo_frames"
        case heartRateBPM = "hr_bpm"
        case location
        case pathYawDegrees = "path_yaw_deg"
        case pathClass = "path_class"
    }
}

/// Typed representation of the JSON emitted by `SessionModel` on watchOS.
/// Missing `schema_version` and `round_id` are accepted as schema-v1 legacy
/// payloads, but a legacy round remains unlinked until the user chooses one.
struct WatchSessionPayload: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let sessionID: String
    let mode: WatchSessionMode
    let roundID: UUID?
    let startedAt: Date
    let completedAt: Date?
    let autoThreshold: Bool
    let sampleRateHz: Int
    let swings: [WatchSessionSwingPayload]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case mode
        case roundID = "round_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case autoThreshold = "auto_threshold"
        case sampleRateHz = "sample_rate_hz"
        case swings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sessionID = try values.decode(String.self, forKey: .sessionID)
        mode = try values.decode(WatchSessionMode.self, forKey: .mode)
        roundID = try values.decodeIfPresent(UUID.self, forKey: .roundID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        autoThreshold = try values.decode(Bool.self, forKey: .autoThreshold)
        sampleRateHz = try values.decode(Int.self, forKey: .sampleRateHz)
        swings = try values.decode([WatchSessionSwingPayload].self, forKey: .swings)
    }
}

enum WatchSessionPayloadError: LocalizedError {
    case malformed(String)
    case unsupportedSchema(Int)
    case invalidSessionID
    case invalidTiming
    case invalidSampleRate
    case duplicateSwingIndex(Int)
    case invalidSwing(index: Int, field: String)
    case rangeHasRoundLink

    var errorDescription: String? {
        switch self {
        case .malformed(let reason):
            return "watch session JSON is malformed (\(reason))"
        case .unsupportedSchema(let version):
            return "watch session schema \(version) is unsupported"
        case .invalidSessionID:
            return "watch session has an invalid identity"
        case .invalidTiming:
            return "watch session completion precedes its start"
        case .invalidSampleRate:
            return "watch session has an invalid sample rate"
        case .duplicateSwingIndex(let index):
            return "watch session repeats swing index \(index)"
        case .invalidSwing(let index, let field):
            return "watch swing \(index) has an invalid \(field)"
        case .rangeHasRoundLink:
            return "a range session cannot identify a golf round"
        }
    }
}

enum WatchSessionPayloadDecoder {
    static let currentSchemaVersion = 1

    static func decode(_ data: Data) throws -> WatchSessionPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO-8601 timestamp"
            )
        }

        let payload: WatchSessionPayload
        do {
            payload = try decoder.decode(WatchSessionPayload.self, from: data)
        } catch {
            throw WatchSessionPayloadError.malformed(error.localizedDescription)
        }
        try validate(payload)
        return payload
    }

    private static func validate(_ payload: WatchSessionPayload) throws {
        guard payload.schemaVersion == currentSchemaVersion else {
            throw WatchSessionPayloadError.unsupportedSchema(payload.schemaVersion)
        }
        guard isSafeSessionID(payload.sessionID) else {
            throw WatchSessionPayloadError.invalidSessionID
        }
        if let completedAt = payload.completedAt, completedAt < payload.startedAt {
            throw WatchSessionPayloadError.invalidTiming
        }
        guard (1...1_000).contains(payload.sampleRateHz) else {
            throw WatchSessionPayloadError.invalidSampleRate
        }
        guard payload.mode != .range || payload.roundID == nil else {
            throw WatchSessionPayloadError.rangeHasRoundLink
        }

        var indexes = Set<Int>()
        for swing in payload.swings {
            guard swing.index > 0 else {
                throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "index")
            }
            guard indexes.insert(swing.index).inserted else {
                throw WatchSessionPayloadError.duplicateSwingIndex(swing.index)
            }
            guard swing.peakG.isFinite, swing.peakG >= 0 else {
                throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "peak g")
            }
            try validateOptionalDuration(swing.backswingSeconds, index: swing.index, field: "backswing")
            try validateOptionalDuration(swing.downswingSeconds, index: swing.index, field: "downswing")
            if let ratio = swing.tempoRatio, (!ratio.isFinite || ratio <= 0) {
                throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "tempo ratio")
            }
            if let bpm = swing.heartRateBPM, !(1...300).contains(bpm) {
                throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "heart rate")
            }
            if let location = swing.location {
                guard location.latitude.isFinite,
                      location.longitude.isFinite,
                      (-90...90).contains(location.latitude),
                      (-180...180).contains(location.longitude)
                else {
                    throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "location")
                }
                if let altitude = location.altitude, !altitude.isFinite {
                    throw WatchSessionPayloadError.invalidSwing(index: swing.index, field: "altitude")
                }
                if let accuracy = location.horizontalAccuracy,
                   (!accuracy.isFinite || accuracy < 0) {
                    throw WatchSessionPayloadError.invalidSwing(
                        index: swing.index,
                        field: "horizontal accuracy"
                    )
                }
            }
        }
    }

    private static func validateOptionalDuration(
        _ value: Double?,
        index: Int,
        field: String
    ) throws {
        if let value, (!value.isFinite || value < 0) {
            throw WatchSessionPayloadError.invalidSwing(index: index, field: field)
        }
    }

    static func isSafeSessionID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 180 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) ||
            (65...90).contains(byte) ||
            (97...122).contains(byte) ||
            byte == 45 || byte == 95
        }
    }
}

/// A completed watch session now owned by the iPhone app container.
struct ReceivedWatchSession: Identifiable, Equatable, Sendable {
    let id: String
    let schemaVersion: Int
    let mode: WatchSessionMode
    let roundID: UUID?
    let fileURL: URL
    let receivedAt: Date
}

struct WatchSessionRecoveryFailure: Identifiable, Equatable, Sendable {
    let fileURL: URL
    let reason: String

    var id: String { fileURL.path }
}

struct WatchSessionRecoverySnapshot: Equatable, Sendable {
    let sessions: [ReceivedWatchSession]
    let failures: [WatchSessionRecoveryFailure]
}

private enum WatchSessionReceiveError: LocalizedError {
    case fileTooLarge
    case invalidPayload(String)
    case metadataMismatch
    case identityCollision

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "watch session exceeds the 5 MB safety limit"
        case .invalidPayload(let reason):
            return reason
        case .metadataMismatch:
            return "watch transfer metadata does not match its payload"
        case .identityCollision:
            return "a different watch session already uses this identity"
        }
    }
}

/// WCSession's incoming file is temporary and is deleted as soon as the
/// delegate callback returns. This synchronous helper validates it and moves it
/// into Application Support before that deadline.
private func takeOwnershipOfWatchSession(
    _ incomingURL: URL,
    metadata: [String: Any]?
) throws -> ReceivedWatchSession {
    let fileManager = FileManager.default
    let byteCount = try incomingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard byteCount.map({ $0 <= 5_000_000 }) ?? true else {
        throw WatchSessionReceiveError.fileTooLarge
    }
    let data = try Data(contentsOf: incomingURL, options: .mappedIfSafe)
    guard data.count <= 5_000_000 else { throw WatchSessionReceiveError.fileTooLarge }

    let payload: WatchSessionPayload
    do {
        payload = try WatchSessionPayloadDecoder.decode(data)
    } catch {
        throw WatchSessionReceiveError.invalidPayload(error.localizedDescription)
    }

    let metadataID = metadata?["sessionID"] as? String
    let metadataMode = metadata?["mode"] as? String
    let schemaVersion = metadata?["schemaVersion"] as? Int
    if let schemaVersion, schemaVersion != payload.schemaVersion {
        throw WatchSessionReceiveError.metadataMismatch
    }
    if let metadataID, payload.sessionID != metadataID {
        throw WatchSessionReceiveError.metadataMismatch
    }
    if let metadataMode, metadataMode != payload.mode.rawValue {
        throw WatchSessionReceiveError.metadataMismatch
    }
    let root = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directory = root.appendingPathComponent("WatchSessions", isDirectory: true)
    let protection: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ]
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: protection
    )
    try fileManager.setAttributes(protection, ofItemAtPath: directory.path)

    let destination = directory
        .appendingPathComponent(payload.sessionID, isDirectory: false)
        .appendingPathExtension("json")
    if fileManager.fileExists(atPath: destination.path) {
        if (try? Data(contentsOf: destination)) == data {
            // Idempotent repeat: the durable copy is already present. Removing
            // the Inbox file still satisfies WatchConnectivity's ownership
            // rule before the callback returns.
            try fileManager.setAttributes(protection, ofItemAtPath: destination.path)
            try? fileManager.removeItem(at: incomingURL)
            return ReceivedWatchSession(
                id: payload.sessionID,
                schemaVersion: payload.schemaVersion,
                mode: payload.mode,
                roundID: payload.roundID,
                fileURL: destination,
                receivedAt: Date()
            )
        }
        throw WatchSessionReceiveError.identityCollision
    }

    do {
        try fileManager.moveItem(at: incomingURL, to: destination)
        try fileManager.setAttributes(protection, ofItemAtPath: destination.path)
    } catch {
        // Cross-volume moves are unusual inside one app container, but an
        // atomic copy still takes ownership before WCSession removes Inbox.
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try? fileManager.removeItem(at: incomingURL)
    }
    return ReceivedWatchSession(
        id: payload.sessionID,
        schemaVersion: payload.schemaVersion,
        mode: payload.mode,
        roundID: payload.roundID,
        fileURL: destination,
        receivedAt: Date()
    )
}

/// Pure directory scanner used both at launch and by focused recovery tests.
/// Every JSON candidate is evaluated independently so one corrupt transfer can
/// never hide other valid sessions waiting for the idempotent importer.
enum WatchSessionRecoveryScanner {
    static func scan(
        directory: URL,
        fileManager: FileManager = .default
    ) -> WatchSessionRecoverySnapshot {
        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return WatchSessionRecoverySnapshot(
                sessions: [],
                failures: [
                    WatchSessionRecoveryFailure(
                        fileURL: directory,
                        reason: "stored Watch sessions could not be enumerated (\(error.localizedDescription))"
                    ),
                ]
            )
        }

        var sessions: [ReceivedWatchSession] = []
        var failures: [WatchSessionRecoveryFailure] = []
        for fileURL in candidates {
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ])
                guard values.isRegularFile == true else {
                    throw WatchSessionReceiveError.invalidPayload("stored entry is not a regular file")
                }
                guard values.fileSize.map({ $0 <= 5_000_000 }) ?? false else {
                    throw WatchSessionReceiveError.fileTooLarge
                }
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let payload = try WatchSessionPayloadDecoder.decode(data)
                guard fileURL.deletingPathExtension().lastPathComponent == payload.sessionID else {
                    throw WatchSessionReceiveError.metadataMismatch
                }
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: fileURL.path
                )
                sessions.append(
                    ReceivedWatchSession(
                        id: payload.sessionID,
                        schemaVersion: payload.schemaVersion,
                        mode: payload.mode,
                        roundID: payload.roundID,
                        fileURL: fileURL,
                        receivedAt: values.contentModificationDate ?? .distantPast
                    )
                )
            } catch {
                failures.append(
                    WatchSessionRecoveryFailure(
                        fileURL: fileURL,
                        reason: error.localizedDescription
                    )
                )
            }
        }
        return WatchSessionRecoverySnapshot(
            sessions: sessions.sorted {
                if $0.receivedAt != $1.receivedAt { return $0.receivedAt < $1.receivedAt }
                return $0.id < $1.id
            },
            failures: failures
        )
    }
}

/// iPhone-side receiver for the watch's background file outbox.
///
/// The application must retain `shared` and call `activate()` during launch;
/// WatchConnectivity may wake the app in the background to deliver a file.
@MainActor
final class WatchSessionReceiver: NSObject, ObservableObject {
    static let shared = WatchSessionReceiver()

    @Published private(set) var lastReceived: ReceivedWatchSession?
    @Published private(set) var lastError: String?
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var activeRoundContext: WatchRoundContext?
    @Published private(set) var contextSyncError: String?
    @Published private(set) var recoveredSessions: [ReceivedWatchSession] = []
    @Published private(set) var recoveryFailures: [WatchSessionRecoveryFailure] = []
    @Published private(set) var liveFace = WatchLiveFace()
    @Published private(set) var lastWatchHeartRate: Int?
    @Published private(set) var lastWatchPathCue: String?
    @Published private(set) var lastWatchImproverTip: String?
    @Published private(set) var lastWatchImproverDrill: String?
    @Published private(set) var lastWatchSwingAt: Date?
    @Published private(set) var coachingCue = WatchCoachingCue()

    private let connectivitySession: WCSession?
    private var desiredRoundContext: WatchRoundContext?
    private var hasDesiredRoundContext = false
    private var desiredCoaching: WatchCoachingCue?
    private var hasDesiredCoaching = false

    private override init() {
        connectivitySession = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func activate() {
        _ = recoverStoredSessions()
        guard let connectivitySession else {
            lastError = "WatchConnectivity is unavailable on this iPhone"
            return
        }
        connectivitySession.delegate = self
        refreshConnectionState(from: connectivitySession)
        connectivitySession.activate()
    }

    /// Publishes the exact persisted phone-round identity. Delivery does not
    /// require live reachability; WatchConnectivity retains the latest
    /// application context and delivers it when the paired Watch is available.
    func publishActiveRound(
        roundID: UUID,
        courseName: String,
        startedAt: Date
    ) {
        let context = WatchRoundContext(
            roundID: roundID,
            courseName: courseName,
            startedAt: startedAt
        )
        desiredRoundContext = context
        hasDesiredRoundContext = true
        activeRoundContext = context
        synchronizeRoundContextIfPossible()
    }

    /// Replaces a previously published identity with an explicit cleared
    /// envelope. The Watch will therefore never link a new session to a round
    /// merely because an old UUID was the last value it saw.
    func clearActiveRound() {
        desiredRoundContext = nil
        hasDesiredRoundContext = true
        activeRoundContext = nil
        synchronizeRoundContextIfPossible()
    }

    /// Publishes hole/yardage/wrist to the Watch. Missing front/mid/back is
    /// honest: facility search is not a green map.
    func publishLiveFace(_ face: WatchLiveFace) {
        var next = face
        if next.wristMount != WatchWristMount.load() && next.wristMount != .golferDefault {
            WatchWristMount.save(next.wristMount)
        } else {
            next.wristMount = WatchWristMount.load()
        }
        liveFace = next
        synchronizeRoundContextIfPossible()
    }

    /// Publishes path cue + improver tip into applicationContext (latest-wins).
    /// Watch also pushes coaching via durable `transferUserInfo` when offline.
    func publishCoaching(_ cue: WatchCoachingCue) {
        desiredCoaching = cue
        hasDesiredCoaching = true
        coachingCue = cue
        if let path = cue.pathCue { lastWatchPathCue = path }
        if let tip = cue.improverTip { lastWatchImproverTip = tip }
        if let drill = cue.improverDrill { lastWatchImproverDrill = drill }
        synchronizeRoundContextIfPossible()
    }

    /// Validates every protected raw JSON file already owned by the app. This
    /// is the crash/relaunch path: AppModel can feed each returned session to
    /// the idempotent importer instead of relying only on the newest callback.
    @discardableResult
    func recoverStoredSessions() -> WatchSessionRecoverySnapshot {
        let snapshot = loadStoredSessions()
        recoveredSessions = snapshot.sessions
        recoveryFailures = snapshot.failures
        return snapshot
    }

    private func synchronizeRoundContextIfPossible() {
        guard let connectivitySession else {
            if hasDesiredRoundContext || hasDesiredCoaching {
                contextSyncError = "WatchConnectivity is unavailable on this iPhone"
            }
            return
        }
        guard connectivitySession.activationState == .activated else {
            contextSyncError = nil
            return
        }
        do {
            var payload: [String: Any]
            if hasDesiredRoundContext {
                payload = try WatchRoundApplicationContextCodec.encode(desiredRoundContext)
            } else {
                payload = connectivitySession.applicationContext
            }
            payload = try WatchLiveFaceCodec.merge(liveFace, into: payload)
            if hasDesiredCoaching, let desiredCoaching {
                payload = try WatchCoachingCueCodec.merge(desiredCoaching, into: payload)
            } else if hasDesiredRoundContext,
                      let existing = connectivitySession.applicationContext[
                        WatchCoachingCueCodec.applicationContextKey
                      ] {
                // Round re-encode starts from a fresh dict — keep prior coaching.
                payload[WatchCoachingCueCodec.applicationContextKey] = existing
            }
            try connectivitySession.updateApplicationContext(payload)
            contextSyncError = nil
        } catch {
            contextSyncError = error.localizedDescription
        }
    }

    private func applyInboundCoaching(_ cue: WatchCoachingCue) {
        coachingCue = cue
        if let path = cue.pathCue {
            lastWatchPathCue = path
            lastWatchSwingAt = Date()
        }
        if let tip = cue.improverTip { lastWatchImproverTip = tip }
        if let drill = cue.improverDrill { lastWatchImproverDrill = drill }
        if let hr = cue.heartRateBPM { lastWatchHeartRate = hr }
        if let wristRaw = cue.wristMount, let mount = WatchWristMount(rawValue: wristRaw) {
            WatchWristMount.save(mount)
            liveFace.wristMount = mount
        }
    }

    private func applyInboundApplicationContext(_ applicationContext: [String: Any]) {
        do {
            if let face = try WatchLiveFaceCodec.decode(applicationContext) {
                liveFace.wristMount = face.wristMount
                WatchWristMount.save(face.wristMount)
            }
        } catch {
            lastError = error.localizedDescription
        }
        do {
            if let cue = try WatchCoachingCueCodec.decode(applicationContext) {
                applyInboundCoaching(cue)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshConnectionState(from session: WCSession) {
        activationState = session.activationState
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    private func loadStoredSessions() -> WatchSessionRecoverySnapshot {
        let fileManager = FileManager.default
        let directory: URL
        do {
            let root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = root.appendingPathComponent("WatchSessions", isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                ]
            )
        } catch {
            let fallback = URL(fileURLWithPath: "WatchSessions", isDirectory: true)
            return WatchSessionRecoverySnapshot(
                sessions: [],
                failures: [
                    WatchSessionRecoveryFailure(
                        fileURL: fallback,
                        reason: "the protected Watch session directory is unavailable (\(error.localizedDescription))"
                    ),
                ]
            )
        }

        return WatchSessionRecoveryScanner.scan(
            directory: directory,
            fileManager: fileManager
        )
    }

    private func didReceive(_ session: ReceivedWatchSession) {
        lastReceived = session
        lastError = nil
        if let index = recoveredSessions.firstIndex(where: { $0.id == session.id }) {
            recoveredSessions[index] = session
        } else {
            recoveredSessions.append(session)
        }
        recoveredSessions.sort {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt < $1.receivedAt }
            return $0.id < $1.id
        }
        NotificationCenter.default.post(
            name: .watchSessionDidArrive,
            object: self,
            userInfo: ["sessionID": session.id, "fileURL": session.fileURL]
        )
    }
}

extension Notification.Name {
    static let watchSessionDidArrive = Notification.Name("WatchSessionDidArrive")
}

extension WatchSessionReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshConnectionState(from: session)
            self.activationState = activationState
            self.lastError = errorDescription
            if activationState == .activated, error == nil {
                self.synchronizeRoundContextIfPossible()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required when the user changes watches; activation binds the receiver
        // to the newly selected device and resumes outstanding deliveries.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshConnectionState(from: session)
            self?.synchronizeRoundContextIfPossible()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshConnectionState(from: session)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.applyInboundApplicationContext(applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cue = WatchCoachingCueCodec.cue(fromUserInfo: userInfo) {
                self.applyInboundCoaching(cue)
            }
            if let wristRaw = userInfo["wristMount"] as? String,
               let mount = WatchWristMount(rawValue: wristRaw) {
                WatchWristMount.save(mount)
                self.liveFace.wristMount = mount
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let received: ReceivedWatchSession?
        let errorDescription: String?
        do {
            received = try takeOwnershipOfWatchSession(
                file.fileURL,
                metadata: file.metadata
            )
            errorDescription = nil
        } catch {
            received = nil
            errorDescription = error.localizedDescription
        }

        Task { @MainActor [weak self] in
            if let received {
                self?.didReceive(received)
            } else {
                self?.lastError = errorDescription ?? "watch session could not be received"
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cue = WatchCoachingCueCodec.cue(fromUserInfo: message) {
                self.applyInboundCoaching(cue)
                return
            }
            let wristRaw = message["wristMount"] as? String
            let hr = message["hr"] as? Int
            let path = message["path"] as? String ?? message["pathCue"] as? String
            let tip = message["improverTip"] as? String
            let drill = message["improverDrill"] as? String
            if let wristRaw, let mount = WatchWristMount(rawValue: wristRaw) {
                WatchWristMount.save(mount)
                self.liveFace.wristMount = mount
            }
            if let hr { self.lastWatchHeartRate = hr }
            if let tip { self.lastWatchImproverTip = tip }
            if let drill { self.lastWatchImproverDrill = drill }
            if let path {
                self.lastWatchPathCue = path
                self.lastWatchSwingAt = Date()
            }
        }
    }
}

import Combine
import Foundation
import WatchConnectivity

/// Watch-side WCSession: receives phone round identity + live yardage/wrist/
/// coaching, and sends finished session JSON plus durable path/improver cues.
@MainActor
final class WatchSessionTransfer: NSObject, ObservableObject {
    static let shared = WatchSessionTransfer()

    @Published private(set) var roundContext: WatchRoundContext?
    @Published private(set) var liveFace: WatchLiveFace
    @Published private(set) var coachingCue = WatchCoachingCue()
    @Published private(set) var isReachable = false
    @Published private(set) var lastError: String?

    private let connectivitySession: WCSession?
    private var pendingSessionTransfers: [(fileURL: URL, metadata: [String: Any])] = []

    private override init() {
        let face = WatchLiveFace(wristMount: WatchWristMount.load())
        liveFace = face
        connectivitySession = WCSession.isSupported() ? .default : nil
        super.init()
        WatchWristMount.save(face.wristMount)
    }

    func activate() {
        guard let connectivitySession else {
            lastError = "WatchConnectivity is unavailable on this Watch"
            return
        }
        connectivitySession.delegate = self
        isReachable = connectivitySession.isReachable
        connectivitySession.activate()
        apply(applicationContext: connectivitySession.receivedApplicationContext)
    }

    func setWrist(_ mount: WatchWristMount) {
        WatchWristMount.save(mount)
        // Preserve yards/hole/path already received from the phone — a
        // wrist-only WatchLiveFace() would wipe the live-face envelope.
        var face = liveFace
        face.wristMount = mount
        liveFace = face
        guard let session = connectivitySession else { return }

        // Durable latest-wins when the phone is asleep / unreachable.
        if session.activationState == .activated {
            do {
                var payload = session.applicationContext
                // Prefer context face (phone-authoritative yards) then local.
                if var contextFace = try WatchLiveFaceCodec.decode(payload) {
                    contextFace.wristMount = mount
                    face = contextFace
                    liveFace = face
                }
                payload = try WatchLiveFaceCodec.merge(face, into: payload)
                try session.updateApplicationContext(payload)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            session.transferUserInfo([
                WatchCoachingCueCodec.userInfoKindKey: WatchCoachingCueCodec.userInfoKindValue,
                "wristMount": mount.rawValue,
            ])
        }

        if session.isReachable {
            session.sendMessage(["wristMount": mount.rawValue], replyHandler: nil) { [weak self] error in
                Task { @MainActor in self?.lastError = error.localizedDescription }
            }
        }
    }

    /// Transfers a phone-compatible session JSON file. Delivery is durable;
    /// the iPhone importer is idempotent on session ID. If WCSession is not
    /// activated yet, the transfer is queued and flushed on activation.
    func transferSession(data: Data, sessionID: String, mode: String, roundID: UUID?) {
        guard let connectivitySession else {
            lastError = "WatchConnectivity is unavailable on this Watch"
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(sessionID).json")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            return
        }
        var metadata: [String: Any] = [
            "sessionID": sessionID,
            "mode": mode,
            "schemaVersion": 1,
        ]
        if let roundID {
            metadata["roundID"] = roundID.uuidString
        }
        enqueueOrTransfer(fileURL: fileURL, metadata: metadata, session: connectivitySession)
    }

    /// Immediate `sendMessage` when reachable, plus durable `transferUserInfo`
    /// so path / improver / HR survive when the phone is not reachable.
    func sendLiveSwing(path: String, peakG: Double, heartRate: Int?) {
        let pathClass = Self.pathClass(fromCoachingLabel: path)
        let wrist = WatchWristMount.load()
        let tip = GolfImprover.cue(path: pathClass, tempoRatio: nil, wrist: wrist)
        let drill = GolfImprover.drill(path: pathClass, tempoRatio: nil, wrist: wrist)
        let cue = WatchCoachingCue(
            pathCue: path,
            improverTip: tip,
            improverDrill: drill,
            wristMount: wrist,
            peakG: peakG,
            heartRateBPM: heartRate
        )
        coachingCue = cue

        guard let connectivitySession else { return }

        if connectivitySession.activationState == .activated {
            _ = connectivitySession.transferUserInfo(WatchCoachingCueCodec.userInfo(from: cue))
        }

        guard connectivitySession.isReachable else { return }
        var message: [String: Any] = [
            WatchCoachingCueCodec.userInfoKindKey: WatchCoachingCueCodec.userInfoKindValue,
            "path": path,
            "pathCue": path,
            "peakG": peakG,
            "improverTip": tip,
            "improverDrill": drill,
            "wristMount": wrist.rawValue,
        ]
        if let heartRate { message["hr"] = heartRate }
        connectivitySession.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    private func enqueueOrTransfer(
        fileURL: URL,
        metadata: [String: Any],
        session: WCSession
    ) {
        if session.activationState != .activated {
            pendingSessionTransfers.append((fileURL, metadata))
            lastError = "phone link is not active yet — session queued on Watch"
            return
        }
        _ = session.transferFile(fileURL, metadata: metadata)
        lastError = nil
    }

    private func flushPendingTransfers(using session: WCSession) {
        guard session.activationState == .activated else { return }
        let pending = pendingSessionTransfers
        pendingSessionTransfers.removeAll()
        for item in pending {
            _ = session.transferFile(item.fileURL, metadata: item.metadata)
        }
        if !pending.isEmpty {
            lastError = nil
        }
    }

    private func apply(applicationContext: [String: Any]) {
        do {
            if let round = try WatchRoundApplicationContextCodec.decode(applicationContext) {
                roundContext = round
            } else if applicationContext["com.alex.whoopgolf.round-context"] != nil {
                // Explicit cleared envelope — drop stale round identity.
                roundContext = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        do {
            if let face = try WatchLiveFaceCodec.decode(applicationContext) {
                liveFace = face
                WatchWristMount.save(face.wristMount)
            }
        } catch {
            lastError = error.localizedDescription
        }
        do {
            if let cue = try WatchCoachingCueCodec.decode(applicationContext) {
                coachingCue = cue
                if let wristRaw = cue.wristMount, let mount = WatchWristMount(rawValue: wristRaw) {
                    WatchWristMount.save(mount)
                    liveFace.wristMount = mount
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func pathClass(fromCoachingLabel label: String) -> SwingPathClass {
        switch label {
        case "in-to-out": return .inToOut
        case "on-plane": return .onPlane
        case "out-to-in": return .outToIn
        default: return .unknown
        }
    }
}

extension WatchSessionTransfer: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = session.isReachable
            self.lastError = error?.localizedDescription
            self.apply(applicationContext: session.receivedApplicationContext)
            if activationState == .activated, error == nil {
                self.flushPendingTransfers(using: session)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.apply(applicationContext: applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cue = WatchCoachingCueCodec.cue(fromUserInfo: userInfo) {
                self.coachingCue = cue
                if let wristRaw = cue.wristMount, let mount = WatchWristMount(rawValue: wristRaw) {
                    WatchWristMount.save(mount)
                    self.liveFace.wristMount = mount
                }
            } else if let wristRaw = userInfo["wristMount"] as? String,
                      let mount = WatchWristMount(rawValue: wristRaw) {
                WatchWristMount.save(mount)
                self.liveFace.wristMount = mount
            }
        }
    }
}

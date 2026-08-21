import Foundation
import Combine

/// One detected swing, encoded to match the swings.json schema the Python
/// tools (round_report.py / analyze.py) already read.
struct Swing: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let timestamp: String
    var peak_g: Double
    var backswing_s: Double?
    var downswing_s: Double?
    var tempo_ratio: Double?
    var tempo_frames: String?
    var hr_bpm: Int?
    var location: GeoPoint?
    /// Distance to the NEXT swing, filled in when the session ends. Absent
    /// until then, and on the final swing, which has no successor.
    var distance_m: Double?
    var distance_yd: Double?
    var path_class: String?
    var path_yaw_deg: Double?
}

struct GeoPoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontal_accuracy: Double?
}

/// The whole session, matching the logger's file wrapper so it round-trips
/// through the same analysis pipeline.
struct SessionLog: Codable {
    let schema_version: Int
    let session_id: String
    let mode: String
    let round_id: String?
    let started_at: String
    let completed_at: String?
    let auto_threshold: Bool
    let sample_rate_hz: Int
    var swings: [Swing]
    /// Set when the watch appeared to be reporting the phone's position rather
    /// than the wrist's, which makes every distance in this file cart-to-cart.
    /// Present in the log so the warning outlives the watch face it appeared on.
    var gps_warning: String?
}

/// Observable state the SwiftUI views bind to, plus persistence and upload.
@MainActor
final class SessionModel: ObservableObject {
    @Published var swings: [Swing] = []
    @Published var lastPeakG: Double?
    @Published var lastTempo: Double?
    @Published var lastFrames: String?
    @Published var lastPath: SwingPathClass = .unknown
    @Published var lastPathYaw: Double?
    @Published var currentHR: Int?
    @Published var status: String = "starting…"
    @Published var running = false

    let mode: String                 // "range" or "round"
    let sessionID: String
    let startedAt: Date
    private let iso = ISO8601DateFormatter()

    /// Point this at your `wb serve` instance (the same host the iPhone Shortcut
    /// used), e.g. "http://192.168.1.24:8790/swings". Empty = keep on-device only.
    /// Configured in Upload settings on the watch — not hardcoded here.
    private var ingestURL: String { IngestSettings.url }
    private var ingestToken: String { IngestSettings.token }

    init(mode: String) {
        self.mode = mode
        self.sessionID = "\(mode)-\(UUID().uuidString.prefix(8))"
        self.startedAt = Date()
        // LOCAL time, deliberately. ISO8601DateFormatter defaults to UTC, and
        // the ingest server files a session under the first swing's calendar
        // date — so an evening round in the US would be stored under tomorrow
        // and silently fall out of the WHOOP join, which matches physiology on
        // the local date. Same bug class as the tee-time fix in rounds/ingest.
        iso.timeZone = TimeZone.current
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func record(_ metrics: SwingMetrics, hr: Int?, location: GeoPoint?) {
        let swing = Swing(
            index: swings.count + 1,
            timestamp: iso.string(from: Date()),
            peak_g: metrics.peakG,
            backswing_s: metrics.backswingS,
            downswing_s: metrics.downswingS,
            tempo_ratio: metrics.tempoRatio,
            tempo_frames: metrics.tempoFrames,
            hr_bpm: hr,
            location: location,
            path_class: metrics.pathClass.rawValue,
            path_yaw_deg: metrics.pathYawDeg
        )
        swings.append(swing)
        lastPeakG = metrics.peakG
        lastTempo = metrics.tempoRatio
        lastFrames = metrics.tempoFrames
        lastPath = metrics.pathClass
        lastPathYaw = metrics.pathYawDeg
        if mode == "round" { computeShotDistances() }
        autosave()
        WatchSessionTransfer.shared.sendLiveSwing(
            path: SwingPathGuidance.coachingLabel(metrics.pathClass),
            peakG: metrics.peakG,
            heartRate: hr
        )
    }

    /// Great-circle distance in metres. A faithful port of `haversine_m` in
    /// iphone/shot_model.py, which is the tested reference.
    /// `nonisolated` deliberately: this is pure arithmetic with no state, and
    /// the golden-vector tests call it from XCTest, which is not on the main
    /// actor. Without this the whole test target fails to compile.
    nonisolated static func haversineMetres(_ lat1: Double, _ lon1: Double,
                                            _ lat2: Double, _ lon2: Double) -> Double {
        let earthRadius = 6_371_008.8
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let a = pow(sin(dp / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    /// Measures each shot as the distance from where you swung to where you
    /// swung next — the Arccos/Shot Scope method.
    ///
    /// This has to happen on the watch, not only in the desktop analysis. The
    /// watch already writes a session the Python tools read; if it ships
    /// locations with no distances, the round shows a yardage of nothing on the
    /// device you were wearing, and the number you actually wanted only appears
    /// later, if you remember to run the analysis at all.
    ///
    /// Both coordinates are guarded on both fixes: latitude and longitude come
    /// from the GPS independently, so one can be present while the other is not.
    func computeShotDistances() {
        for i in swings.indices {
            swings[i].distance_m = nil
            swings[i].distance_yd = nil
            guard i + 1 < swings.count,
                  let here = swings[i].location,
                  let next = swings[i + 1].location
            else { continue }
            let metres = Self.haversineMetres(here.latitude, here.longitude,
                                              next.latitude, next.longitude)
            swings[i].distance_m = (metres * 10).rounded(.toNearestOrEven) / 10
            swings[i].distance_yd = ((metres / 0.9144) * 10).rounded(.toNearestOrEven) / 10
        }
    }

    /// Measured shots, for the on-watch summary.
    var measuredDistances: [Double] {
        swings.compactMap(\.distance_yd)
    }

    var longestYards: Double? { measuredDistances.max() }

    var tempoMean: Double? {
        let vals = swings.compactMap { $0.tempo_ratio }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var tempoCV: Double? {
        let vals = swings.compactMap { $0.tempo_ratio }
        guard vals.count > 1, let mean = tempoMean, mean != 0 else { return nil }
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(vals.count - 1)
        return variance.squareRoot() / mean
    }

    private func fileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(mode == "round" ? "swings.json" : "range_session.json")
    }

    private func encoded(rateHz: Int, completed: Bool = false) -> Data? {
        let roundID = WatchSessionTransfer.shared.roundContext?.roundID.uuidString
        let log = SessionLog(
            schema_version: 1,
            session_id: sessionID,
            mode: mode,
            round_id: mode == "round" ? roundID : nil,
            started_at: iso.string(from: startedAt),
            completed_at: completed ? iso.string(from: Date()) : nil,
            auto_threshold: true,
            sample_rate_hz: rateHz,
            swings: swings,
            gps_warning: gpsWarning
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(log)
    }

    /// Atomic per-swing save, so an interrupted write can never truncate the
    /// session already recorded.
    ///
    /// `Data.write(options: .atomic)` is already a write-to-temp-then-rename on
    /// Apple platforms, which is why there is no manual temp file here. An
    /// earlier version did the dance by hand with `replaceItemAt`, and that
    /// silently lost every session: `replaceItemAt` requires the destination to
    /// already exist, so the very first save threw, the error was swallowed, and
    /// the file was therefore never created — on any save, ever.
    func autosave(rateHz: Int = 100) {
        guard let data = encoded(rateHz: rateHz) else { return }
        do {
            try data.write(to: fileURL(), options: .atomic)
        } catch {
            // A failed save must never crash a live session; the previous good
            // file survives, and the session is still in memory for upload.
            status = "save failed — session still in memory"
        }
    }

    /// The rate actually achieved, measured over the session. Reporting a
    /// hardcoded 100 Hz makes a session that ran at 60 look like one that ran
    /// clean, and the tempo derived from it correspondingly trustworthy.
    var achievedRateHz: Int = 100

    /// Carried into the saved log, so a round with suspect positions is
    /// identifiable weeks later rather than silently averaged in.
    var gpsWarning: String?

    // MARK: - Upload, with a queue that survives a course with no signal

    /// Where unsent sessions wait. One file per round, named by the instant it
    /// finished, so a second round can never overwrite a first that has not yet
    /// been delivered — which the fixed `swings.json` filename allowed.
    nonisolated private static var outboxDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("outbox", isDirectory: true)
    }

    /// Finish the session: try to deliver it, and queue it if that fails.
    ///
    /// Queueing is not a nicety here, it is the normal path. Tailscale has no
    /// watchOS client, so the watch can only reach `wb serve` over plain WiFi —
    /// which a golf course does not have. Every round will therefore fail to
    /// upload at the time and succeed later, and without a queue that meant
    /// every round was lost.
    func upload(rateHz: Int) async {
        guard let body = encoded(rateHz: rateHz, completed: true) else { return }
        WatchSessionTransfer.shared.transferSession(
            data: body,
            sessionID: sessionID,
            mode: mode,
            roundID: WatchSessionTransfer.shared.roundContext?.roundID
        )
        if ingestURL.isEmpty {
            status = "saved · sent to WHOOP Golf on iPhone"
            return
        }
        if await deliver(body) {
            status = "uploaded to server"
        } else {
            enqueue(body)
            status = "no connection — queued, will send on WiFi"
        }
        await flushOutbox()
    }

    /// Retry anything still waiting. Called on app launch, which is the moment
    /// the watch is most likely to be somewhere with WiFi.
    func flushOutbox() async {
        guard !ingestURL.isEmpty else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.outboxDirectory, includingPropertiesForKeys: nil
        ) else { return }

        var sent = 0
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            if await deliver(data) {
                try? fm.removeItem(at: file)
                sent += 1
            } else {
                // Stop on the first failure. If the network is down, the rest
                // will fail too, and hammering it drains a Series 5 battery
                // that is already the weak point of a five-hour round.
                break
            }
        }
        if sent > 0 {
            status = sent == 1 ? "sent 1 queued round" : "sent \(sent) queued rounds"
        }
    }

    /// One delivery attempt. Returns true when the session is SETTLED — which
    /// deliberately includes a 4xx. A bad token or a malformed body will not
    /// start working on the next attempt, and retrying it every launch forever
    /// would keep a permanently undeliverable file at the head of the queue,
    /// blocking every round behind it.
    private func deliver(_ body: Data) async -> Bool {
        var endpoint = ingestURL
        if !endpoint.hasSuffix("/swings") {
            endpoint = endpoint.hasSuffix("/") ? endpoint + "swings" : endpoint + "/swings"
        }
        guard let url = URL(string: endpoint) else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !ingestToken.isEmpty {
            req.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if http.statusCode == 200 { return true }
            if (400..<500).contains(http.statusCode) {
                status = "server refused (\(http.statusCode)) — check the token"
                return true      // settled: never going to succeed
            }
            return false         // 5xx: worth another try later
        } catch {
            return false         // no network, which is the expected case
        }
    }

    private func enqueue(_ body: Data) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.outboxDirectory,
                                withIntermediateDirectories: true)
        // Seconds-resolution timestamps could collide if two sessions ended in
        // the same second; the UUID suffix makes that impossible.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(mode)-\(stamp)-\(UUID().uuidString.prefix(6)).json"
        try? body.write(to: Self.outboxDirectory.appendingPathComponent(name),
                        options: .atomic)
    }

    /// How many rounds are still waiting, for the picker to show.
    /// `nonisolated` so the mode picker can read it without an actor hop —
    /// it touches FileManager only, never this object's state.
    nonisolated static var pendingCount: Int {
        (try? FileManager.default.contentsOfDirectory(
            at: outboxDirectory, includingPropertiesForKeys: nil
        ).count) ?? 0
    }
}

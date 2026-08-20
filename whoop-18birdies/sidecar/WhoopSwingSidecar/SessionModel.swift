import Foundation
import CoreLocation
import Combine

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
    var distance_m: Double?
    var distance_yd: Double?
}

struct GeoPoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontal_accuracy: Double?
}

struct SessionLog: Codable {
    let mode: String
    let auto_threshold: Bool
    let sample_rate_hz: Int
    var swings: [Swing]
    var gps_warning: String?
    /// `whoop_ble` when motion came from strap IMU; `phone_motion` for fallback.
    var imu_source: String?
    var whoop_generation: String?
}

@MainActor
final class SessionModel: ObservableObject {
    @Published var swings: [Swing] = []
    @Published var lastPeakG: Double?
    @Published var lastTempo: Double?
    @Published var lastFrames: String?
    @Published var currentHR: Int?
    @Published var status: String = "starting…"
    @Published var running = false

    let mode: String
    var imuSource = "whoop_ble"
    var whoopGeneration: String?

    private let iso = ISO8601DateFormatter()
    private var ingestURL: String { IngestSettings.url }
    private var ingestToken: String { IngestSettings.token }

    init(mode: String) {
        self.mode = mode
        iso.timeZone = TimeZone.current
        iso.formatOptions = [.withInternetDateTime]
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
            location: location
        )
        swings.append(swing)
        lastPeakG = metrics.peakG
        lastTempo = metrics.tempoRatio
        lastFrames = metrics.tempoFrames
        autosave()
    }

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

    var measuredDistances: [Double] { swings.compactMap(\.distance_yd) }
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

    var achievedRateHz: Int = 100
    var gpsWarning: String?

    private func fileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(mode == "round" ? "swings.json" : "range_session.json")
    }

    private func encoded(rateHz: Int) -> Data? {
        let log = SessionLog(mode: mode, auto_threshold: true,
                             sample_rate_hz: rateHz, swings: swings,
                             gps_warning: gpsWarning,
                             imu_source: imuSource,
                             whoop_generation: whoopGeneration)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        return try? enc.encode(log)
    }

    func autosave(rateHz: Int = 100) {
        guard let data = encoded(rateHz: rateHz) else { return }
        try? data.write(to: fileURL(), options: .atomic)
    }

    nonisolated private static var outboxDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("outbox", isDirectory: true)
    }

    func upload(rateHz: Int) async {
        guard let body = encoded(rateHz: rateHz) else { return }
        if ingestURL.isEmpty {
            status = "saved on phone (no ingest URL set)"
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

    func flushOutbox() async {
        guard !ingestURL.isEmpty else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.outboxDirectory,
                                                      includingPropertiesForKeys: nil)
        else { return }
        var sent = 0
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            if await deliver(data) {
                try? fm.removeItem(at: file)
                sent += 1
            } else { break }
        }
        if sent > 0 {
            status = sent == 1 ? "sent 1 queued round" : "sent \(sent) queued rounds"
        }
    }

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
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func enqueue(_ body: Data) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.outboxDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(mode)-\(stamp)-\(UUID().uuidString.prefix(6)).json"
        try? body.write(to: Self.outboxDirectory.appendingPathComponent(name), options: .atomic)
    }

    nonisolated static var pendingCount: Int {
        (try? FileManager.default.contentsOfDirectory(
            at: outboxDirectory, includingPropertiesForKeys: nil
        ).count) ?? 0
    }
}

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var latest: CLLocation?
    @Published var batch: [CLLocation] = []
    @Published var lastError: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func currentPoint() -> GeoPoint? {
        guard let loc = latest, loc.horizontalAccuracy >= 0 else { return nil }
        return GeoPoint(latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        altitude: loc.altitude,
                        horizontal_accuracy: loc.horizontalAccuracy)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        Task { @MainActor in
            self.batch = locations
            self.latest = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = (error as NSError).code == CLError.denied.rawValue
                ? "location denied — no shot distances"
                : "GPS error — distances may be missing"
        }
    }
}

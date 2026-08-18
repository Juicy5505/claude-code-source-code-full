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
    let mode: String
    let auto_threshold: Bool
    let sample_rate_hz: Int
    var swings: [Swing]
}

/// Observable state the SwiftUI views bind to, plus persistence and upload.
@MainActor
final class SessionModel: ObservableObject {
    @Published var swings: [Swing] = []
    @Published var lastPeakG: Double?
    @Published var lastTempo: Double?
    @Published var lastFrames: String?
    @Published var currentHR: Int?
    @Published var status: String = "starting…"
    @Published var running = false

    let mode: String                 // "range" or "round"
    private let iso = ISO8601DateFormatter()

    /// Where to POST the finished session. Point this at your `wb serve`
    /// instance (the same host the iPhone Shortcut used), e.g.
    /// "http://192.168.1.24:8790/swings". Empty = keep on-device only.
    var ingestURL: String = ""
    var ingestToken: String = ""

    init(mode: String) {
        self.mode = mode
        // LOCAL time, deliberately. ISO8601DateFormatter defaults to UTC, and
        // the ingest server files a session under the first swing's calendar
        // date — so an evening round in the US would be stored under tomorrow
        // and silently fall out of the WHOOP join, which matches physiology on
        // the local date. Same bug class as the tee-time fix in rounds/ingest.
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

    private func encoded(rateHz: Int) -> Data? {
        let log = SessionLog(mode: mode, auto_threshold: true,
                             sample_rate_hz: rateHz, swings: swings)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
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

    /// POST the finished session to `wb serve`, if configured. Best-effort.
    func upload(rateHz: Int) async {
        guard !ingestURL.isEmpty, let url = URL(string: ingestURL),
              let body = encoded(rateHz: rateHz) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !ingestToken.isEmpty {
            req.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                status = http.statusCode == 200 ? "uploaded to server" : "upload failed (\(http.statusCode))"
            }
        } catch {
            status = "upload failed — session saved on watch"
        }
    }
}

import SwiftUI
import UIKit

@MainActor
struct SidecarSessionView: View {
    let mode: String
    let usePhoneFallback: Bool
    let onFinish: () -> Void

    @StateObject private var session: SessionModel
    @StateObject private var whoop = WhoopBLEManager()
    @StateObject private var imuMotion = IMUMotionManager()
    @StateObject private var phoneMotion = PhoneMotionManager()
    @StateObject private var location = LocationManager()
    @State private var ending = false

    init(mode: String, usePhoneFallback: Bool, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.usePhoneFallback = usePhoneFallback
        self.onFinish = onFinish
        _session = StateObject(wrappedValue: SessionModel(mode: mode))
    }

    private var useGPS: Bool { mode == "round" }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(useGPS ? "ROUND · WHOOP IMU" : "RANGE · WHOOP IMU")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text(session.lastPeakG.map { String(format: "%.1f g", $0) } ?? "—")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))

                Text(tempoLine)
                    .font(.headline)
                    .foregroundStyle(session.lastTempo != nil ? .green : .secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    stat("SWINGS", "\(session.swings.count)")
                    stat("HR", session.currentHR.map { "\($0)" } ?? "—")
                }

                Text(whoop.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(session.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !usePhoneFallback && !whoop.bonded {
                    Button("Connect WHOOP") { whoop.scanAndConnect() }
                        .buttonStyle(.borderedProminent)
                }

                Button {
                    guard !ending else { return }
                    ending = true
                    Task { await end() }
                } label: {
                    Text(ending ? "Saving…" : "Stop & Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ending ? .gray : .green)
                .disabled(ending)
            }
            .padding()
        }
        .task { await begin() }
        .onReceive(whoop.$heartRate) { hr in
            if let hr { session.currentHR = hr }
        }
        .onReceive(location.$lastError.compactMap { $0 }) { msg in
            session.status = msg
        }
    }

    private var tempoLine: String {
        if let t = session.lastTempo {
            let frames = session.lastFrames.map { " · \($0)" } ?? ""
            return String(format: "%.1f:1%@", t, frames)
        }
        return session.swings.isEmpty ? "waiting for a swing" : "no tempo (pause at address)"
    }

    private func stat(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(caption).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func begin() async {
        session.running = true
        session.imuSource = usePhoneFallback ? "phone_motion" : "whoop_ble"

        if useGPS {
            location.requestAuthorization()
            location.start()
        }

        let recordSwing: @MainActor (SwingMetrics) -> Void = { metrics in
            let point = useGPS ? location.currentPoint() : nil
            session.record(metrics, hr: session.currentHR, location: point)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        if usePhoneFallback {
            phoneMotion.onSwing = recordSwing
            phoneMotion.start()
            session.status = phoneMotion.isAvailable
                ? "phone motion fallback — shake to test in simulator"
                : "motion unavailable"
        } else {
            imuMotion.onSwing = recordSwing
            whoop.onSample = { sample in imuMotion.ingest(sample) }
            whoop.scanAndConnect()
            session.status = "connect WHOOP strap (pairing mode)"
        }
    }

    private func end() async {
        session.running = false
        if usePhoneFallback {
            phoneMotion.stop()
        } else {
            whoop.disconnect()
        }
        if useGPS {
            location.stop()
            session.computeShotDistances()
            if let longest = session.longestYards {
                session.status = String(format: "%d shots · longest %.0f yd",
                                        session.measuredDistances.count, longest)
            }
        }

        let rate = usePhoneFallback ? phoneMotion.achievedRateHz : imuMotion.achievedRateHz
        session.whoopGeneration = whoop.peripheralName
        session.achievedRateHz = rate
        session.autosave(rateHz: rate)
        await session.upload(rateHz: rate)
        onFinish()
    }
}

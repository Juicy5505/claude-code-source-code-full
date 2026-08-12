import SwiftUI
import WatchKit

/// The live dashboard during a session, and the wiring that binds the sensor
/// managers together: motion drives detection, HealthKit supplies HR, location
/// supplies GPS, and each detected swing is recorded (and haptic-cued).
struct SessionView: View {
    let mode: String

    @StateObject private var session: SessionModel
    @StateObject private var workout = WorkoutManager()
    @StateObject private var motion = MotionManager()
    @StateObject private var location = LocationManager()
    @Environment(\.dismiss) private var dismiss

    init(mode: String) {
        self.mode = mode
        _session = StateObject(wrappedValue: SessionModel(mode: mode))
    }

    private var useGPS: Bool { mode == "round" }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(useGPS ? "ROUND" : "RANGE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(session.lastPeakG.map { String(format: "%.1f g", $0) } ?? "—")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                Text(tempoLine)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(session.lastTempo != nil ? .green : .secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    tile("SWINGS", "\(session.swings.count)")
                    tile("HR", session.currentHR.map { "\($0)" } ?? "—")
                }

                if let mean = session.tempoMean {
                    Text(sessionLine(mean))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(session.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(role: .destructive) {
                    Task { await end() }
                } label: {
                    Text("Stop & Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .task { await begin() }
        .onReceive(workout.$heartRate) { hr in session.currentHR = hr }
    }

    private var tempoLine: String {
        if let t = session.lastTempo {
            let frames = session.lastFrames.map { " · \($0)" } ?? ""
            return String(format: "%.1f:1%@", t, frames)
        }
        return session.swings.isEmpty ? "waiting for a swing" : "no tempo (pause at address)"
    }

    private func sessionLine(_ mean: Double) -> String {
        let cv = session.tempoCV.map { String(format: "  cv %.2f", $0) } ?? ""
        return String(format: "session %.2f:1%@\n%@", mean, cv, TempoBench.verdict(mean))
    }

    private func tile(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(caption).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func begin() async {
        session.running = true
        session.status = "requesting access…"
        _ = await workout.requestAuthorization()
        if useGPS {
            location.requestAuthorization()
            location.start()
        }

        // Each swing: tag with the freshest HR and GPS, record, and buzz the
        // wrist so you know it registered without looking.
        motion.onSwing = { metrics in
            let point = useGPS ? location.currentPoint() : nil
            session.record(metrics, hr: workout.heartRate, location: point)
            WKInterfaceDevice.current().play(.click)
        }

        workout.start()          // background execution + live HR
        motion.start()           // 100 Hz detection
        session.status = motion.isAvailable
            ? "watching — self-calibrating"
            : "device motion unavailable on this watch"
    }

    private func end() async {
        session.running = false
        motion.stop()
        if useGPS { location.stop() }
        workout.stop()
        session.autosave()
        await session.upload(rateHz: 100)
        dismiss()
    }
}

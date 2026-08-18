import SwiftUI
import WatchKit

/// The live dashboard during a session, and the wiring that binds the sensor
/// managers together: motion drives detection, HealthKit supplies HR, location
/// supplies GPS, and each detected swing is recorded (and haptic-cued).
struct SessionView: View {
    let mode: String

    /// Called when the session has finished saving.
    ///
    /// Deliberately a callback rather than `@Environment(\.dismiss)`. This view
    /// is rendered inline at the root of a `WindowGroup`, not presented as a
    /// sheet or pushed onto a stack, so `DismissAction` has nothing to dismiss
    /// and does nothing at all. The previous version called it and left the
    /// user staring at a dead dashboard with no way back to the mode picker
    /// short of force-quitting from the side button.
    let onFinish: () -> Void

    @StateObject private var session: SessionModel
    @StateObject private var workout = WorkoutManager()
    @StateObject private var motion = MotionManager()
    @StateObject private var location = LocationManager()

    /// Guards "Stop & Save" against a second tap.
    ///
    /// Ending is not instant — it awaits HealthKit finishing the workout and
    /// then an upload. Without this, an impatient second tap ran the whole
    /// teardown again and POSTed a duplicate session. The server never
    /// overwrites, so it stored `round-<date>-2.json`, and `analyze.py` then
    /// read one round as two sessions and printed a cross-session trend built
    /// from the same round twice — a fabricated "no change" line indistinguishable
    /// from real data.
    @State private var ending = false

    init(mode: String, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.onFinish = onFinish
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
                    .foregroundStyle(session.lastTempo != nil ? Color.green : Color.secondary)
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

                Button {
                    guard !ending else { return }
                    ending = true
                    Task { await end() }
                } label: {
                    Text(ending ? "Saving…" : "Stop & Save")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                // `.bordered` is watchOS 8.0; `.borderedProminent` is watchOS
                // 9.0 and would break the documented 8.5 floor — the build
                // succeeds and then refuses to install, with an unhelpful
                // "does not support the minimum OS version".
                .buttonStyle(.bordered)
                .tint(ending ? .gray : .green)
                .disabled(ending)
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .task { await begin() }
        .onReceive(workout.$heartRate) { hr in session.currentHR = hr }
        // Forward the WHOLE batch. Core Location coalesces queued fixes into
        // one callback whenever delivery was deferred — which is what happens
        // with the wrist down — so taking only the newest threw away most of
        // the walked track before the route builder ever saw it.
        .onReceive(location.$batch) { batch in
            if useGPS && !batch.isEmpty { workout.append(locations: batch) }
        }
        .onReceive(location.$lastError.compactMap { $0 }) { message in
            session.status = message
        }
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
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func begin() async {
        session.running = true
        session.status = "requesting access…"
        let healthOK = await workout.requestAuthorization()
        if useGPS {
            location.requestAuthorization()
            location.start()
        }

        // Each swing: tag with the freshest HR and GPS, record, and buzz the
        // wrist so you know it registered without looking.
        //
        // The capture list is deliberate. Capturing the view implicitly would
        // capture `_motion`'s StateObject storage too, which strongly holds the
        // MotionManager that owns this very closure — a permanent cycle keeping
        // the whole session graph alive for the life of the process.
        motion.onSwing = { [session, workout, location, useGPS] metrics in
            let point = useGPS ? location.currentPoint() : nil
            session.record(metrics, hr: workout.heartRate, location: point)
            WKInterfaceDevice.current().play(.click)
        }

        // Route tracking only in round mode; at a range you never move.
        let started = workout.start(trackRoute: useGPS)
        motion.start()           // 100 Hz detection

        // Surfaced, not swallowed. Without a running workout session watchOS
        // suspends the app as soon as the wrist drops, so detection silently
        // stops a minute into the round — and the old code still displayed
        // "watching", so it looked fine right up until the log came back empty.
        if !motion.isAvailable {
            session.status = "device motion unavailable on this watch"
        } else if !healthOK || !started {
            session.status = "NO BACKGROUND — keep the screen on, or grant Health access"
        } else {
            session.status = "watching — self-calibrating"
        }
    }

    private func end() async {
        session.running = false
        motion.stop()
        if useGPS { location.stop() }
        // Awaited: the route is attached after the workout is saved, and
        // finishing before that completes loses the GPS track.
        await workout.stop()

        if useGPS {
            // Measure the shots. Without this the round saves a location on
            // every swing and a distance on none — the number the round was
            // tracked for, absent from the device you were wearing.
            session.computeShotDistances()
            if let longest = session.longestYards {
                session.status = String(format: "%d shots · longest %.0f yd",
                                        session.measuredDistances.count, longest)
            }
        }

        session.achievedRateHz = motion.achievedRateHz
        session.autosave(rateHz: session.achievedRateHz)
        await session.upload(rateHz: session.achievedRateHz)
        onFinish()
    }
}

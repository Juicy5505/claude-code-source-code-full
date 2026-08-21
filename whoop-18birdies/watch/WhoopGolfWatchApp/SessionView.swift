import Combine
import SwiftUI
import WatchKit

/// The live dashboard during a session, and the wiring that binds the sensor
/// managers together: motion drives detection, HealthKit supplies HR, location
/// supplies GPS, and each detected swing is recorded (and haptic-cued).
@MainActor
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
    @ObservedObject private var phoneLink = WatchSessionTransfer.shared

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

    /// Catches the watch reporting the phone's position instead of the wrist's.
    /// A Series 5 uses the paired iPhone's GPS whenever it is in range, so with
    /// the phone in the cart every shot would be measured cart-to-cart.
    @State private var gpsCheck = GPSSourceCheck()

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

                // Path · Improve · Yardage · HR/next tip — Shared stroke models.
                WatchRoundFaceView(
                    path: session.lastPath,
                    pathYawDegrees: session.lastPathYaw,
                    tempoRatio: session.lastTempo,
                    tempoFrames: session.lastFrames,
                    liveFace: phoneLink.liveFace,
                    lastWatchYards: session.swings.compactMap(\.distance_yd).last,
                    swingCount: session.swings.count,
                    heartRateBPM: session.currentHR,
                    tempoCV: session.tempoCV,
                    wrist: wrist
                )

                HStack(spacing: 12) {
                    tile("SWINGS", "\(session.swings.count)")
                    tile("TIP", tipChip)
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
                // `.bordered` (watchOS 8.0), matching the mode picker. The
                // project's floor is 9.0, so `.borderedProminent` would also
                // build — this is a legibility choice, not an availability one.
                .buttonStyle(.bordered)
                .tint(ending ? .gray : .green)
                .disabled(ending)
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .task {
            WatchSessionTransfer.shared.activate()
            await begin()
        }
        .onReceive(workout.$heartRate) { hr in session.currentHR = hr }
        // Forward the WHOLE batch. Core Location coalesces queued fixes into
        // one callback whenever delivery was deferred — which is what happens
        // with the wrist down — so taking only the newest threw away most of
        // the walked track before the route builder ever saw it.
        .onReceive(location.$batch) { batch in
            guard useGPS, !batch.isEmpty else { return }
            workout.append(locations: batch)
            if let warning = gpsCheck.update(location: batch.last,
                                             walkingFraction: motion.walkingFraction) {
                session.status = warning
                WKInterfaceDevice.current().play(.failure)
                motion.resetMovementWindow()
            }
        }
        .onReceive(location.$lastError.compactMap { $0 }) { message in
            session.status = message
        }
    }

    private var wrist: WatchWristMount { WatchWristMount.load() }

    private var tipChip: String {
        let tip = GolfImprover.tip(
            path: session.lastPath,
            tempoRatio: session.lastTempo,
            wrist: wrist,
            tempoCV: session.tempoCV,
            correctedYawDegrees: session.lastPathYaw
        )
        switch tip.focus {
        case .tempoRush: return "PAUSE"
        case .tempoSlow: return "GO"
        case .pathOutToIn: return "IN"
        case .pathInToOut: return "QUIET"
        case .pathOnPlane: return "HOLD"
        case .unknown: return "SET"
        }
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
            // Record the warning IN the session, not just on screen. A round
            // whose yardages are really cart-to-cart must not read as a clean
            // round three weeks later when nobody remembers the watch face.
            session.gpsWarning = gpsCheck.warning
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

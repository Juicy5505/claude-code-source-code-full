import Foundation
import CoreMotion

/// Reads device motion at ~100 Hz and runs the swing detector.
///
/// Uses `startDeviceMotionUpdates` (not raw accelerometer) so gravity is already
/// removed — `userAcceleration` matches the g-magnitude the Python reference
/// expects — and attitude is available for the rotation sweep. Series 5 tops out
/// around 100 Hz for device motion, which is exactly the reference rate.
///
/// The detector's trip/post-peak/refractory state machine mirrors
/// swing_logger.run_session: the threshold trips on the rising edge, then a
/// short post-peak window is captured before the true impact peak is located at
/// or after the trip time.
@MainActor
final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()

    /// Serial, deliberately. A default OperationQueue is concurrent, so motion
    /// callbacks can land on several threads at once and reach `ingest` out of
    /// order. The buffer is walked backwards in time by `findMotionStart`, so
    /// out-of-order samples do not merely add noise — they corrupt the tempo
    /// maths, which is exactly the reading that has been unreliable before.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "com.whoopgolf.motion"
        return q
    }()

    private let targetHz = 100.0
    private let bufferSeconds = 2.5
    private let postPeakSeconds = 0.4
    private let refractorySeconds = 3.0

    private let detector = AdaptiveThreshold()
    private var buffer: [MotionSample] = []
    private var bufferMax: Int { max(16, Int(bufferSeconds * targetHz)) }

    private var lastDetection = 0.0
    private var tripTime: TimeInterval?

    /// Samples actually delivered, and when counting began — so the session
    /// records the rate it ACHIEVED rather than the rate it asked for. A run
    /// that managed 60 Hz should not be filed as a clean 100, because the
    /// tempo derived from it is correspondingly coarser.
    private var sampleCount = 0
    private var firstSampleTime: TimeInterval?
    private var lastSampleTime: TimeInterval?

    /// Rolling evidence that the wearer is on the move.
    ///
    /// Used to catch the watch reporting somebody else's position. On a Series
    /// 5 — and every model before the Series 8 — watchOS uses the PAIRED
    /// IPHONE'S GPS whenever the phone is in range, to save the watch's much
    /// smaller battery. With the phone sitting in a golf cart thirty yards
    /// away, that means every shot gets tagged at the cart rather than at the
    /// ball, and nothing anywhere reports it.
    ///
    /// There is no API to force the watch's own receiver, and no field on a fix
    /// that says which radio produced it. But the disagreement is detectable:
    /// if the wrist has been moving like a walk for a minute and the reported
    /// position has barely changed, the position is not coming from the wrist.
    private var movementSamples = 0
    private var walkingSamples = 0

    /// Fraction of recent samples that look like walking rather than standing.
    var walkingFraction: Double {
        guard movementSamples > 0 else { return 0 }
        return Double(walkingSamples) / Double(movementSamples)
    }

    func resetMovementWindow() {
        movementSamples = 0
        walkingSamples = 0
    }

    var achievedRateHz: Int {
        guard let first = firstSampleTime, let last = lastSampleTime,
              last > first, sampleCount > 1
        else { return Int(targetHz) }
        return Int((Double(sampleCount - 1) / (last - first)).rounded())
    }

    /// Called on the main actor for each detected swing, with the analysed
    /// window and the sample index within it that is the impact peak.
    var onSwing: (@MainActor (SwingMetrics) -> Void)?

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        buffer.removeAll(keepingCapacity: true)
        buffer.reserveCapacity(bufferMax + 8)
        motion.deviceMotionUpdateInterval = 1.0 / targetHz
        // `@Sendable` is load-bearing, not decoration. Without it the closure
        // literal inherits this method's main-actor isolation and is then
        // converted to CMDeviceMotionHandler, which is not isolated — the
        // isolation is silently erased. Core Motion calls it on `queue`
        // regardless, so the annotation just makes the truth checkable.
        motion.startDeviceMotionUpdates(to: queue) { @Sendable [weak self] data, _ in
            guard let self, let data else { return }
            let now = data.timestamp   // monotonic seconds since boot
            let a = data.userAcceleration
            let mag = SwingAnalysis.magnitude(x: a.x, y: a.y, z: a.z)
            let att = data.attitude
            let sample = MotionSample(t: now, mag: mag,
                                      attitude: (att.roll, att.pitch, att.yaw))
            // Hop to the main actor to mutate detector state and publish.
            Task { @MainActor in self.ingest(sample) }
        }
    }

    private func ingest(_ sample: MotionSample) {
        movementSamples += 1
        // Walking swings the arm; standing over a ball does not. 0.12 g sits
        // above the noise floor of a still wrist and well below a swing, so it
        // reads gait without counting the shot itself.
        if sample.mag > 0.12 { walkingSamples += 1 }

        sampleCount += 1
        if firstSampleTime == nil { firstSampleTime = sample.t }
        lastSampleTime = sample.t

        buffer.append(sample)
        if buffer.count > bufferMax { buffer.removeFirst(buffer.count - bufferMax) }
        detector.observe(sample.mag)

        let now = sample.t
        if tripTime == nil {
            if detector.isSwing(sample.mag) && (now - lastDetection) >= refractorySeconds {
                tripTime = now
            }
        } else if let trip = tripTime, now - trip >= postPeakSeconds {
            resolve(tripTime: trip)
            lastDetection = now
            tripTime = nil
        }
    }

    private func resolve(tripTime: TimeInterval) {
        // Peak located at or after the trip, so a prior follow-through lingering
        // in the buffer cannot be mistaken for this swing's impact.
        let candidates = buffer.indices.filter { buffer[$0].t >= tripTime }
        guard let peak = candidates.max(by: { buffer[$0].mag < buffer[$1].mag }) else { return }
        let metrics = SwingAnalysis.analyse(buffer, peak: peak)
        onSwing?(metrics)
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        // Release the closure. It captures the session graph, and leaving it
        // set keeps every manager alive for the life of the process.
        onSwing = nil
    }
}

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
    private let queue = OperationQueue()

    private let targetHz = 100.0
    private let bufferSeconds = 2.5
    private let postPeakSeconds = 0.4
    private let refractorySeconds = 3.0

    private let detector = AdaptiveThreshold()
    private var buffer: [MotionSample] = []
    private var bufferMax: Int { max(16, Int(bufferSeconds * targetHz)) }

    private var lastDetection = 0.0
    private var tripTime: TimeInterval?

    /// Called on the main actor for each detected swing, with the analysed
    /// window and the sample index within it that is the impact peak.
    var onSwing: ((SwingMetrics) -> Void)?

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        buffer.removeAll(keepingCapacity: true)
        buffer.reserveCapacity(bufferMax + 8)
        motion.deviceMotionUpdateInterval = 1.0 / targetHz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
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
    }
}

import CoreMotion
import Foundation

/// Fallback motion source for the simulator or when WHOOP BLE is unavailable.
@MainActor
final class PhoneMotionManager: ObservableObject {
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "com.whoopgolf.sidecar.motion"
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
    private var sampleCount = 0
    private var firstSampleTime: TimeInterval?
    private var lastSampleTime: TimeInterval?

    var onSwing: (@MainActor (SwingMetrics) -> Void)?
    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    var achievedRateHz: Int {
        guard let first = firstSampleTime, let last = lastSampleTime,
              last > first, sampleCount > 1
        else { return Int(targetHz) }
        return Int((Double(sampleCount - 1) / (last - first)).rounded())
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        buffer.removeAll(keepingCapacity: true)
        motion.deviceMotionUpdateInterval = 1.0 / targetHz
        motion.startDeviceMotionUpdates(to: queue) { @Sendable [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let mag = SwingAnalysis.magnitude(x: a.x, y: a.y, z: a.z)
            let att = data.attitude
            let sample = MotionSample(t: data.timestamp, mag: mag,
                                      attitude: (att.roll, att.pitch, att.yaw))
            Task { @MainActor in self.ingest(sample) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        onSwing = nil
    }

    private func ingest(_ sample: MotionSample) {
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
        let candidates = buffer.indices.filter { buffer[$0].t >= tripTime }
        guard let peak = candidates.max(by: { buffer[$0].mag < buffer[$1].mag }) else { return }
        onSwing?(SwingAnalysis.analyse(buffer, peak: peak))
    }
}

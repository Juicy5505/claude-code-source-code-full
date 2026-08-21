import Foundation

/// Runs swing detection on WHOOP IMU magnitudes (~100 Hz batches).
@MainActor
final class IMUMotionManager: ObservableObject {
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

    var achievedRateHz: Int {
        guard let first = firstSampleTime, let last = lastSampleTime,
              last > first, sampleCount > 1
        else { return Int(targetHz) }
        return Int((Double(sampleCount - 1) / (last - first)).rounded())
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastDetection = 0
        tripTime = nil
        sampleCount = 0
        firstSampleTime = nil
        lastSampleTime = nil
    }

    func ingest(_ sample: WhoopIMUDecoder.Sample) {
        let motion = MotionSample(t: sample.timestamp, mag: sample.magnitudeG, attitude: nil)
        sampleCount += 1
        if firstSampleTime == nil { firstSampleTime = motion.t }
        lastSampleTime = motion.t

        buffer.append(motion)
        if buffer.count > bufferMax { buffer.removeFirst(buffer.count - bufferMax) }
        detector.observe(motion.mag)

        let now = motion.t
        if tripTime == nil {
            if detector.isSwing(motion.mag) && (now - lastDetection) >= refractorySeconds {
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
        let metrics = SwingAnalysis.analyse(buffer, peak: peak)
        onSwing?(metrics)
    }
}

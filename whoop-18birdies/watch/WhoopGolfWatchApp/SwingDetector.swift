import Foundation

// A faithful Swift port of the tested Python reference in
// whoop-18birdies/iphone/swing_metrics.py. The Python is the source of truth —
// its 93 tests cover the detection and tempo maths. Keep the two in sync: any
// change to the algorithm belongs in the Python first (where it is tested),
// then mirrored here.

/// One motion sample: time in seconds, user-acceleration magnitude in g, and
/// optional device attitude (roll/pitch/yaw radians).
struct MotionSample {
    let t: TimeInterval
    let mag: Double
    let attitude: (roll: Double, pitch: Double, yaw: Double)?
}

/// Mechanics derived from the window around a detected impact.
struct SwingMetrics {
    var peakG: Double
    var backswingS: Double?
    var downswingS: Double?
    var tempoRatio: Double?
    var tempoFrames: String?
    var yawSweepDeg: Double?
}

enum TempoBench {
    static let tour = 3.0
    static let fps = 30.0

    /// A swing's phases in Tour Tempo's 30 fps frame units, e.g. "24/8".
    static func frames(_ backswingS: Double?, _ downswingS: Double?) -> String? {
        guard let b = backswingS, let d = downswingS else { return nil }
        return "\(Int((b * fps).rounded()))/\(Int((d * fps).rounded()))"
    }

    static func verdict(_ ratio: Double?) -> String {
        guard let r = ratio, r.isFinite else { return "no reading" }
        if r < tour - 0.6 { return "quick backswing — rushing the takeaway" }
        if r > tour + 0.6 { return "slow backswing relative to your downswing" }
        return "near the 3:1 tour benchmark"
    }
}

/// A swing threshold that calibrates itself from the wearer's own recent motion.
/// Mirrors AdaptiveThreshold in swing_metrics.py, including the cached median
/// (recomputed periodically, not per sample) that made the Python 21x cheaper.
final class AdaptiveThreshold {
    private let ratio: Double
    private let floorG: Double
    private let maxSamples: Int
    private let recomputeEvery: Int
    private var window: [Double] = []
    private var cachedMedian: Double?
    private var sinceRecompute = 0

    init(windowSeconds: Double = 10, ratio: Double = 2.0, floorG: Double = 1.5,
         sampleHz: Double = 100, recomputeEvery: Int = 25) {
        self.ratio = ratio
        self.floorG = floorG
        self.maxSamples = max(32, Int(windowSeconds * sampleHz))
        self.recomputeEvery = max(1, recomputeEvery)
        window.reserveCapacity(self.maxSamples + 1)
    }

    func observe(_ mag: Double) {
        window.append(mag)
        if window.count > maxSamples {
            window.removeFirst(window.count - maxSamples)
        }
        sinceRecompute += 1
        if cachedMedian == nil || sinceRecompute >= recomputeEvery {
            cachedMedian = computeMedian()
            sinceRecompute = 0
        }
    }

    private func computeMedian() -> Double? {
        guard !window.isEmpty else { return nil }
        let sorted = window.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    func baseline() -> Double? {
        if cachedMedian == nil { cachedMedian = computeMedian() }
        return cachedMedian
    }

    /// Enough history for the baseline to mean anything.
    var isReady: Bool { window.count >= maxSamples / 4 }

    func threshold() -> Double {
        guard let base = baseline() else { return floorG }
        // The floor stops perfect stillness from making everything a swing.
        return max(floorG, base * ratio)
    }

    func isSwing(_ mag: Double) -> Bool { isReady && mag >= threshold() }
}

enum SwingAnalysis {
    static let quietG = 0.35
    static let maxBackswingS = 2.0
    static let quietRunS = 0.15

    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// First sample of the backswing, walking back from impact. Returns nil when
    /// no sustained address stillness exists — the load-bearing case: a swing
    /// straight out of walking has no quiet lead-in, and fabricating a start
    /// inside that motion produces a nonsense tempo. Honest nil keeps it out.
    static func findMotionStart(_ s: [MotionSample], peak: Int) -> Int? {
        if peak <= 0 { return nil }
        let tPeak = s[peak].t
        var quietRun = 0
        var i = peak
        while i > 0 {
            i -= 1
            let t = s[i].t
            let mag = s[i].mag
            if tPeak - t > maxBackswingS { return nil }
            if mag < quietG {
                quietRun += 1
                let runStartT = s[i + quietRun - 1].t
                if runStartT - t >= quietRunS { return i + quietRun }
            } else {
                quietRun = 0
            }
        }
        return nil
    }

    /// Top of the backswing: quietest moment between motion start and impact.
    static func findTransition(_ s: [MotionSample], peak: Int, start: Int) -> Int? {
        if peak <= 0 || start >= peak { return nil }
        let window = start..<peak
        if window.count < 3 { return nil }
        var best = start
        for i in window where s[i].mag < s[best].mag { best = i }
        return best
    }

    static func yawSweep(_ s: [MotionSample], _ start: Int, _ end: Int) -> Double? {
        var yaws: [Double] = []
        for i in start...min(end, s.count - 1) {
            if let a = s[i].attitude { yaws.append(a.yaw) }
        }
        guard let lo = yaws.min(), let hi = yaws.max() else { return nil }
        return ((hi - lo) * 180 / .pi * 10).rounded() / 10
    }

    /// Derives mechanics from a motion window. Fields that need phases the window
    /// does not contain come back nil rather than guessed.
    static func analyse(_ samples: [MotionSample], peak peakIndex: Int) -> SwingMetrics {
        var m = SwingMetrics(peakG: (samples[peakIndex].mag * 100).rounded() / 100,
                             backswingS: nil, downswingS: nil,
                             tempoRatio: nil, tempoFrames: nil, yawSweepDeg: nil)

        guard let start = findMotionStart(samples, peak: peakIndex),
              let transition = findTransition(samples, peak: peakIndex, start: start)
        else { return m }

        let backswing = samples[transition].t - samples[start].t
        let downswing = samples[peakIndex].t - samples[transition].t
        m.backswingS = (backswing * 1000).rounded() / 1000
        m.downswingS = (downswing * 1000).rounded() / 1000
        if downswing > 0.01 && backswing > 0.01 {
            m.tempoRatio = ((backswing / downswing) * 100).rounded() / 100
        }
        m.tempoFrames = TempoBench.frames(m.backswingS, m.downswingS)
        m.yawSweepDeg = yawSweep(samples, start, peakIndex)
        return m
    }
}

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
    /// Mount-corrected downswing yaw in degrees. Positive is in-to-out.
    var pathYawDeg: Double?
    var pathClass: SwingPathClass
}

enum TempoBench {
    static let tour = 3.0
    static let fps = 30.0

    /// A swing's phases in Tour Tempo's 30 fps frame units, e.g. "24/8".
    ///
    /// Rounds half-to-even, matching Python's `"{:.0f}".format`. Swift's plain
    /// `.rounded()` rounds half-away-from-zero, and the difference is not
    /// academic here: a 0.75 s backswing sits dead centre of the elite
    /// 0.7-0.9 s range and 0.75 x 30 is exactly 22.5 frames — "22" on the
    /// phone, "23" on the watch, for the same swing.
    static func frames(_ backswingS: Double?, _ downswingS: Double?) -> String? {
        guard let b = backswingS, let d = downswingS else { return nil }
        let back = Int((b * fps).rounded(.toNearestOrEven))
        let down = Int((d * fps).rounded(.toNearestOrEven))
        return "\(back)/\(down)"
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

    /// Rounds to `places` decimals half-to-even, matching Python's `round()`.
    ///
    /// Every rounded value this file produces is compared against the Python
    /// reference by `SwingDetectorTests`, so the tie-breaking rule has to be the
    /// same one. Swift's bare `.rounded()` is half-away-from-zero and silently
    /// disagrees on exact halves.
    static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded(.toNearestOrEven) / scale
    }

    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// First sample of the backswing, walking back from impact. Returns nil when
    /// no sustained address stillness exists — the load-bearing case: a swing
    /// straight out of walking has no quiet lead-in, and fabricating a start
    /// inside that motion produces a nonsense tempo. Honest nil keeps it out.
    static func findMotionStart(_ s: [MotionSample], peak: Int) -> Int? {
        // Both ends. The lower bound was already here; without the upper one
        // `s[peak]` on the next line is a fatal "Index out of range", which on
        // a watch means the app dies mid-round and the round is gone.
        if peak <= 0 || peak >= s.count { return nil }
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

    /// Undo the +/-pi wrap in an angle sequence.
    ///
    /// Core Motion reports yaw in (-pi, pi], so a body turn crossing pi jumps
    /// straight to -pi. Taking max-min across the raw values reads that 0.02 rad
    /// step as 6.26 rad, and a measured 45-degree shoulder turn comes back as
    /// 359 degrees — which looks like a complete rotation rather than an obvious
    /// error. Which swings it strikes depends only on the compass direction you
    /// are aimed at, so it appears and disappears for no visible reason.
    static func unwrap(_ values: [Double]) -> [Double] {
        guard let first = values.first else { return [] }
        var out = [first]
        var offset = 0.0
        for (previous, current) in zip(values, values.dropFirst()) {
            let delta = current - previous
            if delta > .pi {
                offset -= 2 * .pi
            } else if delta < -.pi {
                offset += 2 * .pi
            }
            out.append(current + offset)
        }
        return out
    }

    static func yawSweep(_ s: [MotionSample], _ start: Int, _ end: Int) -> Double? {
        guard start <= min(end, s.count - 1) else { return nil }
        var yaws: [Double] = []
        for i in start...min(end, s.count - 1) {
            if let a = s[i].attitude { yaws.append(a.yaw) }
        }
        let unwrapped = unwrap(yaws)
        guard let lo = unwrapped.min(), let hi = unwrapped.max() else { return nil }
        return round((hi - lo) * 180 / .pi, 1)
    }

    /// Derives mechanics from a motion window. Fields that need phases the window
    /// does not contain come back nil rather than guessed.
    static func analyse(_ samples: [MotionSample], peak peakIndex: Int) -> SwingMetrics {
        // Named rather than bare. `samples[peakIndex]` on an out-of-range index
        // traps with "Index out of range" and nothing about which caller or
        // which window — on a watch that is a crash report with no lead.
        //
        // A trap and not a fallback: the Python reference raises here too (see
        // analyse_swing in iphone/swing_metrics.py), and there is no honest
        // SwingMetrics to return for a peak that is not in the window. Inventing
        // one would put a fabricated swing into the round.
        precondition(
            samples.indices.contains(peakIndex),
            "analyse: peak \(peakIndex) is outside the \(samples.count) sample(s) given"
        )
        var m = SwingMetrics(peakG: round(samples[peakIndex].mag, 2),
                             backswingS: nil, downswingS: nil,
                             tempoRatio: nil, tempoFrames: nil, yawSweepDeg: nil,
                             pathYawDeg: nil, pathClass: .unknown)

        guard let start = findMotionStart(samples, peak: peakIndex),
              let transition = findTransition(samples, peak: peakIndex, start: start)
        else { return m }

        let backswing = samples[transition].t - samples[start].t
        let downswing = samples[peakIndex].t - samples[transition].t
        m.backswingS = round(backswing, 3)
        m.downswingS = round(downswing, 3)
        if downswing > 0.01 && backswing > 0.01 {
            m.tempoRatio = round(backswing / downswing, 2)
        }
        m.tempoFrames = TempoBench.frames(m.backswingS, m.downswingS)
        m.yawSweepDeg = yawSweep(samples, start, peakIndex)
        let rawPathYaw = signedYawDelta(samples, from: transition, to: peakIndex)
        let classified = SwingPathGuidance.classify(
            downswingYawDegrees: rawPathYaw,
            wrist: WatchWristMount.load()
        )
        m.pathClass = classified.path
        m.pathYawDeg = classified.correctedYawDegrees
        return m
    }

    /// Signed yaw change from the top of the backswing to impact, unwrapped.
    /// Wrist mount polarity is applied later by `SwingPathGuidance`.
    static func signedYawDelta(_ s: [MotionSample], from: Int, to: Int) -> Double? {
        guard from <= to, to < s.count else { return nil }
        var yaws: [Double] = []
        for i in from...to {
            if let a = s[i].attitude { yaws.append(a.yaw) }
        }
        let unwrapped = unwrap(yaws)
        guard let first = unwrapped.first, let last = unwrapped.last else { return nil }
        return round((last - first) * 180 / .pi, 1)
    }
}

import Foundation

/// Plausible city/highway drive used when no adapter is connected, so the UI
/// is fully explorable on the couch and in the CarPlay Simulator.
final class DriveSimulator {
    private var targetMph: Double = 0
    private var phaseRemaining: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    private let phases: [(mph: Double, seconds: TimeInterval)] = [
        (0, 5), (27, 10), (44, 12), (66, 18), (74, 15), (33, 8),
    ]
    private let upshiftMph: [Double] = [0, 12, 21, 33, 47, 62, 999]

    func step(dt: TimeInterval, store: VehicleDataStore) {
        elapsed += dt
        phaseRemaining -= dt
        if phaseRemaining <= 0 {
            let phase = phases.randomElement()!
            targetMph = max(0, phase.mph + Double.random(in: -3...3))
            phaseRemaining = phase.seconds
        }

        let diff = targetMph - store.speedMph
        let rate: Double = diff > 0 ? 6.5 : 11        // accelerate gently, brake harder
        store.speedMph = max(0, min(160, store.speedMph + max(-rate * dt, min(rate * dt, diff))))

        var g = 1
        while g < 6 && store.speedMph > upshiftMph[g] { g += 1 }
        store.gear = store.speedMph < 0.5 ? "P" : "D\(g)"

        let idle: Double = 750
        if store.speedMph < 0.5 {
            store.rpm = idle + sin(elapsed * 2) * 30
        } else {
            let lo = upshiftMph[g - 1], hi = upshiftMph[g]
            let inGear = (store.speedMph - lo) / max(hi - lo, 1)
            store.rpm = min(6500, max(idle, idle + inGear * 2400 + store.speedMph * 14))
        }

        store.coolantF += (198 - store.coolantF) * dt * 0.02
        store.batteryVolts = 14.1 + sin(elapsed * 0.5) * 0.12 - (store.speedMph < 0.5 ? 0.9 : 0)
        store.fuelPercent = max(3, store.fuelPercent -
            (store.speedMph / store.milesPerGallon) * dt / 3600 / store.tankGallons * 100)
    }
}

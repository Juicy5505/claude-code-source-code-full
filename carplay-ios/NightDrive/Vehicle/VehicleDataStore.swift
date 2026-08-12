import Foundation
import Combine

/// Canonical live vehicle state shared by the phone UI and the CarPlay scene.
/// Speed is stored in mph, temperature in °F; formatting converts per the
/// selected units.
final class VehicleDataStore: ObservableObject {
    static let shared = VehicleDataStore()

    enum Source: String, CaseIterable, Identifiable {
        case demo = "Demo"
        case obd = "OBD-II"
        var id: String { rawValue }
    }

    enum Units: String, CaseIterable, Identifiable {
        case imperial = "mph · °F"
        case metric = "km/h · °C"
        var id: String { rawValue }
    }

    // MARK: Live metrics
    @Published var speedMph: Double = 0
    @Published var rpm: Double = 0
    @Published var fuelPercent: Double = 62
    @Published var coolantF: Double = 120
    @Published var batteryVolts: Double = 12.4
    @Published var gear: String = "P"

    // MARK: Persistent counters
    @Published var tripMiles: Double {
        didSet { UserDefaults.standard.set(tripMiles, forKey: "tripMiles") }
    }
    @Published var odometerMiles: Double {
        didSet { UserDefaults.standard.set(odometerMiles, forKey: "odometerMiles") }
    }

    // MARK: Configuration
    @Published var units: Units {
        didSet { UserDefaults.standard.set(units.rawValue, forKey: "units") }
    }
    @Published var source: Source = .demo {
        didSet { sourceChanged() }
    }
    @Published var obdStatus: String = "Not connected"
    @Published var obdConnected: Bool = false

    /// Estimated tank size and economy used for the range readout.
    let tankGallons: Double = 14.5
    let milesPerGallon: Double = 29

    var rangeMiles: Double { fuelPercent / 100 * tankGallons * milesPerGallon }

    private let simulator = DriveSimulator()
    private lazy var obd = OBDManager(store: self)
    private var timer: AnyCancellable?
    private var lastTick = Date()

    private init() {
        tripMiles = UserDefaults.standard.double(forKey: "tripMiles")
        let odo = UserDefaults.standard.double(forKey: "odometerMiles")
        odometerMiles = odo == 0 ? 48_213.4 : odo
        units = Units(rawValue: UserDefaults.standard.string(forKey: "units") ?? "") ?? .imperial

        timer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.tick(now: now) }
    }

    private func tick(now: Date) {
        let dt = min(0.5, now.timeIntervalSince(lastTick))
        lastTick = now
        if source == .demo {
            simulator.step(dt: dt, store: self)
        }
        // Trip/odometer accrue from whichever source is live.
        let miles = speedMph * dt / 3600
        tripMiles += miles
        odometerMiles += miles
    }

    private func sourceChanged() {
        switch source {
        case .demo:
            obdStatus = "Not connected"
        case .obd:
            obd.connect()
        }
    }

    func resetTrip() { tripMiles = 0 }

    // MARK: Formatting

    func formattedSpeed() -> (value: String, unit: String) {
        switch units {
        case .imperial: return (String(Int(speedMph.rounded())), "mph")
        case .metric: return (String(Int((speedMph * 1.60934).rounded())), "km/h")
        }
    }

    func formattedDistance(_ miles: Double, decimals: Int = 1) -> String {
        let v = units == .metric ? miles * 1.60934 : miles
        let u = units == .metric ? "km" : "mi"
        return String(format: "%.\(decimals)f %@", v, u)
    }

    func formattedTemp(_ fahrenheit: Double) -> String {
        switch units {
        case .imperial: return String(format: "%.0f °F", fahrenheit)
        case .metric: return String(format: "%.0f °C", (fahrenheit - 32) * 5 / 9)
        }
    }
}

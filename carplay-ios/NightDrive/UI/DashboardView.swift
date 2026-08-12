import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: VehicleDataStore

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ScrollView {
                VStack(spacing: 14) {
                    if landscape {
                        HStack(spacing: 14) { speedGauge; rpmGauge }
                    } else {
                        speedGauge
                        rpmGauge
                    }
                    tiles
                }
                .padding(14)
            }
        }
        .background(Theme.ground)
    }

    private var speedGauge: some View {
        let speed = store.formattedSpeed()
        let maxSpeed: Double = store.units == .metric ? 240 : 160
        let displayed = store.units == .metric ? store.speedMph * 1.60934 : store.speedMph
        return GaugeView(value: displayed, maxValue: maxSpeed,
                         tick: store.units == .metric ? 30 : 20,
                         centerText: speed.value, unitText: speed.unit,
                         subText: "GEAR \(store.gear)")
            .panelStyle()
    }

    private var rpmGauge: some View {
        GaugeView(value: store.rpm, maxValue: 7000, tick: 1000,
                  centerText: String(format: "%.1f", store.rpm / 1000),
                  unitText: "rpm ×1000", redlineFrom: 5800, tickDivisor: 1000)
            .panelStyle()
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricTile(label: "Fuel",
                       value: String(format: "%.0f%%", store.fuelPercent),
                       detail: store.formattedDistance(store.rangeMiles, decimals: 0) + " range",
                       fraction: store.fuelPercent / 100,
                       severity: store.fuelPercent < 10 ? .crit : store.fuelPercent < 20 ? .warn : .normal)
            MetricTile(label: "Coolant",
                       value: store.formattedTemp(store.coolantF),
                       detail: nil,
                       fraction: min(1, max(0, (store.coolantF - 100) / 160)),
                       severity: store.coolantF > 240 ? .crit : store.coolantF > 225 ? .warn : .normal)
            MetricTile(label: "Battery",
                       value: String(format: "%.1f V", store.batteryVolts),
                       detail: nil,
                       fraction: min(1, max(0, (store.batteryVolts - 10) / 5)),
                       severity: store.batteryVolts < 11.8 ? .crit : store.batteryVolts < 12.2 ? .warn : .normal)
            MetricTile(label: "Trip",
                       value: store.formattedDistance(store.tripMiles),
                       detail: "Odometer " + store.formattedDistance(store.odometerMiles, decimals: 0),
                       fraction: nil, severity: .normal)
        }
    }
}

enum TileSeverity { case normal, warn, crit }

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String?
    let fraction: Double?
    let severity: TileSeverity

    private var tint: Color {
        switch severity {
        case .normal: return Theme.accent
        case .warn: return Theme.warn
        case .crit: return Theme.crit
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(severity == .normal ? Theme.muted : tint)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(severity == .normal ? Theme.text : tint)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ground)
                        Capsule().fill(tint)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
    }
}

extension View {
    func panelStyle() -> some View {
        self.padding(8)
            .frame(maxWidth: .infinity)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline))
    }
}

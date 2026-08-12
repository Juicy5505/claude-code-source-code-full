import SwiftUI

/// 270°-sweep analog dial with a digital center readout, matching the web
/// dashboard's design language.
struct GaugeView: View {
    let value: Double
    let maxValue: Double
    let tick: Double
    let centerText: String
    let unitText: String
    var subText: String? = nil
    var redlineFrom: Double? = nil
    var tickDivisor: Double = 1     // e.g. 1000 to label RPM as 0–7

    private let startAngle = 0.75 * Double.pi
    private let sweep = 1.5 * Double.pi

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size * 0.42
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let fraction = min(1, max(0, value / maxValue))
            let over = redlineFrom.map { value >= $0 } ?? false

            ZStack {
                dialArc(from: 0, to: 1, color: Theme.hairline)
                if let red = redlineFrom {
                    dialArc(from: red / maxValue, to: 1, color: Theme.crit.opacity(0.35))
                }
                dialArc(from: 0, to: fraction, color: over ? Theme.crit : Theme.accent)

                ticksAndLabels(center: center, radius: radius)

                needle(center: center, radius: radius, fraction: fraction,
                       color: over ? Theme.crit : Theme.text)

                VStack(spacing: size * 0.01) {
                    Text(centerText)
                        .font(.system(size: radius * 0.55, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.crit : Theme.text)
                    Text(unitText.uppercased())
                        .font(.system(size: radius * 0.11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.muted)
                    if let subText {
                        Text(subText)
                            .font(.system(size: radius * 0.10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .offset(y: size * 0.02)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func angle(forFraction f: Double) -> Angle {
        .radians(startAngle + sweep * f)
    }

    private func dialArc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat((to - from) * 0.75))
            .rotation(angle(forFraction: from))
            .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .padding(14)
    }

    private func ticksAndLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(stride(from: 0.0, through: maxValue, by: tick)), id: \.self) { v in
            let a = startAngle + sweep * (v / maxValue)
            let labelPos = CGPoint(x: center.x + cos(a) * radius * 0.68,
                                   y: center.y + sin(a) * radius * 0.68)
            Text(String(Int(v / tickDivisor)))
                .font(.system(size: radius * 0.115, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .position(labelPos)
        }
    }

    private func needle(center: CGPoint, radius: CGFloat, fraction: Double, color: Color) -> some View {
        let a = startAngle + sweep * fraction
        return Path { p in
            p.move(to: CGPoint(x: center.x + cos(a) * radius * 0.30,
                               y: center.y + sin(a) * radius * 0.30))
            p.addLine(to: CGPoint(x: center.x + cos(a) * radius * 0.78,
                                  y: center.y + sin(a) * radius * 0.78))
        }
        .stroke(color, style: StrokeStyle(lineWidth: max(3, radius * 0.03), lineCap: .round))
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

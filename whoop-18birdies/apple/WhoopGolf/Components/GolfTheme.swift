import SwiftUI

extension Color {
    static let golfInk = Color(red: 0.035, green: 0.055, blue: 0.050)
    static let golfPine = Color(red: 0.055, green: 0.145, blue: 0.115)
    static let golfLime = Color(red: 0.706, green: 0.898, blue: 0.494)
    static let golfSand = Color(red: 0.875, green: 0.796, blue: 0.655)
    static let golfMist = Color(red: 0.650, green: 0.720, blue: 0.690)
}

struct GolfBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.golfPine.opacity(0.9), .golfInk, .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GolfCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.075))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                    )
            )
    }
}

struct SourceBadge: View {
    let provenance: DataProvenance

    var body: some View {
        Label(provenance.source.title, systemImage: provenance.source.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(provenance.source == .demo ? Color.golfSand : Color.golfLime)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.28), in: Capsule())
            .accessibilityLabel("Source: (provenance.source.title), quality (provenance.quality.rawValue)")
    }
}

struct ConnectionPill: View {
    let title: String
    let systemImage: String
    let active: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? Color.golfLime : Color.golfMist)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(active ? 0.10 : 0.055), in: Capsule())
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(Color.golfLime)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.golfMist)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(15)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}


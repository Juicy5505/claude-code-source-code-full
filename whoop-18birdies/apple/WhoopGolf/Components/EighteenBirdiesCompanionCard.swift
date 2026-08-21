import SwiftUI

struct EighteenBirdiesCompanionCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        GolfCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("18Birdies companion", systemImage: "arrow.up.forward.app.fill")
                        .font(.headline)
                    Spacer()
                    Text("INDEPENDENT")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.golfLime)
                }
                Text("Open 18Birdies beside this round for its course maps, rangefinder, scoring, and account features.")
                    .font(.subheadline.weight(.semibold))
                Text("WHOOP 5 has no GPS. This independent companion uses mobile GPS only if enabled. No scores, shots, location, login, or account data sync between the apps.")
                    .font(.caption)
                    .foregroundStyle(Color.golfMist)
                Button(action: openCompanion) {
                    Label("Open 18Birdies", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .tint(.golfLime)
                .foregroundStyle(Color.golfInk)
                .accessibilityHint("Leaves WHOOP Golf and opens the independent 18Birdies app or website")
                Text("Official universal-link handoff · App Store fallback if iOS cannot open it.")
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }
        }
    }

    private func openCompanion() {
        openURL(EighteenBirdiesCompanionLink.primaryURL) { primaryAccepted in
            guard let fallbackURL = EighteenBirdiesCompanionLink.fallbackURL(
                afterPrimaryAccepted: primaryAccepted
            ) else { return }
            openURL(fallbackURL)
        }
    }
}

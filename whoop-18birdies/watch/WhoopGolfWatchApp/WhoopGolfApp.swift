import SwiftUI

// WHOOP + Golf, on the watch. The Apple Watch is the swing sensor (motion,
// tempo, GPS shot distance, live heart rate); WHOOP remains the physiology
// side (recovery / sleep / strain / readiness) via the TypeScript toolkit.
// Together they cover both halves — how you swung, and whether your body was
// ready — with nothing in your hands during the round.
//
// This is an independent watchOS app: it needs no iOS companion to run. Build
// and install it from Xcode on a Mac (see whoop-18birdies/watch/WATCH.md).

@main
struct WhoopGolfApp: App {
    var body: some Scene {
        WindowGroup {
            ModePicker()
        }
    }
}

struct ModePicker: View {
    @State private var mode: String?

    var body: some View {
        if let mode {
            SessionView(mode: mode)
        } else {
            VStack(spacing: 10) {
                Text("Swing Logger")
                    .font(.headline)
                Text("Detection self-calibrates from your motion.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Range (no GPS)") { mode = "range" }
                    .buttonStyle(.borderedProminent)
                Button("Play a round (GPS)") { mode = "round" }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}

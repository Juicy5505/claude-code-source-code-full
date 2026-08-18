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
    @State private var pending = 0

    var body: some View {
        if let mode {
            // onFinish sets this back to nil, which is what actually returns
            // you to the picker. `dismiss()` cannot: this view is rendered
            // inline at the root of a WindowGroup, with no presentation to end.
            SessionView(mode: mode) { self.mode = nil }
        } else {
            VStack(spacing: 10) {
                Text("Swing Logger")
                    .font(.headline)
                Text("Detection self-calibrates from your motion.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Surfaced, because the alternative is a round sitting
                // undelivered on the watch with nothing anywhere saying so.
                if pending > 0 {
                    Text(pending == 1
                         ? "1 round waiting to upload"
                         : "\(pending) rounds waiting to upload")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button("Range (no GPS)") { mode = "range" }
                    // .bordered is watchOS 8.0; .borderedProminent is 9.0 and
                    // would break the documented 8.5 floor.
                    .buttonStyle(.bordered)
                    .tint(.green)
                Button("Play a round (GPS)") { mode = "round" }
                    .buttonStyle(.bordered)
            }
            .padding()
            .task {
                // App launch is when the watch is most likely to be somewhere
                // with WiFi, so this is the right moment to drain the queue.
                // The watch cannot reach a tailnet — Tailscale has no watchOS
                // client — so plain WiFi is the only route it has.
                let carrier = SessionModel(mode: "round")
                await carrier.flushOutbox()
                pending = SessionModel.pendingCount
            }
        }
    }
}

import SwiftUI

@MainActor
struct ContentView: View {
    @State private var mode: String?
    @State private var showSettings = false
    @State private var usePhoneFallback = false
    @State private var pending = 0

    var body: some View {
        NavigationStack {
            if let mode {
                SidecarSessionView(mode: mode,
                                   usePhoneFallback: usePhoneFallback) {
                    self.mode = nil
                }
            } else if showSettings {
                SettingsView { showSettings = false }
            } else {
                VStack(spacing: 16) {
                    Text("WHOOP Swing Sidecar")
                        .font(.title2.bold())
                    Text("Bonds to your WHOOP strap over BLE (NOOP protocol), detects swings from strap IMU, tags GPS from the phone, uploads to wb serve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if pending > 0 {
                        Text(pending == 1
                             ? "1 round waiting to upload"
                             : "\(pending) rounds waiting to upload")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button("Range (no GPS)") { mode = "range" }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Play a round (GPS)") { mode = "round" }
                        .buttonStyle(.bordered)

                    Toggle("Phone motion fallback (simulator / no strap)", isOn: $usePhoneFallback)
                        .font(.caption)

                    Button("Upload settings") { showSettings = true }
                        .font(.caption)

                    Text("Before connecting: close the WHOOP app, put strap in pairing mode (blue LEDs).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .navigationTitle("Kit C")
                .task { await refreshPending() }
            }
        }
    }

    private func refreshPending() async {
        let model = SessionModel(mode: "round")
        await model.flushOutbox()
        pending = SessionModel.pendingCount
    }
}

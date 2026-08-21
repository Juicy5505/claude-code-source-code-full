import SwiftUI

/// Configure where finished sessions upload.
///
/// The watch cannot reach a tailnet address — use the Mac's LAN IP from
/// `ipconfig getifaddr en0`, not a 100.x Tailscale address.
@MainActor
struct SettingsView: View {
    let onDone: () -> Void

    @AppStorage(IngestSettings.urlKey) private var ingestURL = ""
    @AppStorage(IngestSettings.tokenKey) private var ingestToken = ""
    @AppStorage(WatchWristMount.storageKey) private var wristRaw = WatchWristMount.golferDefault.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wrist")
                    .font(.headline)
                Text("Alex's golf default is the right trail wrist. Path and improver follow this mount.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("Watch wrist", selection: $wristRaw) {
                    Text("Right trail").tag(WatchWristMount.trailRight.rawValue)
                    Text("Left lead").tag(WatchWristMount.leadLeft.rawValue)
                }
                .onChange(of: wristRaw) { newValue in
                    let mount = WatchWristMount(rawValue: newValue) ?? .golferDefault
                    WatchSessionTransfer.shared.setWrist(mount)
                }

                Text("Upload")
                    .font(.headline)

                Text("Your Mac running `wb serve`. LAN address only — no Tailscale on the watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Server").font(.caption2).foregroundStyle(.secondary)
                    TextField("http://192.168.1.24:8790", text: $ingestURL)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Token").font(.caption2).foregroundStyle(.secondary)
                    TextField("WB_INGEST_TOKEN", text: $ingestToken)
                }

                if IngestSettings.isConfigured {
                    Text("Queued rounds upload on WiFi when you open the app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Leave empty to keep sessions on the watch only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Done") { onDone() }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 6)
        }
    }
}

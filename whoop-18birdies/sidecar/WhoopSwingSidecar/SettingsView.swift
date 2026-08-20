import SwiftUI

struct SettingsView: View {
    let onDismiss: () -> Void
    @AppStorage(IngestSettings.urlKey) private var ingestURL = ""
    @AppStorage(IngestSettings.tokenKey) private var ingestToken = ""

    var body: some View {
        Form {
            Section("wb serve") {
                TextField("http://100.x.x.x:8790", text: $ingestURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("WB_INGEST_TOKEN", text: $ingestToken)
            }
            Section {
                Text("Tailscale works on iPhone. Copy the token from `wb serve` on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Done") { onDismiss() }
        }
        .navigationTitle("Upload settings")
    }
}

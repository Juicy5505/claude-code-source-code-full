import SwiftUI

@main
struct WhoopGolfApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await model.retryBridgeUploads(showSuccessNotice: false)
                        await model.refreshWhoopMotion(showNotReadyNotice: false)
                    }
                }
        }
    }
}

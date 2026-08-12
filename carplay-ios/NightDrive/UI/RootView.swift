import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: VehicleDataStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.needle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

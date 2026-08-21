import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            OverviewView()
                .tag(AppModel.Tab.overview)
                .tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }

            TodayView()
                .tag(AppModel.Tab.today)
                .tabItem { Label("Today", systemImage: "gauge.with.dots.needle.50percent") }

            RoundView()
                .tag(AppModel.Tab.round)
                .tabItem { Label("Round", systemImage: "figure.golf") }

            TrendsView()
                .tag(AppModel.Tab.trends)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tag(AppModel.Tab.settings)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(.golfLime)
        .alert(
            "WHOOP Golf",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            ),
            actions: { Button("OK") { model.notice = nil } },
            message: { Text(model.notice ?? "") }
        )
    }
}


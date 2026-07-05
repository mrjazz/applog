import SwiftUI

private struct WindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate

    var body: some View {
        Color.clear
            .onAppear {
                delegate.openStatisticsAction = { openWindow(id: "statistics") }
                delegate.openSettingsAction = { openWindow(id: "settings") }
            }
    }
}

@main
struct applogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        Window("Statistics", id: "statistics") {
            Group {
                if environment.isReady {
                    StatisticsView(viewModel: environment.statisticsViewModel, permissions: environment.permissions)
                } else {
                    ProgressView("Loading…").frame(width: 920, height: 560)
                }
            }
            .background(WindowOpenerBridge(delegate: appDelegate))
        }
        .defaultSize(width: 960, height: 600)

        Window("Settings", id: "settings") {
            Group {
                if environment.isReady {
                    SettingsView(settings: environment.settings, store: environment.store, statisticsViewModel: environment.statisticsViewModel)
                } else {
                    ProgressView().frame(width: 560, height: 620)
                }
            }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentSize)
    }
}

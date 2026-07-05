import Foundation
import SwiftUI
import AppKit
import Combine

/// Bootstraps the async pieces (DB open, settings load) once at launch and
/// hands out the shared instances every view/scene needs. A single instance
/// is shared between the SwiftUI `App` scenes and the AppDelegate's status
/// item, so "click opens Statistics" and "the tree the user is looking at"
/// are always talking to the same store.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    @Published private(set) var isReady = false
    @Published private(set) var store: Store!
    @Published private(set) var settings: SettingsStore!
    @Published private(set) var statisticsViewModel: StatisticsViewModel!
    @Published private(set) var isPaused = false
    let permissions = PermissionsMonitor()

    private var engine: TrackingEngine!

    private init() {}

    func bootstrap() async {
        guard !isReady else { return }
        do {
            let dbURL = try Self.databaseURL()
            let store = try Store(databaseURL: dbURL)
            let settings = await SettingsStore(store: store)
            let engine = TrackingEngine(store: store, settings: settings)
            let vm = StatisticsViewModel(store: store, engine: engine)

            self.store = store
            self.settings = settings
            self.engine = engine
            self.statisticsViewModel = vm
            self.isReady = true

            await engine.start()
            await vm.refresh()

            NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        } catch {
            print("AppEnvironment: bootstrap failed — \(error)")
        }
    }

    func togglePaused() async -> Bool {
        let newValue = await engine.togglePaused()
        isPaused = newValue
        return newValue
    }

    private static func databaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("AppTracker", isDirectory: true).appendingPathComponent("database.sqlite")
    }
}

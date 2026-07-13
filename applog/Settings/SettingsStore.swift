import Foundation
import SwiftUI
import AppKit
import Combine
import os
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// The status-item's display mode. Not yet wired to `AppDelegate`'s status
/// item rendering — persisted and editable in Settings, but every style
/// still shows the same glyph today.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case glyph
    case time
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glyph: return "Glyph"
        case .time: return "Time"
        case .hidden: return "Hidden"
        }
    }
}

/// Typed accessors over the `setting` key/value table. Settings are persisted
/// in the database (not UserDefaults) so they travel with export/merge/restore,
/// per design.md §6.
@MainActor
final class SettingsStore: ObservableObject {
    private let store: Store

    @Published var launchAtLogin: Bool
    @Published var showInDock: Bool
    @Published var sampleIntervalSeconds: Int
    @Published var semiIdleThresholdSeconds: Int
    @Published var fullyIdleThresholdSeconds: Int
    @Published var autosaveIntervalMinutes: Int
    @Published var backupRetentionCount: Int
    @Published var cullThresholdSeconds: Int
    @Published var cullAgeDays: Int
    @Published var menuBarIconStyle: MenuBarIconStyle

    init(store: Store) async {
        self.store = store
        launchAtLogin = (try? await store.setting("launchAtLogin")) == "true"
        showInDock = ((try? await store.setting("showInDock")) ?? "true") == "true"
        sampleIntervalSeconds = Int((try? await store.setting("sampleIntervalSeconds")) ?? "") ?? 5
        semiIdleThresholdSeconds = Int((try? await store.setting("semiIdleThresholdSeconds")) ?? "") ?? 10
        fullyIdleThresholdSeconds = Int((try? await store.setting("fullyIdleThresholdSeconds")) ?? "") ?? 180
        autosaveIntervalMinutes = Int((try? await store.setting("autosaveIntervalMinutes")) ?? "") ?? 10
        backupRetentionCount = Int((try? await store.setting("backupRetentionCount")) ?? "") ?? 10
        cullThresholdSeconds = Int((try? await store.setting("cullThresholdSeconds")) ?? "") ?? 60
        cullAgeDays = Int((try? await store.setting("cullAgeDays")) ?? "") ?? 30
        menuBarIconStyle = MenuBarIconStyle(rawValue: (try? await store.setting("menuBarIconStyle")) ?? "") ?? .glyph
    }

    func persist(_ key: String, _ value: String) {
        Task { try? await store.setSetting(key, value) }
    }

    func setLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        persist("launchAtLogin", value ? "true" : "false")
        LoginItemManager.setEnabled(value)
    }

    func setShowInDock(_ value: Bool) {
        showInDock = value
        persist("showInDock", value ? "true" : "false")
    }

    func setSampleInterval(_ seconds: Int) {
        sampleIntervalSeconds = seconds
        persist("sampleIntervalSeconds", String(seconds))
    }

    func setSemiIdleThreshold(_ seconds: Int) {
        semiIdleThresholdSeconds = seconds
        persist("semiIdleThresholdSeconds", String(seconds))
    }

    func setFullyIdleThreshold(_ seconds: Int) {
        fullyIdleThresholdSeconds = seconds
        persist("fullyIdleThresholdSeconds", String(seconds))
    }

    func setAutosaveInterval(_ minutes: Int) {
        autosaveIntervalMinutes = minutes
        persist("autosaveIntervalMinutes", String(minutes))
    }

    func setBackupRetention(_ count: Int) {
        backupRetentionCount = count
        persist("backupRetentionCount", String(count))
    }

    func setCullThreshold(seconds: Int, ageDays: Int) {
        cullThresholdSeconds = seconds
        cullAgeDays = ageDays
        persist("cullThresholdSeconds", String(seconds))
        persist("cullAgeDays", String(ageDays))
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style
        persist("menuBarIconStyle", style.rawValue)
    }
}

/// Wraps `SMAppService` (macOS 13+) for launch-at-login, replacing the older
/// `SMLoginItemSetEnabled` API per design.md §6.
enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                AppLogger.settings.error("failed to update login item: \(error)")
            }
        }
        #endif
    }
}

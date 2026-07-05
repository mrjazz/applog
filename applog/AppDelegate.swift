import AppKit
import SwiftUI
import Combine

/// Owns the `NSStatusItem` directly (rather than `MenuBarExtra`) because we
/// need to distinguish left-click from right-click: a plain click always
/// opens Statistics (FR-21), with no dropdown — only a right-click shows the
/// small quick-action menu (FR-21a). `MenuBarExtra` doesn't expose that
/// distinction, which is the sanctioned escape hatch to raw AppKit noted in
/// design.md §1.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isPaused = false
    private var isPausedSubscription: AnyCancellable?
    private var showInDockSubscription: AnyCancellable?

    /// Window titles that should keep AppTracker in the Dock/Cmd-Tab list
    /// while visible (FR: appear only while Statistics or Settings is open).
    private static let dockRelevantWindowTitles: Set<String> = ["Statistics", "Settings"]

    /// Registered by `WindowOpenerBridge` once the Statistics window scene
    /// exists, so this AppKit-side delegate can drive SwiftUI's `openWindow`.
    var openStatisticsAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hourglass.bottomhalf.fill", accessibilityDescription: "AppTracker")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        isPausedSubscription = AppEnvironment.shared.$isPaused.sink { [weak self] paused in
            self?.updatePauseState(paused)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWindowVisibilityChange),
            name: NSWindow.willCloseNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWindowVisibilityChange),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )

        Task {
            await AppEnvironment.shared.bootstrap()
            showInDockSubscription = AppEnvironment.shared.settings.$showInDock.sink { [weak self] _ in
                self?.updateActivationPolicy()
            }
            updateActivationPolicy()
        }
    }

    @objc private func handleWindowVisibilityChange(_ notification: Notification) {
        // Deferred a tick: on willClose the window is still in NSApp.windows
        // and still reports isVisible, so check after the close completes.
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    private func updateActivationPolicy() {
        let anyRelevantWindowVisible = NSApp.windows.contains {
            $0.isVisible && Self.dockRelevantWindowTitles.contains($0.title)
        }
        let pinnedToDock = AppEnvironment.shared.settings?.showInDock ?? false
        NSApp.setActivationPolicy(anyRelevantWindowVisible || pinnedToDock ? .regular : .accessory)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuickActionMenu()
        } else {
            openStatistics()
        }
    }

    private func showQuickActionMenu() {
        let menu = NSMenu()

        let pauseItem = NSMenuItem(
            title: isPaused ? "Resume Tracking" : "Pause Tracking",
            action: #selector(togglePauseTracking), keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let statisticsItem = NSMenuItem(title: "Statistics…", action: #selector(openStatistics), keyEquivalent: "")
        statisticsItem.target = self
        menu.addItem(statisticsItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit AppTracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so the next left-click goes back through statusItemClicked
        // instead of always reopening this menu.
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    @objc private func togglePauseTracking() {
        Task { await AppEnvironment.shared.togglePaused() }
    }

    private func updatePauseState(_ paused: Bool) {
        isPaused = paused
        statusItem.button?.image = NSImage(
            systemSymbolName: paused ? "hourglass" : "hourglass.bottomhalf.fill",
            accessibilityDescription: "AppTracker"
        )
    }

    @objc private func openStatistics() {
        bringToFront(windowTitle: "Statistics", action: openStatisticsAction)
    }

    @objc private func openSettings() {
        bringToFront(windowTitle: "Settings", action: openSettingsAction)
    }

    /// `openWindow(id:)` is responsible for creating the scene the first
    /// time, but SwiftUI doesn't reliably raise an already-open window above
    /// other apps, so we always follow up by ordering the matching NSWindow
    /// to the front ourselves.
    private func bringToFront(windowTitle: String, action: (() -> Void)?) {
        NSApp.activate(ignoringOtherApps: true)
        action?()
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title == windowTitle })?.makeKeyAndOrderFront(nil)
        }
    }
}

import Foundation
import ApplicationServices
import AppKit
import Combine

/// Watches Accessibility trust status so the UI can show/hide the permission
/// banner (FR-35) without the app ever blocking on a modal prompt itself.
@MainActor
final class PermissionsMonitor: ObservableObject {
    @Published private(set) var isAccessibilityGranted: Bool

    private var pollTimer: Timer?

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
        // Accessibility grants take effect immediately but this process only
        // learns about them by re-checking; poll at a low frequency rather
        // than requiring the user to relaunch the app.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isAccessibilityGranted {
            isAccessibilityGranted = granted
        }
    }

    /// Triggers the system's own "AppTracker would like to control this
    /// computer" prompt if not already granted, in addition to the banner.
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

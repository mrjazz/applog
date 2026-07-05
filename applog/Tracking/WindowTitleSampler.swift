import ApplicationServices
import AppKit

/// Reads the frontmost app's focused-window title via the Accessibility API
/// (design.md §3.1). Returns nil title when Accessibility isn't granted or no
/// window is focused — callers fall back to app-level-only tracking.
enum WindowTitleSampler {
    static func frontmostWindowTitle(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard windowResult == .success, let window = focusedWindow else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String, !title.isEmpty else { return nil }
        return title
    }
}

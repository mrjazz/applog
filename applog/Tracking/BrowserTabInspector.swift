import Foundation
import AppKit

/// Fetches the frontmost tab's URL for supported browsers via Apple Events.
/// A browser's Accessibility window title is the page's `<title>` only — it
/// never contains the domain — so grouping by site (FR-3/FR-4) needs the
/// real URL, not a regex guess against the title text.
@MainActor
enum BrowserTabInspector {
    static func activeTabURL(bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return run(script: """
                tell application "Safari"
                    if (count of windows) = 0 then return ""
                    return URL of front document
                end tell
                """)
        case "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser":
            return run(script: """
                tell application "\(appleScriptAppName(for: bundleID))"
                    if (count of windows) = 0 then return ""
                    return URL of active tab of front window
                end tell
                """)
        default:
            // Firefox has no scriptable tab/URL interface via AppleScript;
            // callers fall back to the window-title-based domain guess.
            return nil
        }
    }

    private static func appleScriptAppName(for bundleID: String) -> String {
        switch bundleID {
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "company.thebrowser.Browser": return "Arc"
        default: return "Google Chrome"
        }
    }

    private static func run(script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        guard errorDict == nil, let value = result.stringValue, !value.isEmpty else { return nil }
        return value
    }
}

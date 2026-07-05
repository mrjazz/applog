import Foundation

/// One level of the node chain to find-or-create, root first.
struct HierarchyLevel {
    let kind: NodeKind
    let name: String
}

/// Turns (bundle id, app name, window title) into the chain of nodes to
/// find-or-create, per FR-3/FR-4: browsers get a fixed three-level shape
/// (browser → domain → page title); everything else is delimiter-parsed
/// into arbitrary-depth segments. See design.md §3.1 — this is intentionally
/// app-agnostic beyond the browser bundle-id list below.
nonisolated enum HierarchyBuilder {
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
    ]

    private static let delimiters = [" - ", " | ", " : ", " > ", "\\"]

    private static let hostnamePattern = try! NSRegularExpression(
        pattern: #"([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}"#
    )

    static func chain(bundleID: String, appName: String, windowTitle: String?, tabURL: String? = nil) -> [HierarchyLevel] {
        var levels: [HierarchyLevel] = [HierarchyLevel(kind: .app, name: appName)]

        guard let title = windowTitle, !title.isEmpty else { return levels }

        if browserBundleIDs.contains(bundleID) {
            let domain = tabURL.flatMap(extractHost) ?? extractDomain(from: title) ?? "Unknown"
            levels.append(HierarchyLevel(kind: .domain, name: domain))
            levels.append(HierarchyLevel(kind: .pageTitle, name: title))
        } else {
            for segment in splitOnDelimiters(title) {
                levels.append(HierarchyLevel(kind: .titleSegment, name: segment))
            }
        }
        return levels
    }

    /// Parses the real domain out of an actual tab URL (reliable) rather
    /// than guessing from the page title (`extractDomain`, kept only as a
    /// fallback for browsers Apple Events can't query, e.g. Firefox).
    private static func extractHost(from urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func splitOnDelimiters(_ title: String) -> [String] {
        var pieces = [title]
        for delimiter in delimiters {
            pieces = pieces.flatMap { $0.components(separatedBy: delimiter) }
        }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func extractDomain(from title: String) -> String? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = hostnamePattern.firstMatch(in: title, range: range),
              let matchRange = Range(match.range, in: title) else { return nil }
        return String(title[matchRange]).lowercased()
    }
}

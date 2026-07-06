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

    /// Matches a plain domain (needs a letter-based TLD), an IPv4 address,
    /// or "localhost" — each optionally followed by :port, since local/dev
    /// URLs (routers, self-hosted services, `localhost:3000`) are common
    /// enough that the letters-only pattern alone left them as "Unknown".
    private static let hostnamePattern = try! NSRegularExpression(
        pattern: #"(?:(?:\d{1,3}\.){3}\d{1,3}|localhost|(?:[a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,})(?::\d+)?"#
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
    /// Keeps the port when present — `URL.host` alone would collapse
    /// distinct local services like `192.168.1.1:8080` and `:9090` into a
    /// single domain node.
    private static func extractHost(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let port = url.port else { return trimmedHost }
        return "\(trimmedHost):\(port)"
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

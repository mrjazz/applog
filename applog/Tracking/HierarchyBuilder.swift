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

    /// VS Code's window title puts the open file first, the project/folder
    /// last: "file.ext - project".
    private static let vscodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
    ]

    /// JetBrains IDEA-platform IDEs (IntelliJ IDEA, Android Studio, WebStorm,
    /// PyCharm, etc.) put the project first, the open file/tab last:
    /// "project – file.ext".
    private static let jetBrainsBundleIDs: Set<String> = [
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm", "com.jetbrains.PhpStorm",
        "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
        "com.jetbrains.CLion", "com.jetbrains.rubymine",
        "com.jetbrains.goland", "com.jetbrains.datagrip",
        "com.jetbrains.rider",
        "com.google.android.studio",
    ]

    private static let delimiters = [" - ", " | ", " : ", " > ", "\\"]

    /// Title separators IDEs use between project and file — includes the en
    /// and em dashes JetBrains IDEs favor over a plain hyphen.
    private static let ideDelimiters = [" – ", " — ", " - "]

    private static let appNameSuffixes: Set<String> = [
        "Visual Studio Code", "Android Studio",
    ]

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
        } else if vscodeBundleIDs.contains(bundleID) {
            let (project, tab) = splitProjectAndTab(title, projectFirst: false)
            levels.append(HierarchyLevel(kind: .project, name: project))
            levels.append(HierarchyLevel(kind: .tab, name: tab))
        } else if jetBrainsBundleIDs.contains(bundleID) {
            let (project, tab) = splitProjectAndTab(title, projectFirst: true)
            levels.append(HierarchyLevel(kind: .project, name: project))
            levels.append(HierarchyLevel(kind: .tab, name: tab))
        } else {
            for segment in splitOnDelimiters(title) {
                levels.append(HierarchyLevel(kind: .titleSegment, name: segment))
            }
        }
        return levels
    }

    /// Splits an IDE window title into (project, tab). `projectFirst`
    /// reflects that JetBrains IDEs order "project – file" while VS Code
    /// orders "file - project"; a trailing app-name segment (VS Code appends
    /// "Visual Studio Code" when unfocused) is dropped either way.
    private static func splitProjectAndTab(_ title: String, projectFirst: Bool) -> (project: String, tab: String) {
        var parts = [title]
        for delimiter in ideDelimiters {
            parts = parts.flatMap { $0.components(separatedBy: delimiter) }
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let last = parts.last, appNameSuffixes.contains(last), parts.count > 1 {
            parts.removeLast()
        }

        guard parts.count > 1 else {
            return (project: "Unknown", tab: parts.first ?? title)
        }
        return projectFirst
            ? (project: parts.first!, tab: parts.last!)
            : (project: parts.last!, tab: parts.first!)
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

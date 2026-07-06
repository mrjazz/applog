import Foundation

enum NodeKind: String, Codable {
    case app
    case titleSegment = "title-segment"
    case domain
    case pageTitle = "page-title"
    case away
    case project
    case tab
}

struct Node: Identifiable, Hashable {
    let id: Int64
    var parentID: Int64?
    var kind: NodeKind
    var name: String
    var bundleID: String?
    var tagID: Int64?
    var hidden: Bool
    var createdAt: Date
}

struct Tag: Identifiable, Hashable {
    let id: Int64
    var name: String
    var colorHex: String
}

struct UsageBucket {
    var nodeID: Int64
    var day: Date
    var activeSeconds: Int
    var semiIdleSeconds: Int
    var keyClicks: Int
    var mouseClicks: Int
}

struct TrackedSession {
    var nodeID: Int64
    var startedAt: Date
    var endedAt: Date
}

enum ExclusionKind: String {
    case app
    case domain
}

/// A resolved row for display in the Statistics tree: a node plus everything
/// derived from its subtree for the current filter window.
struct TreeRow: Identifiable {
    let node: Node
    var depth: Int
    var totalSeconds: Int
    /// Seconds broken down by resolved tag, for this node + all descendants.
    var tagBreakdown: [Tag?: Int]
    var children: [TreeRow]

    var id: Int64 { node.id }

    var resolvedTagLabel: String {
        let nonZero = tagBreakdown.filter { $0.value > 0 }
        if nonZero.count > 1 { return "Mixed" }
        if let only = nonZero.first?.key { return only.name }
        return "Untagged"
    }

    /// The single tag this node resolves to, if any — `nil` for "Mixed" (more
    /// than one tag among its descendants) or "Untagged", which render as a
    /// neutral pill instead of a tag color.
    var resolvedTag: Tag? {
        let nonZero = tagBreakdown.filter { $0.value > 0 }
        guard nonZero.count == 1 else { return nil }
        return nonZero.first?.key
    }
}

/// One colored block on the daily timeline panel.
struct TimelineBlock {
    var startFraction: Double  // 0...1 across the 24h day
    var widthFraction: Double
    var colorHex: String
}

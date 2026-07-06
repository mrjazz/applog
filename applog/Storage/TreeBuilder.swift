import Foundation

enum TreeBuilder {
    static let untaggedColorHex = "#9A9AA0"

    struct Filter {
        var minDurationSeconds: Int = 0
        var searchText: String = ""
        var activeTagID: Int64?
        var filterOnTag: Bool = false
        var excludedAppBundleIDs: Set<String> = []
        var excludedDomains: Set<String> = []
    }

    /// True for a node the user has excluded directly: an app by bundle ID,
    /// a domain by name, or the synthetic "Away" node by its fixed name —
    /// entered as "Away" in the same Excluded Apps list, since it has no
    /// real bundle ID to match against.
    static func isNodeItselfExcluded(_ node: Node, filter: Filter) -> Bool {
        switch node.kind {
        case .app:
            guard let bundleID = node.bundleID else { return false }
            return filter.excludedAppBundleIDs.contains(bundleID)
        case .domain:
            return filter.excludedDomains.contains(node.name.lowercased())
        case .away:
            return filter.excludedAppBundleIDs.contains { $0.caseInsensitiveCompare(node.name) == .orderedSame }
        default:
            return false
        }
    }

    /// True if this node — or, for a session's leaf node, any of its
    /// ancestors — is an excluded app, domain, or the Away node. Shared by
    /// the tree builder and the daily timeline so excluded activity
    /// disappears from both.
    static func isExcluded(nodeID: Int64?, nodes: [Int64: Node], filter: Filter) -> Bool {
        guard !filter.excludedAppBundleIDs.isEmpty || !filter.excludedDomains.isEmpty else { return false }
        var current = nodeID.flatMap { nodes[$0] }
        while let n = current {
            if isNodeItselfExcluded(n, filter: filter) { return true }
            current = n.parentID.flatMap { nodes[$0] }
        }
        return false
    }

    /// Builds the full tree for a date range, resolves inherited tags (FR-12/FR-13),
    /// and applies the sidebar filters. Nodes are looked up once into memory —
    /// the design goal (design.md §4.1) is a node count small enough that this
    /// is cheap even after years of use.
    static func buildTree(
        nodes: [Int64: Node],
        ownSeconds: [Int64: Int],
        tags: [Int64: Tag],
        filter: Filter
    ) -> [TreeRow] {
        var childrenByParent: [Int64: [Node]] = [:]
        for node in nodes.values where !node.hidden && !isNodeItselfExcluded(node, filter: filter) {
            if let parentID = node.parentID {
                childrenByParent[parentID, default: []].append(node)
            }
        }

        func resolvedTag(for node: Node) -> Tag? {
            var current: Node? = node
            while let n = current {
                if let tagID = n.tagID, let tag = tags[tagID] { return tag }
                current = n.parentID.flatMap { nodes[$0] }
            }
            return nil
        }

        func build(_ node: Node) -> TreeRow {
            let ownTotal = ownSeconds[node.id] ?? 0
            let childNodes = (childrenByParent[node.id] ?? []).sorted { $0.name < $1.name }
            let childRows = childNodes.map(build)

            var breakdown: [Tag?: Int] = [:]
            if ownTotal > 0 {
                breakdown[resolvedTag(for: node), default: 0] += ownTotal
            }
            for child in childRows {
                for (tag, seconds) in child.tagBreakdown {
                    breakdown[tag, default: 0] += seconds
                }
            }

            let total = ownTotal + childRows.reduce(0) { $0 + $1.totalSeconds }
            return TreeRow(node: node, depth: 0, totalSeconds: total, tagBreakdown: breakdown, children: childRows)
        }

        func assignDepth(_ row: TreeRow, depth: Int) -> TreeRow {
            var row = row
            row.depth = depth
            row.children = row.children.map { assignDepth($0, depth: depth + 1) }
            return row
        }

        func matchesSearch(_ row: TreeRow) -> Bool {
            guard !filter.searchText.isEmpty else { return true }
            if row.node.name.localizedCaseInsensitiveContains(filter.searchText) { return true }
            return row.children.contains(where: matchesSearch)
        }

        func matchesTagFilter(_ row: TreeRow) -> Bool {
            guard filter.filterOnTag, let activeTagID = filter.activeTagID else { return true }
            if row.tagBreakdown.contains(where: { $0.key?.id == activeTagID && $0.value > 0 }) { return true }
            return false
        }

        func prune(_ row: TreeRow) -> TreeRow? {
            // Duration displays as whole minutes (DurationFormat.short), so
            // anything under 60 seconds would render as a confusing "0m" —
            // hide it regardless of the user's own minDuration setting.
            guard row.totalSeconds >= 60 else { return nil }
            guard row.totalSeconds >= filter.minDurationSeconds else { return nil }
            guard matchesSearch(row) else { return nil }
            guard matchesTagFilter(row) else { return nil }
            var row = row
            row.children = row.children.compactMap(prune).sorted { $0.totalSeconds > $1.totalSeconds }
            return row
        }

        let roots = nodes.values.filter { $0.parentID == nil && !$0.hidden && !isNodeItselfExcluded($0, filter: filter) }
        let built = roots.map(build).compactMap(prune)
        return built
            .map { assignDepth($0, depth: 0) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    /// Flattens a tree into a single list (pre-order) — used to find the
    /// max duration across all visible rows, which scales every bar's length
    /// (FR-16: length reflects absolute magnitude, not just proportion-of-parent).
    static func flatten(_ rows: [TreeRow]) -> [TreeRow] {
        rows.flatMap { [$0] + flatten($0.children) }
    }
}

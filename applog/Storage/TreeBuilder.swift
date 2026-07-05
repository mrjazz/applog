import Foundation

enum TreeBuilder {
    static let untaggedColorHex = "#9A9AA0"

    struct Filter {
        var minDurationSeconds: Int = 0
        var searchText: String = ""
        var activeTagID: Int64?
        var filterOnTag: Bool = false
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
        for node in nodes.values where !node.hidden {
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
            guard row.totalSeconds >= filter.minDurationSeconds else { return nil }
            guard matchesSearch(row) else { return nil }
            guard matchesTagFilter(row) else { return nil }
            var row = row
            row.children = row.children.compactMap(prune).sorted { $0.totalSeconds > $1.totalSeconds }
            return row
        }

        let roots = nodes.values.filter { $0.parentID == nil && !$0.hidden }
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

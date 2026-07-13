import Foundation
import SwiftUI
import Combine

enum DateQuickSet: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisYear = "This Year"
    case allTime = "All Time"
    case custom = "Custom Range"

    var id: String { rawValue }

    /// `nil` for `.custom` — the view model resolves that case against the
    /// user's own from/to dates instead of a fixed preset. Bounds are whole
    /// calendar days since `Store.ownActiveSeconds` compares day-string
    /// buckets inclusively (see `StatisticsViewModel.activeRange`) — `to`
    /// just needs to fall on the last intended day, not be an exact instant.
    var range: (from: Date, to: Date)? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return (start, now)
        case .lastWeek:
            let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let start = cal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
            let end = cal.date(byAdding: .day, value: -1, to: thisWeekStart) ?? thisWeekStart
            return (start, end)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (start, now)
        case .lastMonth:
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let start = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let end = cal.date(byAdding: .day, value: -1, to: thisMonthStart) ?? thisMonthStart
            return (start, end)
        case .thisYear:
            let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return (start, now)
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
        case .custom:
            return nil
        }
    }
}

@MainActor
final class StatisticsViewModel: ObservableObject {
    private let store: Store
    private let engine: TrackingEngine

    @Published var rows: [TreeRow] = []
    @Published var tags: [Tag] = []
    @Published var selectedTagID: Int64?
    @Published var selectedNodeID: Int64?
    @Published var filterOnTag = false
    @Published var minDurationMinutes: Double = 0
    @Published var searchText = ""
    @Published var quickSet: DateQuickSet = .today {
        didSet {
            guard let range = quickSet.range else { return }
            customFrom = range.from
            customTo = range.to
        }
    }
    /// Seeds the custom-range calendars with a sensible starting window
    /// before the user has touched them — not tied to `quickSet`'s default
    /// (`.today`), since seeding "From" at today's start would collapse the
    /// calendar to a single day the first time Custom Range is picked.
    @Published var customFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customTo: Date = Date()
    @Published var timelineDays: [(label: String, totalSeconds: Int, blocks: [TimelineBlock])] = []
    @Published var totalTrackedToday: Int = 0
    /// Node IDs the user has expanded. Absence means collapsed — nodes
    /// default closed until opened.
    @Published var expandedNodeIDs: Set<Int64> = []

    var maxRowSeconds: Int {
        TreeBuilder.flatten(rows).map(\.totalSeconds).max() ?? 1
    }

    func expandAll() {
        expandedNodeIDs = Set(TreeBuilder.flatten(rows).filter { !$0.children.isEmpty }.map(\.id))
    }

    func collapseAll() {
        expandedNodeIDs.removeAll()
    }

    /// `ownActiveSeconds` compares whole calendar-day strings (`day BETWEEN
    /// ? AND ?`, inclusive both ends — see Store.swift), so the upper bound
    /// here must be `customTo` itself, not the start of the following day;
    /// advancing to the next day would leak one extra day of data into the
    /// selected range.
    var activeRange: (from: Date, to: Date) {
        quickSet.range ?? (Calendar.current.startOfDay(for: customFrom), customTo)
    }

    func setCustomFrom(_ date: Date) {
        customFrom = date
        quickSet = .custom
    }

    func setCustomTo(_ date: Date) {
        customTo = date
        quickSet = .custom
    }

    init(store: Store, engine: TrackingEngine) {
        self.store = store
        self.engine = engine
    }

    func refresh() async {
        do {
            let nodes = try await store.allNodes()
            let allTags = try await store.allTags()
            let tagsByID = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
            let (from, to) = activeRange
            let ownSeconds = try await store.ownActiveSeconds(from: from, to: to)
            let excludedApps = Set((try? await store.exclusions(kind: .app)) ?? [])
            let excludedDomains = Set(((try? await store.exclusions(kind: .domain)) ?? []).map { $0.lowercased() })

            let filter = TreeBuilder.Filter(
                minDurationSeconds: Int(minDurationMinutes * 60),
                searchText: searchText,
                activeTagID: selectedTagID,
                filterOnTag: filterOnTag,
                excludedAppBundleIDs: excludedApps,
                excludedDomains: excludedDomains
            )
            let builtRows = TreeBuilder.buildTree(nodes: nodes, ownSeconds: ownSeconds, tags: tagsByID, filter: filter)

            tags = allTags
            if selectedTagID == nil { selectedTagID = allTags.first?.id }
            rows = builtRows

            let (todayStart, now) = DateQuickSet.today.range!
            let todaySeconds = try await store.ownActiveSeconds(from: todayStart, to: now)
            totalTrackedToday = todaySeconds
                .filter { !TreeBuilder.isExcluded(nodeID: $0.key, nodes: nodes, filter: filter) }
                .values.reduce(0, +)

            await refreshTimeline(nodes: nodes, tagsByID: tagsByID, filter: filter)
        } catch {
            print("StatisticsViewModel: refresh failed — \(error)")
        }
    }

    private func refreshTimeline(nodes: [Int64: Node], tagsByID: [Int64: Tag], filter: TreeBuilder.Filter) async {
        func resolvedColor(for nodeID: Int64?) -> String {
            var current = nodeID.flatMap { nodes[$0] }
            while let n = current {
                if let tagID = n.tagID, let tag = tagsByID[tagID] { return tag.colorHex }
                current = n.parentID.flatMap { nodes[$0] }
            }
            return TreeBuilder.untaggedColorHex
        }

        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d"

        var result: [(String, Int, [TimelineBlock])] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            // Same source as the toolbar total and the tree (usage_bucket,
            // via ownActiveSeconds) rather than the `session` table: a
            // session only gets written once it closes, so the still-open
            // "current" session would be missing from today's total if we
            // aggregated from sessions(onDay:) instead, as this used to.
            let nodeSeconds = (try? await store.ownActiveSeconds(from: dayStart, to: dayStart)) ?? [:]
            guard !nodeSeconds.isEmpty else { continue }

            // One segment per tag actually used that day (not one per node
            // — a tag used across a dozen nodes should still be a single
            // bar), sized by that tag's total time as a fraction of the
            // day, e.g. 2.4h of a 24h day renders as a 10%-wide segment.
            var secondsByColor: [String: Int] = [:]
            for (nodeID, seconds) in nodeSeconds {
                guard seconds > 0, !TreeBuilder.isExcluded(nodeID: nodeID, nodes: nodes, filter: filter) else { continue }
                secondsByColor[resolvedColor(for: nodeID), default: 0] += seconds
            }
            guard !secondsByColor.isEmpty else { continue }

            let daySeconds = dayEnd.timeIntervalSince(dayStart)
            var cursor = 0.0
            let blocks = secondsByColor.sorted { $0.value > $1.value }.map { colorHex, seconds -> TimelineBlock in
                let widthFraction = Double(seconds) / daySeconds
                let block = TimelineBlock(startFraction: cursor, widthFraction: widthFraction, colorHex: colorHex)
                cursor += widthFraction
                return block
            }
            let totalSeconds = secondsByColor.values.reduce(0, +)
            result.append((dayFormatter.string(from: day), totalSeconds, blocks))
        }
        timelineDays = result
    }

    func applySelectedTag(toNode nodeID: Int64) {
        guard let tagID = selectedTagID else { return }
        Task {
            try? await store.applyTag(tagID, toNode: nodeID)
            await refresh()
        }
    }

    func renameTag(id tagID: Int64, to newName: String) {
        guard !newName.isEmpty else { return }
        Task {
            try? await store.renameTag(id: tagID, to: newName)
            await refresh()
        }
    }

    func createTag(name: String, colorHex: String) {
        Task {
            _ = try? await store.createTag(name: name, colorHex: colorHex)
            await refresh()
        }
    }
}

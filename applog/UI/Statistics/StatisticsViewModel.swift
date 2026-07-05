import Foundation
import SwiftUI
import Combine

enum DateQuickSet: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: String { rawValue }

    var range: (from: Date, to: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return (start, now)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (start, now)
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
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
    @Published var quickSet: DateQuickSet = .thisWeek
    @Published var timelineDays: [(label: String, blocks: [TimelineBlock])] = []
    @Published var totalTrackedToday: Int = 0

    var maxRowSeconds: Int {
        TreeBuilder.flatten(rows).map(\.totalSeconds).max() ?? 1
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
            let (from, to) = quickSet.range
            let ownSeconds = try await store.ownActiveSeconds(from: from, to: to)

            let filter = TreeBuilder.Filter(
                minDurationSeconds: Int(minDurationMinutes * 60),
                searchText: searchText,
                activeTagID: selectedTagID,
                filterOnTag: filterOnTag
            )
            let builtRows = TreeBuilder.buildTree(nodes: nodes, ownSeconds: ownSeconds, tags: tagsByID, filter: filter)

            tags = allTags
            if selectedTagID == nil { selectedTagID = allTags.first?.id }
            rows = builtRows

            let (todayStart, now) = DateQuickSet.today.range
            let todaySeconds = try await store.ownActiveSeconds(from: todayStart, to: now)
            totalTrackedToday = todaySeconds.values.reduce(0, +)

            await refreshTimeline(nodes: nodes, tagsByID: tagsByID)
        } catch {
            print("StatisticsViewModel: refresh failed — \(error)")
        }
    }

    private func refreshTimeline(nodes: [Int64: Node], tagsByID: [Int64: Tag]) async {
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

        var result: [(String, [TimelineBlock])] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let sessions = (try? await store.sessions(onDay: dayStart)) ?? []
            guard !sessions.isEmpty else { continue }
            let blocks = sessions.map { session -> TimelineBlock in
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let clampedStart = max(session.startedAt, dayStart)
                let clampedEnd = min(session.endedAt, dayEnd)
                let daySeconds = dayEnd.timeIntervalSince(dayStart)
                let startFraction = clampedStart.timeIntervalSince(dayStart) / daySeconds
                let widthFraction = max(0, clampedEnd.timeIntervalSince(clampedStart) / daySeconds)
                return TimelineBlock(
                    startFraction: startFraction, widthFraction: widthFraction,
                    colorHex: resolvedColor(for: session.nodeID)
                )
            }
            result.append((dayFormatter.string(from: day), blocks))
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

    func renameSelectedTag(to newName: String) {
        guard let tagID = selectedTagID, !newName.isEmpty else { return }
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

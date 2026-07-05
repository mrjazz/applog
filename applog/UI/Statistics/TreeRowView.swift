import SwiftUI

struct TreeListView: View {
    let rows: [TreeRow]
    let maxSeconds: Int
    @Binding var selectedNodeID: Int64?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    TreeRowView(row: row, maxSeconds: maxSeconds, selectedNodeID: $selectedNodeID)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct TreeRowView: View {
    let row: TreeRow
    let maxSeconds: Int
    @Binding var selectedNodeID: Int64?

    var body: some View {
        if row.children.isEmpty {
            content
        } else {
            DisclosureGroup {
                ForEach(row.children) { child in
                    TreeRowView(row: child, maxSeconds: maxSeconds, selectedNodeID: $selectedNodeID)
                }
            } label: {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Text(row.node.name)
                .font(.system(size: row.depth == 0 ? 12.5 : 12))
                .foregroundStyle(row.depth == 0 ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(row.resolvedTagLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            Text(DurationFormat.short(row.totalSeconds))
                .font(.system(size: 12, weight: row.depth == 0 ? .medium : .regular))
                .foregroundStyle(row.depth == 0 ? .primary : .secondary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            SegmentedBar(breakdown: row.tagBreakdown, totalSeconds: row.totalSeconds, maxSeconds: maxSeconds)
                .frame(width: 130, height: 7)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(selectedNodeID == row.node.id ? Color.accentColor.opacity(0.12) : .clear)
        .onTapGesture { selectedNodeID = row.node.id }
    }
}

/// The proportional, tag-colored bar to the right of each row (FR-16): length
/// scales against the largest visible row's duration; color is a single fill
/// or a stack of segments sized by each tag's share of this node's time.
struct SegmentedBar: View {
    let breakdown: [Tag?: Int]
    let totalSeconds: Int
    let maxSeconds: Int

    var body: some View {
        GeometryReader { geo in
            let widthFraction = maxSeconds > 0 ? Double(totalSeconds) / Double(maxSeconds) : 0
            let barWidth = geo.size.width * widthFraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).fill(Color.secondary.opacity(0.15))
                HStack(spacing: 0) {
                    ForEach(sortedSegments, id: \.0) { tag, seconds in
                        Rectangle().fill(Color(hex: tag?.colorHex ?? TreeBuilder.untaggedColorHex))
                            .frame(width: barWidth * (Double(seconds) / Double(max(totalSeconds, 1))))
                    }
                }
                .frame(width: barWidth, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 3.5))
            }
        }
    }

    private var sortedSegments: [(Tag?, Int)] {
        breakdown.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

enum DurationFormat {
    static func short(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

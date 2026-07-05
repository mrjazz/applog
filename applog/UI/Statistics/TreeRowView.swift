import SwiftUI
import AppKit

struct TreeListView: View {
    let rows: [TreeRow]
    let maxSeconds: Int
    @Binding var selectedNodeID: Int64?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TreeRowView(row: row, maxSeconds: maxSeconds, selectedNodeID: $selectedNodeID)
                    if index < rows.count - 1 {
                        Divider().padding(.horizontal, 18).padding(.vertical, 4)
                    }
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
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            if isExpanded {
                ForEach(row.children) { child in
                    TreeRowView(row: child, maxSeconds: maxSeconds, selectedNodeID: $selectedNodeID)
                }
            }
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: indent)

            disclosureChevron

            NodeIcon(row: row)

            Text(row.node.name)
                .font(.system(size: row.depth == 0 ? 12.5 : 12))
                .foregroundStyle(row.depth == 0 ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            TagPill(label: row.resolvedTagLabel, colorHex: row.resolvedTag?.colorHex)

            Spacer(minLength: 8)

            Text(DurationFormat.short(row.totalSeconds))
                .font(.system(size: 12, weight: row.depth == 0 ? .medium : .regular))
                .foregroundStyle(row.depth == 0 ? .primary : .secondary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            SegmentedBar(breakdown: row.tagBreakdown, totalSeconds: row.totalSeconds, maxSeconds: maxSeconds)
                .frame(width: 130, height: 7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(selectedNodeID == row.node.id ? Color.accentColor.opacity(0.12) : .clear)
        .onTapGesture { selectedNodeID = row.node.id }
    }

    /// Depth 1 nodes sit 24pt in, depth 2 sit 44pt in — matches
    /// docs/design-mockup.html's `.tree-row.depth-1/2 .node` padding-left.
    private var indent: CGFloat {
        row.depth == 0 ? 0 : CGFloat(row.depth) * 20 + 4
    }

    @ViewBuilder
    private var disclosureChevron: some View {
        if row.children.isEmpty {
            Color.clear.frame(width: 10)
        } else {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The badge in front of each node name (FR-3/FR-4 hierarchy display): the
/// app's own icon at the top level (reused from the installed app, not
/// hand-picked per app), a plain tag-colored dot for everything nested
/// underneath (domains, page titles, title segments).
private struct NodeIcon: View {
    let row: TreeRow

    var body: some View {
        if row.depth == 0 {
            Group {
                if let icon = row.node.bundleID.flatMap(AppIconCache.icon) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: fallbackColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            Image(systemName: fallbackSymbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(hex: dominantColorHex))
                .frame(width: 8, height: 8)
        }
    }

    private var dominantColorHex: String {
        row.tagBreakdown.max { $0.value < $1.value }?.key?.colorHex ?? TreeBuilder.untaggedColorHex
    }

    private var fallbackSymbol: String {
        if row.node.kind == .away { return "moon.stars.fill" }
        guard let first = row.node.name.lowercased().first, first.isLetter else { return "app.fill" }
        return "\(first).circle.fill"
    }

    private static let fallbackPalette: [[String]] = [
        ["#4C8BF5", "#1D3F91"],
        ["#5BC0F8", "#0A7FD6"],
        ["#C774E8", "#7B3FB5"],
        ["#7ED88A", "#1F9E46"],
        ["#F2A65A", "#D97A1C"],
        ["#E88A9E", "#C23F63"],
    ]

    private var fallbackColors: [Color] {
        if row.node.kind == .away { return [Color(hex: "#8E8E93"), Color(hex: "#5B5B60")] }
        let index = abs(row.node.name.hashValue) % Self.fallbackPalette.count
        return Self.fallbackPalette[index].map { Color(hex: $0) }
    }
}

/// Looks up each installed app's real icon by bundle identifier once and
/// reuses it, instead of hand-picking a glyph per app.
nonisolated enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forBundleID bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// The resolved-tag pill next to each node name: a light tint of the tag's
/// color behind a darkened version of that same color as text, which keeps
/// contrast above 4:1 even for light hues (a flat color + white text does
/// not — e.g. the default orange swatch is ~2.3:1 against white).
private struct TagPill: View {
    let label: String
    let colorHex: String?

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
    }

    private var backgroundColor: Color {
        guard let colorHex else { return Color.secondary.opacity(0.12) }
        return Color(hex: colorHex).opacity(0.16)
    }

    private var textColor: Color {
        guard let colorHex else { return .secondary }
        return Color(hex: colorHex).darkened(by: 0.4)
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

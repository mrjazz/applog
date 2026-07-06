import SwiftUI

/// One row per day, each a 24-hour strip colored by resolved tag (FR-19b).
/// Independent of the tree's filters — always shows full days.
struct TimelinePanel: View {
    let days: [(label: String, totalSeconds: Int, blocks: [TimelineBlock])]
    let tags: [Tag]

    /// ScrollView is greedy along its scroll axis regardless of any frame
    /// modifier on it or its content, and internally centers content that's
    /// shorter than the space it was given. The only reliable fix is to
    /// measure that space and force the content to fill at least it, so
    /// there's nothing left to center — see the GeometryReader below.
    @State private var scrollAreaHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY TIMELINE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            legend

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(days, id: \.label) { day in
                        HStack(spacing: 8) {
                            Text(day.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                            DayTrack(blocks: day.blocks)
                                .frame(height: 11)
                            Text(DurationFormat.short(day.totalSeconds))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                .frame(minHeight: scrollAreaHeight, alignment: .top)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollAreaHeight = geo.size.height }
                        .onChange(of: geo.size.height) { scrollAreaHeight = geo.size.height }
                }
            )
        }
        .padding(14)
    }

    private var legend: some View {
        LegendFlow {
            ForEach(tags) { tag in
                legendItem(name: tag.name, colorHex: tag.colorHex)
            }
            legendItem(name: "Untagged / Away", colorHex: TreeBuilder.untaggedColorHex)
        }
    }

    private func legendItem(name: String, colorHex: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: colorHex)).frame(width: 8, height: 8)
            Text(name).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

/// A simple wrapping row layout for the legend — tag names vary in count and
/// length, so a fixed HStack would just overflow the 240pt column instead of
/// flowing to a second line.
private struct LegendFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            x += size.width + 10
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + 6
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + 10
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct DayTrack: View {
    let blocks: [TimelineBlock]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                ForEach(0..<3, id: \.self) { tick in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .offset(x: geo.size.width * Double(tick + 1) / 4)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    Rectangle()
                        .fill(Color(hex: block.colorHex))
                        .frame(width: max(1, geo.size.width * block.widthFraction))
                        .offset(x: geo.size.width * block.startFraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

import SwiftUI

/// One row per day, each a 24-hour strip colored by resolved tag (FR-19b).
/// Independent of the tree's filters — always shows full days.
struct TimelinePanel: View {
    static let untaggedLabel = "Untagged / Away"

    let days: [(id: String, label: String, totalSeconds: Int, blocks: [TimelineBlock])]
    let tags: [Tag]

    /// ScrollView is greedy along its scroll axis regardless of any frame
    /// modifier on it or its content, and internally centers content that's
    /// shorter than the space it was given. The only reliable fix is to
    /// measure that space and force the content to fill at least it, so
    /// there's nothing left to center — see the GeometryReader below.
    @State private var scrollAreaHeight: CGFloat = 0
    @State private var selectedDayID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY TIMELINE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            legend

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(days, id: \.id) { day in
                        Button {
                            selectedDayID = day.id
                        } label: {
                            HStack(spacing: 8) {
                            Text(day.label)
                                .font(.system(size: 10))
                                .foregroundStyle(selectedDayID == day.id ? .primary : .tertiary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: 52, alignment: .trailing)
                            DayTrack(blocks: day.blocks)
                                .frame(height: 11)
                            Text(DurationFormat.short(day.totalSeconds))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(
                                selectedDayID == day.id ? Color.accentColor.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(day.label), \(DurationFormat.short(day.totalSeconds)) tracked")
                        .accessibilityAddTraits(selectedDayID == day.id ? .isSelected : [])
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

            if let selectedDay {
                dayDetail(selectedDay)
            }
        }
        .padding(14)
        .onAppear(perform: selectFirstDayIfNeeded)
        .onChange(of: days.map(\.id)) { _ in
            selectFirstDayIfNeeded()
        }
    }

    private var selectedDay: (id: String, label: String, totalSeconds: Int, blocks: [TimelineBlock])? {
        days.first { $0.id == selectedDayID }
    }

    private func selectFirstDayIfNeeded() {
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }
        guard selectedDay == nil else { return }
        selectedDayID = days[0].id
    }

    private func dayDetail(_ day: (id: String, label: String, totalSeconds: Int, blocks: [TimelineBlock])) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            HStack {
                Text(day.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DurationFormat.short(day.totalSeconds))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            Text("TIME BY CATEGORY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)

            ForEach(Array(day.blocks.enumerated()), id: \.offset) { _, block in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: block.colorHex))
                        .frame(width: 7, height: 7)
                    Text(block.label)
                        .font(.system(size: 10))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DurationFormat.short(block.seconds))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                    Text(percentText(for: block, total: day.totalSeconds))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 29, alignment: .trailing)
                }
            }
        }
    }

    private func percentText(for block: TimelineBlock, total: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(block.seconds) / Double(total) * 100).rounded()))%"
    }

    private var legend: some View {
        LegendFlow {
            ForEach(tags) { tag in
                legendItem(name: tag.name, colorHex: tag.colorHex)
            }
            legendItem(name: Self.untaggedLabel, colorHex: TreeBuilder.untaggedColorHex)
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
                // Laid out with a real HStack rather than offset overlays:
                // `.help` derives its tooltip rect from the layout frame, and
                // `.offset` only moves pixels, so offset blocks would all
                // register their tooltip at x = 0 and the first one would win.
                HStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        Rectangle()
                            .fill(Color(hex: block.colorHex))
                            .frame(width: max(1, geo.size.width * block.widthFraction))
                            .help("\(block.label): \(DurationFormat.short(block.seconds))")
                    }
                    Spacer(minLength: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

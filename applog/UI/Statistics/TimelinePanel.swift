import SwiftUI

/// One row per day, each a 24-hour strip colored by resolved tag (FR-19b).
/// Independent of the tree's filters — always shows full days.
struct TimelinePanel: View {
    let days: [(label: String, blocks: [TimelineBlock])]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY TIMELINE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 8) {
                Color.clear.frame(width: 34)
                HStack {
                    Text("12a"); Spacer(); Text("6a"); Spacer(); Text("12p"); Spacer(); Text("6p"); Spacer(); Text("12a")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

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
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                ForEach(DefaultTagPalette.swatches, id: \.name) { swatch in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: swatch.hex)).frame(width: 8, height: 8)
                        Text(swatch.name).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: TreeBuilder.untaggedColorHex)).frame(width: 8, height: 8)
                    Text("Untagged / Away").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
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

import SwiftUI

/// One row per day, each a 24-hour strip colored by resolved tag (FR-19b).
/// Independent of the tree's filters — always shows full days.
struct TimelinePanel: View {
    let days: [(label: String, blocks: [TimelineBlock])]

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

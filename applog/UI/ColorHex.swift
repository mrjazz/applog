import SwiftUI

extension Color {
    /// Parses "#RRGGBB" (used throughout for tag colors, since colors are
    /// stored as hex strings in the database — see design.md §4.1).
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

enum DefaultTagPalette {
    static let swatches: [(name: String, hex: String)] = [
        ("Work", "#0A84FF"),
        ("Browsing", "#F4941C"),
        ("Comms", "#B054E0"),
        ("Writing", "#26A559"),
    ]
}

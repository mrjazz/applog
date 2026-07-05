import SwiftUI
import AppKit

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

    /// Scales this color's RGB components toward black — used to derive a
    /// readable text color from a tag's swatch, since the swatch itself
    /// (e.g. a light orange) often fails 4:1 contrast against white or a
    /// light tint of itself.
    func darkened(by factor: Double) -> Color {
        let ui = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return Color(
            red: ui.redComponent * (1 - factor),
            green: ui.greenComponent * (1 - factor),
            blue: ui.blueComponent * (1 - factor)
        )
    }
}

extension Color {
    /// Matches `--sidebar-bg` / `--toolbar-bg` in docs/design-mockup.html —
    /// a hardcoded pair since the closest system colors don't reproduce the
    /// mockup's light near-white tone.
    static let appSidebarBackground = Color(
        light: Color(hex: "#EEF0F3"), dark: Color(hex: "#1D1D1F")
    )
    static let appToolbarBackground = Color(
        light: Color(hex: "#F6F7F9"), dark: Color(hex: "#232325")
    )

    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
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

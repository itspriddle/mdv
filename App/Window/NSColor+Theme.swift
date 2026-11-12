import AppKit
import PeepCore

extension NSColor {
    /// A theme's page background (`Theme.background`), resolved for the current appearance.
    /// Windows and web views paint their theme's before the page draws (#34: each window's
    /// own), and it follows system appearance changes live.
    static func themeBackground(_ background: ThemeBackground) -> NSColor {
        NSColor(name: "peepThemeBackground") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? background.dark : background.light)
        }
    }

    convenience init(_ color: ThemeColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: 1)
    }
}

import AppKit
import MdvCore

extension NSColor {
    /// The default theme's page background, resolved for the current appearance. Windows and
    /// web views paint it before the page draws, and it follows system appearance changes live.
    static let themeBackground = themeBackground(ThemeRegistry.bundled.defaultTheme.background)

    /// A theme's page background (`Theme.background`), resolved for the current appearance.
    static func themeBackground(_ background: ThemeBackground) -> NSColor {
        NSColor(name: "mdvThemeBackground") { appearance in
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

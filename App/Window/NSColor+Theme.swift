import AppKit
import PeepCore

extension NSColor {
    /// A theme's page background (`Theme.background`), resolved for the current appearance.
    /// Windows and web views paint their theme's before the page draws (#34: each window's
    /// own), and it follows system appearance changes live.
    ///
    /// The name includes both colors: dynamic colors with the same name are equal, so AppKit
    /// would keep showing the old theme's (a window's `backgroundColor` ignores an equal color).
    static func themeBackground(_ background: ThemeBackground) -> NSColor {
        NSColor(name: "peepThemeBackground-\(background.light.hex)-\(background.dark.hex)") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? background.dark : background.light)
        }
    }

    /// A theme's chrome border (`ThemeBackground.chromeBorder`), resolved for the current
    /// appearance: under the titlebar, over the status bar, and between the outline and the page.
    static func themeBorder(_ background: ThemeBackground) -> NSColor {
        let border = background.chromeBorder
        return NSColor(name: "peepThemeBorder-\(border.light.hex)-\(border.dark.hex)") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? border.dark : border.light)
        }
    }

    convenience init(_ color: ThemeColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: 1)
    }
}

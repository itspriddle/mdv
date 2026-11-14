import Observation
import PeepCore
import SwiftUI

/// The theme colors of a window's own chrome: the titlebar (the window background) and the
/// strips `DocumentView` draws around the page (the border under the titlebar, the status bar).
/// The window controller sets `background` with its theme (`applyTheme()`).
@MainActor
@Observable
final class WindowChrome {
    /// The window's theme background.
    var background: ThemeBackground

    init(background: ThemeBackground = ThemeRegistry.bundled.defaultTheme.background) {
        self.background = background
    }

    /// The colors for the appearance a view is drawn in (`colorScheme`, the system's), and the
    /// scheme its controls and text use: the one that contrasts with the background, which
    /// needn't be the system's (a custom theme with one dark background, in Light mode).
    func colors(in colorScheme: ColorScheme) -> Colors {
        let isDark = colorScheme == .dark
        let background = isDark ? background.dark : background.light
        return Colors(
            background: background, border: background.chromeBorder,
            contentScheme: background.isDark ? .dark : .light)
    }

    struct Colors: Equatable {
        let background: ThemeColor
        let border: ThemeColor
        let contentScheme: ColorScheme
    }
}

extension Color {
    init(_ color: ThemeColor) {
        self.init(nsColor: NSColor(color))
    }
}

/// A 1 pt line in the theme's border color, between the page and the window's chrome.
struct ChromeBorder: View {
    let chrome: WindowChrome

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color(chrome.colors(in: colorScheme).border))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

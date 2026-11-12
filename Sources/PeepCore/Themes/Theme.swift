import Foundation

/// A page theme: plain CSS plus the metadata the app needs before the page draws.
///
/// Every page gets the base layer (`ThemeBase`) first; a theme only styles the document
/// (typography, colors, code, tables, highlight tokens). `HTMLDocument` puts the theme in the
/// `mdv-theme` cascade layer (`ThemeLayer`), so whatever its CSS says, it can't remove the base
/// layer's protected rules. Theme CSS is inlined under the page's CSP: no remote `url()`, no
/// `@import`, no web fonts.
public struct Theme: Sendable, Equatable, Identifiable {
    /// Stable identifier, saved in preferences and window state (e.g. `github`).
    public var id: String
    /// The name shown in menus.
    public var displayName: String
    /// The page background per appearance. The app paints windows and the web view's under-page
    /// area with it before the page loads, and the page's own `body` background is generated
    /// from it (`layerCSS`), so the two always agree.
    public var background: ThemeBackground
    /// The theme's own CSS. Dark colors belong under
    /// `@media screen and (prefers-color-scheme: dark)` so paper always prints light.
    public var stylesheet: String
    /// Token colors for highlight.js's `hljs-*` classes, light and dark.
    public var highlightStylesheet: String
    /// Rules for paper only, wrapped in `@media print` after the rest of the theme. The base
    /// layer already handles layout on paper (full width, nothing clipped); this is for looks.
    public var printStylesheet: String?

    public init(
        id: String,
        displayName: String,
        background: ThemeBackground,
        stylesheet: String,
        highlightStylesheet: String = "",
        printStylesheet: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.background = background
        self.stylesheet = stylesheet
        self.highlightStylesheet = highlightStylesheet
        self.printStylesheet = printStylesheet
    }

    /// The theme's complete CSS, unwrapped: the generated page background, then `stylesheet`,
    /// `highlightStylesheet`, and `printStylesheet` (in `@media print`).
    public var css: String {
        var parts = [
            """
            body { background: \(background.light.hex); }
            @media screen and (prefers-color-scheme: dark) {
              body { background: \(background.dark.hex); }
            }
            """,
            stylesheet,
        ]
        if !highlightStylesheet.isEmpty {
            parts.append(highlightStylesheet)
        }
        if let printStylesheet, !printStylesheet.isEmpty {
            parts.append("@media print {\n\(printStylesheet)\n}")
        }
        return parts.joined(separator: "\n")
    }
}

/// A theme's page background for each system appearance.
public struct ThemeBackground: Sendable, Equatable {
    public var light: ThemeColor
    public var dark: ThemeColor

    public init(light: ThemeColor, dark: ThemeColor) {
        self.light = light
        self.dark = dark
    }
}

/// An opaque sRGB color.
public struct ThemeColor: Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A color from a `0xRRGGBB` literal.
    public init(_ rgb: UInt32) {
        self.init(
            red: UInt8(truncatingIfNeeded: rgb >> 16), green: UInt8(truncatingIfNeeded: rgb >> 8),
            blue: UInt8(truncatingIfNeeded: rgb))
    }

    /// CSS hex notation, e.g. `#0d1117`.
    public var hex: String {
        "#" + [red, green, blue].map { $0 < 0x10 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }

    /// Whether the color is dark: its relative luminance (WCAG) is below 0.179, the point where
    /// white and black have equal contrast on it. The app draws its own controls over a theme
    /// background (the render progress indicator, #58) in the matching appearance.
    public var isDark: Bool {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance < 0.179
    }
}

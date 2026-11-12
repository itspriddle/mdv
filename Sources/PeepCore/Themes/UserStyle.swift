/// How wide the reading column may grow (#37): a few presets on top of any theme.
///
/// Text size is not a user style: page zoom (View > Zoom In/Out, `WKWebView.pageZoom`) already
/// reflows the page at a larger text size, so a separate font size control would be a second,
/// subtly different way to do the same thing (settled in #37, recorded in `docs/VISION.md`).
public enum ContentWidth: String, Sendable, CaseIterable {
    /// About 60 to 70 characters per line of body text.
    case narrow
    /// Whatever the theme sets; the user layer adds nothing.
    case theme
    /// Wider than any bundled theme's default.
    case wide
    /// No limit: the column fills the window (the theme's padding stays).
    case full

    /// The persisted and default value.
    public static let `default` = ContentWidth.theme

    /// The menu title.
    public var displayName: String {
        switch self {
        case .narrow: "Narrow"
        case .theme: "Theme Default"
        case .wide: "Wide"
        case .full: "Full Width"
        }
    }

    /// The `max-width` value for the column, or nil to keep the theme's. In `em` of the column's
    /// own font size, so the measure (characters per line) is the same in every theme and at
    /// every zoom level. Constants only: nothing outside this enum reaches the CSS.
    public var cssValue: String? {
        switch self {
        case .narrow: "32em"
        case .theme: nil
        case .wide: "72em"
        case .full: "none"
        }
    }
}

/// The reader's style controls: the `mdv-user` cascade layer (`ThemeLayer.user`), above the
/// theme, so they win over any theme's ordinary rules without specificity games, and below the
/// base layer's protected (`!important`) rules.
///
/// The layer sets the custom property `--mdv-content-width` and applies it to
/// `.markdown-body`'s `max-width`. Themes that limit width elsewhere read
/// `var(--mdv-content-width, <their default>)` there. Everything is screen only, so paper
/// always gets the full width (the base layer's print rules force it too).
public struct UserStyle: Sendable, Equatable {
    /// The custom property themes read for the column width.
    public static let contentWidthProperty = "--mdv-content-width"

    public var contentWidth: ContentWidth

    public init(contentWidth: ContentWidth = .default) {
        self.contentWidth = contentWidth
    }

    /// Nothing changed: every value is the theme's.
    public static let themeDefaults = UserStyle()

    /// The layer's rules, unwrapped. Empty when everything is the theme's.
    public var css: String {
        guard let width = contentWidth.cssValue else {
            return ""
        }
        return """
            @media screen {
              :root { \(Self.contentWidthProperty): \(width); }
              .markdown-body { max-width: var(\(Self.contentWidthProperty)); }
            }
            """
    }

    /// The text of the page's `<style id="mdv-user">` element. An in-place change replaces that
    /// element's text with this.
    public var layerCSS: String {
        ThemeLayer.user.wrap(css)
    }
}

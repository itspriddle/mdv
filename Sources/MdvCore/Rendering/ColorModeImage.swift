/// GitHub's theme-specific images: a URL ending in `#gh-dark-mode-only` is shown only in dark
/// mode, and `#gh-light-mode-only` only in light mode. `DefaultTheme` hides the other one with
/// `img[src$="#..."]` selectors (and the matching placeholder class), so it follows live
/// appearance changes without a re-render; print always shows the light variant.
public enum ColorModeImage: String, Sendable, CaseIterable {
    case dark
    case light

    /// The URL fragment GitHub uses, without `#` (also the placeholder's class name).
    public var fragment: String { "gh-\(rawValue)-mode-only" }

    /// The variant `source` asks for, by its exact (case-sensitive) suffix, as GitHub's CSS
    /// matches it.
    public init?(source: String) {
        guard let mode = Self.allCases.first(where: { source.hasSuffix("#" + $0.fragment) }) else {
            return nil
        }
        self = mode
    }
}

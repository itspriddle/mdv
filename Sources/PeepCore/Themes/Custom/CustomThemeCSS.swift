import Foundation

/// Checks a custom theme's CSS (#35) before it is inlined in the `peep-theme` layer.
///
/// The page's CSP already blocks every load a stylesheet could start (`default-src 'none'`,
/// images from `peep-doc:` and `data:` only), so this is the second, independent line: a theme
/// that tries to load anything is rejected with a reason the picker shows, rather than
/// silently styled differently than its author expects. The rules:
/// - no `@import`;
/// - `url()`, and strings in `image-set()`, `-webkit-image-set()`, `image()`, `src()`, and
///   `cross-fade()`, must be `data:image/…` URLs;
/// - no `expression()`;
/// - `{}`, `()`, and `[]` nest properly, comments and strings are closed. A stray `}` would
///   end the `@layer peep-theme { … }` block the theme is wrapped in, and an unclosed `{` or
///   comment would swallow its end.
///
/// The scanner follows CSS Syntax Level 3 tokenizing where it matters: comments and strings
/// are skipped, and escapes in names are decoded, so `@\69mport` and `u\72l(` are caught.
/// Names compare ASCII case-insensitively, as CSS does. `</style` is handled when the CSS is
/// inlined (`ThemeLayer.inlineSafe`), not here.
public enum CustomThemeCSS {
    /// Functions whose string arguments are URLs.
    static let urlStringFunctions: Set<String> = [
        "url", "src", "image", "image-set", "-webkit-image-set", "cross-fade", "-webkit-cross-fade",
    ]

    /// Throws the first problem found in `css`, scanning from the start.
    public static func validate(_ css: String) throws(CustomThemeProblem) {
        var scanner = CustomThemeCSSScanner(bytes: Array(css.utf8))
        try scanner.run()
    }

    /// Whether `value` (a `url()` or string argument, escapes decoded) is an allowed URL: a
    /// `data:` URL of an image type. SVG images are fine: WebKit loads images in CSS with
    /// scripts and external resources off.
    static func isAllowedURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .cssWhitespace)
        return asciiLowercased(String(trimmed.prefix(11))) == "data:image/"
    }

    /// `text` with only ASCII letters lowercased (CSS is ASCII case-insensitive; full Unicode
    /// lowercasing would turn the Kelvin sign into `k`).
    static func asciiLowercased(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.unicodeScalars.map { scalar in
                    (0x41...0x5A).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x20) ?? scalar : scalar
                }))
    }
}

extension CharacterSet {
    /// CSS whitespace: space, tab, and line breaks.
    static let cssWhitespace = CharacterSet(charactersIn: " \t\n\r\u{0C}")
}

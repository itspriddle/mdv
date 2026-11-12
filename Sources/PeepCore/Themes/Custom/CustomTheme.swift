import Foundation

/// A custom theme (#35): one `.css` file in the Themes folder, turned into a `Theme`.
///
/// The file is plain CSS. It may start with a header comment that declares metadata; every
/// key is optional:
///
/// ```css
/// /* mdv-theme
///    name: Solarized Light
///    background: #fdf6e3
///    background-dark: #002b36
///    extends: github
/// */
/// ```
///
/// - The header is a `/* … */` comment before anything else in the file (whitespace aside)
///   whose first line is `mdv-theme`. Each other non-blank line is `key: value`; a leading
///   `*` (comment decoration) is ignored. Keys are case-insensitive; unknown or repeated keys
///   are errors, so a typo doesn't go unnoticed.
/// - `name`: the picker's name. Default: the file name without `.css`.
/// - `background` / `background-dark`: the page background in light and dark appearance, as
///   `#rgb` or `#rrggbb`. The app paints the window with it before the page draws, and the
///   page's `body` background is generated from it. `background-dark` defaults to
///   `background` (a theme with one background looks the same in both appearances); with
///   neither, the extended theme's backgrounds, else the default theme's.
/// - `extends`: a bundled theme id (`github`, `document`, `serif`). Its CSS goes first in the
///   theme layer and this file's CSS after it, so the file only overrides. Without it the
///   theme starts from the base layer alone: browser defaults plus the rules mdv's features
///   need.
///
/// The id is `custom:<file name>` (e.g. `custom:solarized.css`), a namespace no bundled id
/// uses, so a custom theme never shadows a bundled one. The CSS must pass `CustomThemeCSS`.
public enum CustomTheme {
    /// The id prefix of every custom theme.
    public static let idPrefix = "custom:"
    /// The header comment's marker line.
    public static let headerMarker = "mdv-theme"
    /// The longest display name; longer names are cut with an ellipsis.
    public static let maximumNameLength = 64

    /// The theme in `css`, read from the file `fileName`. `base` supplies the themes `extends`
    /// may name and the fallback background.
    public static func make(
        fileName: String, css: String, base: ThemeRegistry = .bundled
    ) throws(CustomThemeProblem) -> Theme {
        let header = try Header.parse(css)
        try CustomThemeCSS.validate(css)

        var extended: Theme?
        if let id = header.extends {
            guard base.contains(id: id) else {
                throw .unknownBaseTheme(sanitizedName(String(id.prefix(40))) ?? "")
            }
            extended = base.theme(id: id)
        }
        let fallback = (extended ?? base.defaultTheme).background
        let light = header.background ?? fallback.light
        let dark = header.backgroundDark ?? header.background ?? fallback.dark

        return Theme(
            id: id(forFileName: fileName),
            displayName: header.name ?? displayName(forFileName: fileName),
            background: ThemeBackground(light: light, dark: dark),
            stylesheet: [extended.map(Self.bodyCSS), css].compactMap(\.self).joined(separator: "\n"))
    }

    /// The id for the theme in `fileName`.
    public static func id(forFileName fileName: String) -> String {
        idPrefix + fileName
    }

    /// The name for a theme without a `name:`: the file name without its extension, cleaned
    /// up (`sanitizedName`), or "Untitled Theme".
    public static func displayName(forFileName fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return sanitizedName(stem) ?? "Untitled Theme"
    }

    /// `name` fit for a menu: control, format (bidi overrides), and line separator characters
    /// become spaces, runs of whitespace collapse, and it is trimmed and cut to
    /// `maximumNameLength` characters. Nil when nothing is left.
    public static func sanitizedName(_ name: String) -> String? {
        let cleaned = String(
            String.UnicodeScalarView(
                name.unicodeScalars.map { scalar in
                    switch scalar.properties.generalCategory {
                    case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned,
                        .privateUse:
                        " "
                    default:
                        scalar
                    }
                }))
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return nil
        }
        let joined = words.joined(separator: " ")
        guard joined.count > maximumNameLength else {
            return joined
        }
        return joined.prefix(maximumNameLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A bundled theme's CSS without its generated background (the custom theme has its
    /// own): stylesheet, token colors, and print rules, in `Theme.css` order.
    static func bodyCSS(_ theme: Theme) -> String {
        var parts = [theme.stylesheet]
        if !theme.highlightStylesheet.isEmpty {
            parts.append(theme.highlightStylesheet)
        }
        if let print = theme.printStylesheet, !print.isEmpty {
            parts.append("@media print {\n\(print)\n}")
        }
        return parts.joined(separator: "\n")
    }

    /// The header comment's values.
    struct Header: Equatable {
        var name: String?
        var background: ThemeColor?
        var backgroundDark: ThemeColor?
        var extends: String?

        /// The header at the start of `css`, or an empty header when the file doesn't start
        /// with one.
        static func parse(_ css: String) throws(CustomThemeProblem) -> Header {
            var header = Header()
            let leading = css.prefix { $0.isWhitespace }
            let afterWhitespace = css[leading.endIndex...]
            guard afterWhitespace.hasPrefix("/*") else {
                return header
            }
            let rest = afterWhitespace.dropFirst(2)
            // An unclosed comment is reported by the CSS check.
            guard let end = rest.range(of: "*/") else {
                return header
            }
            let body = rest[..<end.lowerBound]
            let firstLine = leading.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
            var lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated()
                .map { (number: firstLine + $0.offset, text: clean($0.element)) }
                .drop { $0.text.isEmpty }
            guard let marker = lines.first, marker.text.lowercased() == headerMarker else {
                return header
            }
            lines = lines.dropFirst()

            var seen: Set<String> = []
            for line in lines where !line.text.isEmpty {
                guard let colon = line.text.firstIndex(of: ":") else {
                    throw .invalidHeader(line: line.number, message: "Expected “key: value” in the header")
                }
                let key = line.text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line.text[line.text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard seen.insert(key).inserted else {
                    throw .invalidHeader(line: line.number, message: "“\(clip(key))” appears twice in the header")
                }
                try header.set(key, to: value, line: line.number)
            }
            return header
        }

        /// Sets `key` (lowercased) from a header line.
        private mutating func set(_ key: String, to value: String, line: Int) throws(CustomThemeProblem) {
            switch key {
            case "name":
                guard let name = CustomTheme.sanitizedName(value) else {
                    throw .invalidHeader(line: line, message: "The name is empty")
                }
                self.name = name
            case "background", "background-dark":
                guard let color = ThemeColor(hex: value) else {
                    throw .invalidHeader(
                        line: line, message: "\(key) must be a hex color like #ffffff, not “\(Self.clip(value))”")
                }
                if key == "background" {
                    background = color
                } else {
                    backgroundDark = color
                }
            case "extends":
                extends = value
            default:
                throw .invalidHeader(line: line, message: "Unknown header key “\(Self.clip(key))”")
            }
        }

        /// A header line without surrounding whitespace and comment decoration (`*`).
        private static func clean(_ line: Substring) -> String {
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("*") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return text
        }

        /// `text` short and printable enough to quote in an error message.
        private static func clip(_ text: String) -> String {
            sanitizedName(String(text.prefix(40))) ?? ""
        }
    }
}

extension ThemeColor {
    /// A color from CSS hex notation, `#rgb` or `#rrggbb` (case-insensitive). Nil for
    /// anything else, including named colors and alpha.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else {
            return nil
        }
        let digits = hex.dropFirst()
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else {
            return nil
        }
        if digits.count == 3 {
            let red = (value >> 8) & 0xF
            let green = (value >> 4) & 0xF
            let blue = value & 0xF
            self.init((red * 0x11) << 16 | (green * 0x11) << 8 | blue * 0x11)
        } else {
            self.init(value)
        }
    }
}

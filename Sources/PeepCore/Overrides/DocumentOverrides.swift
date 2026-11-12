/// Per-document presentation choices read from the `peep:` mapping of YAML frontmatter (#54):
///
/// ```yaml
/// ---
/// peep:
///   flavor: commonmark
///   theme: serif
///   wikilinks: true
/// ---
/// ```
///
/// **The security boundary.** A document is untrusted input, so it can only choose among
/// presentation options: the three keys above, nothing else. It can never turn on the custom
/// preprocessor, turn off sanitizing, allow remote images, or change any other `RenderOptions`
/// setting. There is no generic mapping from frontmatter to options: each key is read here into
/// a typed field, and `RenderOptions.applying(_:)` is the one place a field changes a render.
/// Anything else under `peep:` (including the names of safety settings) is ignored and reported
/// in `ignored`; a wrong value never fails the render or shows an error page.
///
/// - `flavor`: a registered flavor id (`FlavorRegistry.bundled`), compared lowercased. Applied in
///   PeepCore before the body is parsed (pipeline stage 3), so `peep --html` gets it too, and it
///   beats `RenderOptions.flavor` (the app's default). An unknown id is ignored, so the document
///   renders with `RenderOptions.flavor`, not the registry's default.
/// - `theme`: a theme id, bundled (`github`, compared lowercased) or `custom:<file name>` (kept
///   as written). Not resolved here: the app resolves it in its theme registry like a window's
///   pick (`ThemeSettings`), and `peep --html` in `ThemeRegistry.bundled`. It is only ever looked
///   up by id, never read as a path.
/// - `wikilinks`: `true` or `false`, turning wiki links (#53) on or off for this document. It beats
///   Settings' built-in preprocessors in both directions (`RenderOptions.applying(_:)`).
///
/// Only YAML frontmatter is read. TOML frontmatter (`+++`) isn't parsed at all (no TOML parser,
/// by decision), so a TOML `[peep]` table is reported as ignored rather than silently dropped.
public struct DocumentOverrides: Sendable, Equatable {
    /// The top-level frontmatter key that holds the overrides.
    public static let frontmatterKey = "peep"

    /// The keys a document can set under `peep:`.
    public enum Key: String, CaseIterable, Sendable {
        case flavor
        case theme
        case wikiLinks = "wikilinks"
    }

    /// No overrides (a document without a `peep:` mapping).
    public static let none = DocumentOverrides()

    /// The longest theme id read (the app's `isPlausibleThemeID` limit).
    static let maximumThemeIDLength = 256

    /// A registered flavor id, lowercased.
    public var flavor: String?
    /// A theme id, not yet resolved: bundled ids lowercased, `custom:` ids as written.
    public var theme: String?
    /// Turns wiki links on or off for this document (#53).
    public var wikiLinks: Bool?
    /// What was ignored under `peep:` and why, in document order, for diagnostics.
    public var ignored: [IgnoredOverride]

    public init(flavor: String? = nil, theme: String? = nil, wikiLinks: Bool? = nil, ignored: [IgnoredOverride] = []) {
        self.flavor = flavor
        self.theme = theme
        self.wikiLinks = wikiLinks
        self.ignored = ignored
    }

    /// Reads the `peep:` mapping of `frontmatter`. A missing, null, or unparsed (malformed YAML)
    /// block gives no overrides; flavor ids are checked against `FlavorRegistry.bundled`.
    public init(frontmatter: Frontmatter?) {
        self.init()
        guard let frontmatter else {
            return
        }
        if frontmatter.format == .toml {
            if Self.mentionsOverrides(toml: frontmatter.raw) {
                ignored.append(IgnoredOverride(key: Self.frontmatterKey, reason: .tomlFrontmatter))
            }
            return
        }
        guard let value = frontmatter.values?[Self.frontmatterKey] else {
            return
        }
        switch value {
        case .null:
            return
        case .table(let entries):
            // Yams rejects duplicate keys, so each key appears once.
            for entry in entries {
                read(key: entry.key, value: entry.value)
            }
        case .scalar, .array:
            ignored.append(IgnoredOverride(key: Self.frontmatterKey, reason: .wrongType(expected: .mapping)))
        }
    }

    /// Whether nothing is overridden (ignored keys don't count).
    public var isEmpty: Bool {
        flavor == nil && theme == nil && wikiLinks == nil
    }

    // MARK: Reading

    private mutating func read(key: String, value: FrontmatterValue) {
        guard let known = Key(rawValue: key) else {
            ignored.append(IgnoredOverride(key: Self.path(key), reason: .unknownKey))
            return
        }
        if case .null = value {
            return  // `theme: ~` sets nothing.
        }
        let path = Self.path(key)
        switch known {
        case .flavor:
            guard let text = Self.text(value) else {
                ignored.append(IgnoredOverride(key: path, reason: .wrongType(expected: .string)))
                return
            }
            let id = text.lowercased()
            guard FlavorRegistry.bundled.contains(id: id) else {
                ignored.append(IgnoredOverride(key: path, reason: .unknownFlavor(text)))
                return
            }
            flavor = id
        case .theme:
            guard let text = Self.text(value) else {
                ignored.append(IgnoredOverride(key: path, reason: .wrongType(expected: .string)))
                return
            }
            guard let id = Self.themeID(text) else {
                ignored.append(IgnoredOverride(key: path, reason: .invalidThemeID))
                return
            }
            theme = id
        case .wikiLinks:
            guard let flag = Self.boolean(value) else {
                ignored.append(IgnoredOverride(key: path, reason: .wrongType(expected: .boolean)))
                return
            }
            wikiLinks = flag
        }
    }

    private static func path(_ key: String) -> String {
        "\(frontmatterKey).\(key)"
    }

    /// A non-blank scalar, trimmed.
    private static func text(_ value: FrontmatterValue) -> String? {
        guard case .scalar(let raw) = value else {
            return nil
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// YAML 1.2 core booleans: `true`/`false` in lower, title, or upper case.
    private static func boolean(_ value: FrontmatterValue) -> Bool? {
        switch text(value) {
        case "true", "True", "TRUE":
            true
        case "false", "False", "FALSE":
            false
        default:
            nil
        }
    }

    /// `text` as a theme id: at most `maximumThemeIDLength` characters with no control
    /// characters; bundled ids lowercased, `custom:<file name>` kept as written (file names are
    /// case-sensitive), with a non-empty file name.
    static func themeID(_ text: String) -> String? {
        guard text.count <= maximumThemeIDLength,
            !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else {
            return nil
        }
        let customPrefix = "custom:"
        if text.hasPrefix(customPrefix) {
            return text.count > customPrefix.count ? text : nil
        }
        return text.lowercased()
    }

    /// Whether TOML frontmatter looks like it sets Peep options: an `[peep]` table, or a `peep`
    /// key (`peep.theme = …`, `peep = { … }`).
    static func mentionsOverrides(toml raw: String) -> Bool {
        raw.split(whereSeparator: \.isNewline).contains { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                let name = line.dropFirst().prefix { $0 != "]" }.trimmingCharacters(in: .whitespaces)
                return name == frontmatterKey || name.hasPrefix("\(frontmatterKey).")
            }
            return line.hasPrefix("\(frontmatterKey).") || line.hasPrefix("\(frontmatterKey) ")
                || line.hasPrefix("\(frontmatterKey)=")
        }
    }
}

/// Something under `peep:` that a render ignored, and why (`DocumentOverrides.ignored`).
public struct IgnoredOverride: Sendable, Equatable, CustomStringConvertible {
    public enum ValueType: String, Sendable, Equatable {
        case mapping
        case string
        case boolean
    }

    public enum Reason: Sendable, Equatable {
        /// Not a key documents can set: only `flavor`, `theme`, and `wikilinks` are. Safety
        /// settings (`sanitize`, remote images, the custom preprocessor, ...) land here.
        case unknownKey
        /// The value isn't of the type the key takes.
        case wrongType(expected: ValueType)
        /// `flavor` names a flavor that isn't registered (the value as written).
        case unknownFlavor(String)
        /// `theme` is too long, has control characters, or is `custom:` without a file name.
        case invalidThemeID
        /// TOML frontmatter sets Peep options; only YAML frontmatter is read.
        case tomlFrontmatter
    }

    /// Where it was: `peep.<key>`, or `peep` for the whole block.
    public var key: String
    public var reason: Reason

    public init(key: String, reason: Reason) {
        self.key = key
        self.reason = reason
    }

    /// A one-line explanation for diagnostics. Untrusted text in it is shortened.
    public var description: String {
        let key = Self.shortened(key)
        switch reason {
        case .unknownKey:
            let keys = DocumentOverrides.Key.allCases.map(\.rawValue).joined(separator: ", ")
            return "\(key) isn't a setting a document can change (only \(keys)); ignored."
        case .wrongType(let expected):
            return "\(key) must be a \(expected.rawValue); ignored."
        case .unknownFlavor(let value):
            let flavors = FlavorRegistry.bundled.flavors.map(\.id).joined(separator: ", ")
            return "\(key) \"\(Self.shortened(value))\" isn't a flavor (\(flavors)); ignored."
        case .invalidThemeID:
            return "\(key) isn't a valid theme id; ignored."
        case .tomlFrontmatter:
            return "\(key) settings in TOML frontmatter aren't read; use YAML frontmatter (---); ignored."
        }
    }

    private static func shortened(_ text: String) -> String {
        text.count > 64 ? "\(text.prefix(64))…" : text
    }
}

extension RenderOptions {
    /// These options with a document's overrides applied (#54): the one place frontmatter changes
    /// a render, and it changes only presentation. The flavor, when the document names a
    /// registered one; otherwise `flavor` stays (the reader's default). Every safety setting
    /// (sanitizing, remote images, `linkRoot`, ...) is untouched by construction. The custom
    /// preprocessor isn't a `RenderOptions` setting at all: it runs before frontmatter is read.
    ///
    /// A key in `pinnedOverrides` (#64) is skipped: the caller's own setting for it stays, as an
    /// explicit `peep --flavor` beats `peep.flavor`. The theme isn't applied here at all (callers
    /// resolve `overrides.theme`), so pinning `.theme` changes nothing in PeepCore.
    public func applying(_ overrides: DocumentOverrides) -> RenderOptions {
        guard appliesDocumentOverrides else {
            return self
        }
        var options = self
        if !pinnedOverrides.contains(.flavor), let id = overrides.flavor, FlavorRegistry.bundled.contains(id: id) {
            options.flavor = FlavorRegistry.bundled.flavor(id: id)
        }
        if !pinnedOverrides.contains(.wikiLinks), let wikiLinks = overrides.wikiLinks {
            if wikiLinks {
                options.builtInPreprocessors.insert(.wikiLinks)
            } else {
                options.builtInPreprocessors.remove(.wikiLinks)
            }
        }
        return options
    }
}

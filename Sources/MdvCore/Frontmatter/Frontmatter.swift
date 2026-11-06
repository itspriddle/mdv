import Foundation

/// A metadata block at the very start of a Markdown file: YAML between `---` fences (closed by
/// `---` or `...`), or TOML between `+++` fences.
///
/// Frontmatter is untrusted input. Values are only ever written to HTML escaped, and YAML is parsed
/// with size, alias, and complexity limits (see `YAMLFrontmatter`).
public struct Frontmatter: Sendable, Equatable {
    public enum Format: Sendable, Equatable {
        case yaml
        case toml
    }

    public var format: Format
    /// The text between the fences, verbatim (fences excluded, line endings kept).
    public var raw: String
    /// Top-level keys in document order. `nil` when the block was not parsed: TOML (no parser in
    /// M1), or YAML that is malformed, oversized, or too complex (see `error`).
    public var entries: [FrontmatterEntry]?
    /// Why YAML could not be parsed. The block is still stripped from the rendered body.
    public var error: String?
    /// Lines the block occupies in the source file, fences included. The Markdown body starts on
    /// line `lineCount + 1`, and `MarkdownParser.parse(_:lineOffset:)` takes this as its offset.
    public var lineCount: Int

    public init(
        format: Format,
        raw: String,
        entries: [FrontmatterEntry]? = nil,
        error: String? = nil,
        lineCount: Int
    ) {
        self.format = format
        self.raw = raw
        self.entries = entries
        self.error = error
        self.lineCount = lineCount
    }

    /// Top-level values by key. For a duplicated key, the last value wins.
    public var values: [String: FrontmatterValue]? {
        entries.map { entries in
            Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// The `title` value, when it is a non-blank scalar.
    public var title: String? {
        guard case .scalar(let text) = values?["title"] else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A key and its value in a frontmatter mapping.
public struct FrontmatterEntry: Sendable, Equatable {
    public var key: String
    public var value: FrontmatterValue

    public init(key: String, value: FrontmatterValue) {
        self.key = key
        self.value = value
    }
}

/// A frontmatter value. Scalars keep their YAML text (after unquoting) rather than being typed, so
/// `version: 1.10` displays as written.
public indirect enum FrontmatterValue: Sendable, Equatable {
    /// `~`, `null`, or an empty value.
    case null
    case scalar(String)
    case array([FrontmatterValue])
    /// A nested mapping, keys in document order.
    case table([FrontmatterEntry])
}

/// How `HTMLRenderer` shows detected frontmatter.
public enum FrontmatterDisplay: Sendable, Equatable {
    /// Stripped from the output (the default).
    case hidden
    /// Rendered before the body: parsed YAML as a table, TOML as a code block.
    case table
}

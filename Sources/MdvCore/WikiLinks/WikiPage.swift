/// The page a wiki link names (`Page Name` in `[[Page Name#Heading|label]]`), and the naming rule
/// that matches it to a file (#53).
///
/// The rule follows GitHub wikis: a page's file is its name with spaces as hyphens plus a
/// Markdown extension (`Page Name` → `Page-Name.md`). Matching is case-insensitive, and a space
/// and a hyphen are the same character, so `[[page name]]`, `[[Page-Name]]`, and `[[PAGE NAME]]`
/// all name `Page-Name.md`, and also `Page Name.md` (how note apps name files). A name that ends
/// in a Markdown extension (`[[Page.md]]`) names that file. Only Markdown files
/// (`LinkPolicy.markdownExtensions`) are pages.
///
/// A name may have folders (`[[guides/Setup]]`): the file must be in a folder of that name (also
/// case-insensitive, spaces as hyphens), at any depth. A name with an empty folder, `.`, or
/// `..` (so `/Page` and `../Page` too), a control character, or a part longer than a file name
/// can be (255 UTF-8 bytes) names no page, so the link shows as missing.
public struct WikiPage: Sendable, Hashable {
    /// The name as written, trimmed (`guides/Setup`).
    public let name: String
    /// The folders before the page's own name (`["guides"]`), trimmed; empty for most links.
    public let folders: [String]
    /// The page's own name, the last part (`Setup`), trimmed.
    public let fileName: String

    /// At most this many parts (folders plus the name).
    static let maximumParts = 32
    /// A part longer than this (UTF-8 bytes) can't be a file name on macOS.
    static let maximumPartBytes = 255

    /// The page `name` names, or `nil` when it names none (see the type's rules).
    public init?(_ name: String) {
        let trimmed = name.trimmingWikiWhitespace()
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map {
            String($0).trimmingWikiWhitespace()
        }
        guard !trimmed.isEmpty, parts.count <= Self.maximumParts, let last = parts.last,
            parts.allSatisfy(Self.isValidPart)
        else {
            return nil
        }
        self.name = trimmed
        self.folders = Array(parts.dropLast())
        self.fileName = last
    }

    /// Whether the file named `candidate` (a name, not a path) is this page's file.
    public func matches(fileName candidate: String) -> Bool {
        guard let candidateExtension = Self.markdownExtension(of: candidate) else {
            return false
        }
        if Self.markdownExtension(of: fileName) != nil {
            return Self.key(candidate) == Self.key(fileName)
        }
        let stem = candidate.dropLast(candidateExtension.count + 1)
        return Self.key(String(stem)) == Self.key(fileName)
    }

    /// Whether the folder path `candidate` (folder names from the search root down to the file's
    /// folder) ends with this page's folders. Always true for a name without folders.
    public func matchesFolders(endingWith candidate: [String]) -> Bool {
        guard candidate.count >= folders.count else {
            return false
        }
        return zip(candidate.suffix(folders.count), folders).allSatisfy { Self.key($0) == Self.key($1) }
    }

    /// Whether the folder named `candidate` is `folders[index]`.
    public func matchesFolder(_ candidate: String, at index: Int) -> Bool {
        folders.indices.contains(index) && Self.key(candidate) == Self.key(folders[index])
    }

    /// The comparison key for a name: spaces as hyphens, lowercased. Swift string equality is
    /// canonical, so precomposed and decomposed accents (as file systems may store them) match.
    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "-").lowercased()
    }

    /// Whether `name` has a Markdown extension (`LinkPolicy.markdownExtensions`).
    static func isMarkdownFileName(_ name: String) -> Bool {
        markdownExtension(of: name) != nil
    }

    /// The Markdown extension `name` ends with (as written), or `nil`.
    private static func markdownExtension(of name: String) -> Substring? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return nil
        }
        let pathExtension = name[name.index(after: dot)...]
        return LinkPolicy.markdownExtensions.contains(pathExtension.lowercased()) ? pathExtension : nil
    }

    private static func isValidPart(_ part: String) -> Bool {
        !part.isEmpty && part != "." && part != ".." && part.utf8.count <= maximumPartBytes
            && !part.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

extension StringProtocol {
    /// Trimmed of spaces and tabs, the only whitespace a single line of text can hold.
    func trimmingWikiWhitespace() -> String {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        guard let first = firstIndex(where: { !isBlank($0) }), let last = lastIndex(where: { !isBlank($0) }) else {
            return ""
        }
        return String(self[first...last])
    }
}

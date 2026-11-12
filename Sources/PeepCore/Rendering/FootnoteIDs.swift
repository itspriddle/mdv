/// Element ids for a document's footnotes, unique among themselves and against heading slugs.
///
/// Footnote ids follow GitHub: `fn-KEY` on the note, `fnref-KEY` on its first reference and
/// `fnref-KEY-N` on the Nth, and `footnote-label` on the section's heading, where `KEY` is the
/// label percent-encoded like an `href` (`houdini_escape_href`). github.com keeps them apart from
/// heading ids with a `user-content-` prefix and a per-render nonce; Peep writes neither, so they
/// can collide: `# fn 1` slugs to `fn-1`, the id of footnote `[^1]`; footnote `[^a]` referenced
/// twice has `fnref-a-2`, which is also the first reference id of `[^a-2]`; and labels `a b` and
/// `a%20b` encode to the same key.
///
/// Heading slugs win every collision: readers link to them by hand and they must match GitHub's,
/// while footnote ids are only linked from the renderer's own references and back-links, so
/// renaming one never breaks a link. A footnote whose ids aren't all free gets the first `-N`
/// suffix on its key that frees them (`[^1]` beside `# fn 1` becomes `fn-1-1`), in footnote
/// order. The section heading takes the first free of `footnote-label`, `footnote-label-1`, ...
struct FootnoteIDs {
    /// The id key per footnote number. References without an entry fall back to their label.
    private var keys: [Int: String] = [:]
    /// The id of the footnotes section's heading, which references point at with
    /// `aria-describedby`.
    private(set) var sectionLabel = "footnote-label"

    init() {}

    /// Assigns ids to the footnote definitions among `root`'s children (cmark moves them to the
    /// end of the document), avoiding every id in `reserved`.
    init(for root: MarkdownNode, reserving reserved: Set<String>) {
        var taken = reserved
        for child in root.children {
            guard case .footnoteDefinition(let label, let number, let referenceCount) = child.kind else {
                continue
            }
            let base = Self.percentEncoded(label)
            var key = base
            var ids = Self.ids(forKey: key, referenceCount: referenceCount)
            var suffix = 0
            while !ids.allSatisfy({ !taken.contains($0) }) {
                suffix += 1
                key = "\(base)-\(suffix)"
                ids = Self.ids(forKey: key, referenceCount: referenceCount)
            }
            taken.formUnion(ids)
            keys[number] = key
        }
        guard !keys.isEmpty else {
            return
        }
        var suffix = 0
        while taken.contains(sectionLabel) {
            suffix += 1
            sectionLabel = "footnote-label-\(suffix)"
        }
    }

    /// The id key for footnote `number` (the part after `fn-`/`fnref-`), already
    /// percent-encoded; write it with `HTMLOutput.url`, which leaves it unchanged apart from
    /// entity-escaping `&` and `'`.
    func key(number: Int, label: String) -> String {
        keys[number] ?? Self.percentEncoded(label)
    }

    /// Every id a footnote with this key writes.
    private static func ids(forKey key: String, referenceCount: Int) -> [String] {
        ["fn-\(key)", "fnref-\(key)"] + (1..<max(referenceCount, 1)).map { "fnref-\(key)-\($0 + 1)" }
    }

    /// `label` percent-encoded the way `HTMLOutput.url` encodes it, without the entity escaping:
    /// the id value an HTML parser reads back from the attribute.
    static func percentEncoded(_ label: String) -> String {
        var key = ""
        key.reserveCapacity(label.utf8.count)
        for byte in label.utf8 {
            if HTMLOutput.isHrefSafe(byte) || byte == UInt8(ascii: "&") || byte == UInt8(ascii: "'") {
                key.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                key += "%"
                key.unicodeScalars.append(hexDigits[Int(byte >> 4)])
                key.unicodeScalars.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return key
    }

    private static let hexDigits = Array("0123456789ABCDEF".unicodeScalars)
}

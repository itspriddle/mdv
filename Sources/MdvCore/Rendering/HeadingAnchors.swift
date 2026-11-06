import Foundation

/// GitHub-compatible heading slugs (#6).
///
/// Matches the ids github.com gives headings (minus its `user-content-` prefix), verified against
/// GitHub's renderer; see `HeadingSlugTests` for the cases and how they were checked.
enum HeadingSlug {
    /// The slug for a heading's text, before de-duplication: lowercase each scalar (full Unicode
    /// mapping, no context rules, like Ruby's `downcase`), keep word characters and `-`, turn each
    /// ASCII space into `-`, and drop everything else (punctuation, symbols, emoji, tabs, other
    /// whitespace). Word characters follow Unicode's `\w`: Alphabetic, marks, decimal digits,
    /// connector punctuation (`_`), and join controls (ZWJ/ZWNJ).
    static func slug(for text: String) -> String {
        var slug = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            for lower in scalar.properties.lowercaseMapping.unicodeScalars {
                if lower == " " {
                    slug.append("-")
                } else if lower == "-" || isWordCharacter(lower) {
                    slug.append(lower)
                }
            }
        }
        return String(slug)
    }

    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isAlphabetic || properties.isJoinControl {
            return true
        }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .connectorPunctuation:
            return true
        default:
            return false
        }
    }
}

/// Hands out unique slugs in document order, the way GitHub de-duplicates them.
///
/// A slug not used yet is taken as is. A repeat gets the first free `-N` suffix, counting up from
/// that slug's last suffix, so `A`, `A-1`, `A` gives `a`, `a-1`, `a-2`.
///
/// An empty slug (a heading with no word characters) is always suffixed, starting at `-0`. GitHub
/// gives the first such heading `id=""`, which is unusable; later ones get `-1`, `-2`, ... on both.
struct HeadingSlugger {
    private var used: Set<String> = []
    private var nextSuffix: [String: Int] = [:]

    mutating func uniqueSlug(for text: String) -> String {
        let base = HeadingSlug.slug(for: text)
        if !base.isEmpty, used.insert(base).inserted {
            return base
        }
        var suffix = nextSuffix[base] ?? (base.isEmpty ? 0 : 1)
        while used.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        nextSuffix[base] = suffix + 1
        let slug = "\(base)-\(suffix)"
        used.insert(slug)
        return slug
    }
}

/// A heading's text, gathered like the DOM `textContent` GitHub slugs.
///
/// Text and code spans count; raw HTML tags and image alt text do not. Breaks are newlines in the
/// slug source (so they vanish from the slug, as on GitHub) and spaces in the display text.
/// Footnote references contribute their number to the slug only. Emoji shortcodes show their
/// character but slug as the shortcode text.
struct HeadingText {
    var display = ""
    var slugSource = ""

    init(_ heading: MarkdownNode) {
        var stack = heading.children.reversed() as [MarkdownNode]
        while let node = stack.popLast() {
            switch node.kind {
            case .text(let literal), .code(let literal):
                display += literal
                slugSource += literal
            case .emoji(let shortcode, let character):
                // GitHub slugs the shortcode as written (`:tada: Release` -> `tada-release`).
                display += character
                slugSource += ":\(shortcode):"
            case .softBreak, .lineBreak:
                display += " "
                slugSource += "\n"
            case .footnoteReference(_, let number, _):
                slugSource += String(number)
            case .htmlInline, .image:
                break
            default:
                stack.append(contentsOf: node.children.reversed())
            }
        }
    }
}

/// A token produced by `HTMLTokenizer`.
enum HTMLToken: Equatable {
    /// Character data exactly as written (character references are not decoded).
    case text(String)
    case startTag(HTMLStartTag)
    case endTag(name: String)
    /// A comment, doctype, processing instruction, CDATA section, or bogus comment. Its
    /// content is discarded.
    case comment
}

struct HTMLStartTag: Equatable {
    /// ASCII-lowercased tag name.
    var name: String
    /// Attributes in source order. Duplicates are dropped (the first wins, as in browsers).
    var attributes: [HTMLAttribute]
    /// The tag ended with `/>`.
    var isSelfClosing: Bool
}

struct HTMLAttribute: Equatable {
    /// ASCII-lowercased attribute name.
    var name: String
    /// The value as written, without quotes and with character references not decoded, or
    /// `nil` when the attribute has no `=`.
    var value: String?
}

/// A tokenizer for raw HTML fragments, following the WHATWG tokenizer's data and tag states
/// closely enough that tags and attributes are split where a browser would split them.
///
/// It does not build a tree or track raw-text elements itself; the sanitizer asks it to skip
/// raw text with `skipRawText(endTag:)`. Unterminated tags at the end of the input are
/// dropped (a browser drops them too), and U+0000 becomes U+FFFD.
struct HTMLTokenizer {
    private let scalars: [Unicode.Scalar]
    private var position = 0

    init(_ html: String) {
        scalars = Array(html.unicodeScalars)
    }

    /// How many Unicode scalars of the input have been consumed: the end of the last token.
    var scalarOffset: Int {
        position
    }

    mutating func next() -> HTMLToken? {
        while position < scalars.count {
            if scalars[position] != "<" {
                return .text(consumeText())
            }
            if let token = consumeMarkup() {
                return token
            }
        }
        return nil
    }

    /// Skips raw text up to and including the end tag `</name>` (matched ASCII
    /// case-insensitively). Returns `false` when the input ends first.
    mutating func skipRawText(endTag name: String) -> Bool {
        let nameScalars = Array(name.unicodeScalars)
        while position < scalars.count {
            if scalars[position] == "<", peek(1) == "/", matchesName(nameScalars, at: position + 2),
                let after = peek(2 + nameScalars.count), Self.isWhitespace(after) || after == "/" || after == ">"
            {
                position += 2 + nameScalars.count
                _ = consumeAttributes()
                return true
            }
            position += 1
        }
        return false
    }

    // MARK: - States

    private mutating func consumeText() -> String {
        var text = String.UnicodeScalarView()
        while let scalar = current, scalar != "<" {
            text.append(Self.normalized(scalar))
            position += 1
        }
        return String(text)
    }

    /// Consumes markup starting at `<`. Returns `nil` when the markup produces no token.
    private mutating func consumeMarkup() -> HTMLToken? {
        guard let next = peek(1) else {
            position += 1
            return .text("<")
        }
        if Self.isASCIIAlpha(next) {
            position += 1
            return consumeStartTag()
        }
        switch next {
        case "/":
            guard let afterSlash = peek(2) else {
                position += 2
                return .text("</")
            }
            if Self.isASCIIAlpha(afterSlash) {
                position += 2
                let name = consumeTagName()
                return consumeAttributes() == nil ? nil : .endTag(name: name)
            }
            if afterSlash == ">" {
                // `</>` is ignored entirely.
                position += 3
                return nil
            }
            position += 2
            consumeBogusComment()
            return .comment
        case "!":
            if peek(2) == "-", peek(3) == "-" {
                position += 4
                consumeComment()
            } else {
                position += 2
                consumeBogusComment()
            }
            return .comment
        case "?":
            position += 1
            consumeBogusComment()
            return .comment
        default:
            position += 1
            return .text("<")
        }
    }

    private mutating func consumeStartTag() -> HTMLToken? {
        let name = consumeTagName()
        guard let (attributes, isSelfClosing) = consumeAttributes() else {
            return nil
        }
        return .startTag(HTMLStartTag(name: name, attributes: attributes, isSelfClosing: isSelfClosing))
    }

    private mutating func consumeTagName() -> String {
        var name = String.UnicodeScalarView()
        while let scalar = current, !Self.isWhitespace(scalar), scalar != "/", scalar != ">" {
            name.append(Self.lowercased(Self.normalized(scalar)))
            position += 1
        }
        return String(name)
    }

    /// Consumes attributes through the closing `>`. Returns `nil` when the input ends inside
    /// the tag.
    private mutating func consumeAttributes() -> (attributes: [HTMLAttribute], isSelfClosing: Bool)? {
        var attributes: [HTMLAttribute] = []
        var seen: Set<String> = []
        while true {
            skipWhitespace()
            guard let scalar = current else {
                return nil
            }
            if scalar == ">" {
                position += 1
                return (attributes, false)
            }
            if scalar == "/" {
                position += 1
                if current == ">" {
                    position += 1
                    return (attributes, true)
                }
                continue
            }
            // The first character of a name may be `=`.
            var name = String.UnicodeScalarView([Self.lowercased(Self.normalized(scalar))])
            position += 1
            while let scalar = current, !Self.isWhitespace(scalar), scalar != "/", scalar != ">", scalar != "=" {
                name.append(Self.lowercased(Self.normalized(scalar)))
                position += 1
            }
            skipWhitespace()
            var value: String?
            if current == "=" {
                position += 1
                skipWhitespace()
                guard let attributeValue = consumeAttributeValue() else {
                    return nil
                }
                value = attributeValue
            }
            let attributeName = String(name)
            if seen.insert(attributeName).inserted {
                attributes.append(HTMLAttribute(name: attributeName, value: value))
            }
        }
    }

    private mutating func consumeAttributeValue() -> String? {
        guard let first = current else {
            return nil
        }
        var value = String.UnicodeScalarView()
        if first == "\"" || first == "'" {
            position += 1
            while let scalar = current, scalar != first {
                value.append(Self.normalized(scalar))
                position += 1
            }
            guard current != nil else {
                return nil
            }
            position += 1
            return String(value)
        }
        // Unquoted; `>` right after `=` means an empty value.
        while let scalar = current, !Self.isWhitespace(scalar), scalar != ">" {
            value.append(Self.normalized(scalar))
            position += 1
        }
        return current == nil ? nil : String(value)
    }

    /// After `<!--`: ends at `-->` or `--!>`; `<!-->` and `<!--->` are empty comments.
    private mutating func consumeComment() {
        if current == ">" {
            position += 1
            return
        }
        if current == "-", peek(1) == ">" {
            position += 2
            return
        }
        while position < scalars.count {
            if matches("-->") {
                position += 3
                return
            }
            if matches("--!>") {
                position += 4
                return
            }
            position += 1
        }
    }

    private mutating func consumeBogusComment() {
        while let scalar = current {
            position += 1
            if scalar == ">" {
                return
            }
        }
    }

    // MARK: - Helpers

    private var current: Unicode.Scalar? {
        peek(0)
    }

    private func peek(_ offset: Int) -> Unicode.Scalar? {
        let index = position + offset
        return index < scalars.count ? scalars[index] : nil
    }

    private func matches(_ literal: String) -> Bool {
        var index = position
        for scalar in literal.unicodeScalars {
            guard index < scalars.count, scalars[index] == scalar else {
                return false
            }
            index += 1
        }
        return true
    }

    private func matchesName(_ name: [Unicode.Scalar], at start: Int) -> Bool {
        guard start + name.count <= scalars.count else {
            return false
        }
        return name.indices.allSatisfy { Self.lowercased(scalars[start + $0]) == name[$0] }
    }

    private mutating func skipWhitespace() {
        while let scalar = current, Self.isWhitespace(scalar) {
            position += 1
        }
    }

    /// HTML whitespace: tab, line feed, form feed, carriage return, and space.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\t", "\n", "\u{0C}", "\r", " ": true
        default: false
        }
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard ("A"..."Z").contains(scalar), let lower = Unicode.Scalar(scalar.value + 0x20) else {
            return scalar
        }
        return lower
    }

    private static func normalized(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        scalar == "\u{0}" ? "\u{FFFD}" : scalar
    }
}

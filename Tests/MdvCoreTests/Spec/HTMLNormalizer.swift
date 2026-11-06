import Foundation

/// Normalizes HTML so insignificant differences don't fail spec examples. A port of the approach
/// in cmark's `test/normalize.py`:
///
/// - Whitespace runs collapse to one space outside `<pre>`, and whitespace around block-level
///   tags is removed.
/// - Tag and attribute names are lowercased, attributes are sorted, values are re-escaped.
/// - Self-closing syntax is dropped (`<br />` becomes `<br>`).
/// - Numeric character references and `&amp;`/`&lt;`/`&gt;`/`&quot;` decode to characters, then
///   `<`, `>`, `&`, `"` are re-escaped.
///
/// Deviation: other named entities are kept verbatim instead of decoded (no entity table). Both
/// sides of a comparison go through the same function, so this only matters when one side uses
/// a named entity and the other the literal character; cmark never emits named entities beyond
/// the four above.
enum HTMLNormalizer {
    static func normalize(_ html: String) -> String {
        var state = State()
        for chunk in chunks(of: html) {
            if chunk.hasPrefix("<![CDATA[") {
                state.output += chunk
            } else if chunk.hasPrefix("<") {
                state.handleMarkup(chunk)
            } else {
                state.handleText(chunk)
            }
        }
        return state.output
    }

    /// Splits like normalize.py's `html_chunk_re`: CDATA sections, `<...>` runs, and text.
    private static func chunks(of html: String) -> [String] {
        var result: [String] = []
        var rest = html[...]
        while !rest.isEmpty {
            if rest.hasPrefix("<![CDATA["), let end = rest.range(of: "]]>") {
                result.append(String(rest[..<end.upperBound]))
                rest = rest[end.upperBound...]
            } else if rest.hasPrefix("<"), let end = rest.firstIndex(of: ">") {
                let next = rest.index(after: end)
                result.append(String(rest[..<next]))
                rest = rest[next...]
            } else {
                // Text runs to the next `<` (an unclosed `<` is text, as in the Python regex).
                let start = rest.index(after: rest.startIndex)
                let end = rest[start...].firstIndex(of: "<") ?? rest.endIndex
                result.append(String(rest[..<end]))
                rest = rest[end...]
            }
        }
        return result
    }
}

// MARK: - Parser state (MyHTMLParser in normalize.py)

extension HTMLNormalizer {
    private enum Event {
        case startTag, endTag, data, other
    }

    private static let blockTags: Set<String> = [
        "article", "header", "aside", "hgroup", "blockquote", "hr", "iframe", "body", "li", "map",
        "button", "object", "canvas", "ol", "caption", "output", "col", "p", "colgroup", "pre", "dd",
        "progress", "div", "section", "dl", "table", "td", "dt", "tbody", "embed", "textarea",
        "fieldset", "tfoot", "figcaption", "th", "figure", "thead", "footer", "tr", "form", "ul",
        "h1", "h2", "h3", "h4", "h5", "h6", "video", "script", "style",
    ]

    private struct State {
        var output = ""
        var last = Event.startTag
        var lastTag = ""
        var inPre = false

        mutating func handleMarkup(_ chunk: String) {
            if chunk.hasPrefix("<!--") || chunk.hasPrefix("<!") || chunk.hasPrefix("<?") {
                output += chunk
                last = .other
            } else if let tag = Tag(chunk) {
                if tag.isEnd {
                    endTag(tag.name)
                } else {
                    startTag(tag)
                }
            } else {
                handleText(chunk)
            }
        }

        mutating func handleText(_ text: String) {
            // Character references split the text the way HTMLParser's callbacks do.
            for piece in References.split(text) {
                switch piece {
                case .text(let data): handleData(data)
                case .reference(let character):
                    // Like normalize.py's `output_char`: `'` stays literal in text.
                    output += character == "'" ? "'" : References.escape(String(character))
                    last = .other
                }
            }
        }

        private mutating func handleData(_ text: String) {
            var data = text
            let afterTag = last == .startTag || last == .endTag
            let afterBlockTag = afterTag && blockTags.contains(lastTag)
            if afterTag, lastTag == "br" {
                data = String(data.drop { $0 == "\n" })
            }
            if !inPre {
                data = collapsingWhitespace(data)
            }
            if afterBlockTag, !inPre {
                data = last == .startTag ? String(data.drop(while: \.isWhitespace)) : data.trimmed
            }
            output += data
            last = .data
        }

        private mutating func startTag(_ tag: Tag) {
            if tag.name == "pre" {
                inPre = true
            }
            if blockTags.contains(tag.name) {
                output = output.trimmedTrailing
            }
            output += "<" + tag.name
            for (name, value) in tag.attributes.sorted(by: { $0.name < $1.name }) {
                output += " " + name
                if let value {
                    output += "=\"" + References.escape(References.decode(value)) + "\""
                }
            }
            output += ">"
            lastTag = tag.name
            last = tag.isSelfClosing ? .endTag : .startTag
        }

        private mutating func endTag(_ name: String) {
            if name == "pre" {
                inPre = false
            } else if blockTags.contains(name) {
                output = output.trimmedTrailing
            }
            output += "</" + name + ">"
            lastTag = name
            last = .endTag
        }

        private func collapsingWhitespace(_ text: String) -> String {
            var result = ""
            var inWhitespace = false
            for character in text {
                if character.isWhitespace {
                    if !inWhitespace {
                        result.append(" ")
                    }
                    inWhitespace = true
                } else {
                    result.append(character)
                    inWhitespace = false
                }
            }
            return result
        }
    }
}

// MARK: - Tags

extension HTMLNormalizer {
    /// A start or end tag parsed from one `<...>` chunk, or `nil` if the chunk isn't a tag
    /// (HTMLParser then treats it as text).
    private struct Tag {
        var name: String
        var isEnd: Bool
        var isSelfClosing = false
        var attributes: [(name: String, value: String?)] = []

        init?(_ chunk: String) {
            var body = chunk.dropFirst().dropLast()[...]
            isEnd = body.hasPrefix("/")
            if isEnd {
                body = body.dropFirst()
            }
            guard let first = body.first, first.isASCII, first.isLetter else {
                return nil
            }
            let nameEnd = body.firstIndex { $0.isWhitespace || $0 == "/" } ?? body.endIndex
            name = body[..<nameEnd].lowercased()
            guard !isEnd else {
                return
            }
            var rest = body[nameEnd...]
            if rest.hasSuffix("/") {
                isSelfClosing = true
                rest = rest.dropLast()
            }
            attributes = Self.attributes(in: rest)
        }

        /// Attribute name/value pairs, like HTMLParser's `attrfind` regex.
        private static func attributes(in text: Substring) -> [(name: String, value: String?)] {
            var result: [(name: String, value: String?)] = []
            var rest = text.drop { $0.isWhitespace || $0 == "/" }
            while !rest.isEmpty {
                let nameEnd = rest.firstIndex { $0.isWhitespace || $0 == "=" || $0 == "/" } ?? rest.endIndex
                let name = rest[..<nameEnd].lowercased()
                rest = rest[nameEnd...].drop(while: \.isWhitespace)
                var value: String?
                if rest.first == "=" {
                    rest = rest.dropFirst().drop(while: \.isWhitespace)
                    if let quote = rest.first, quote == "\"" || quote == "'" {
                        let body = rest.dropFirst()
                        let close = body.firstIndex(of: quote) ?? body.endIndex
                        value = String(body[..<close])
                        rest = close < body.endIndex ? body[body.index(after: close)...] : body[close...]
                    } else {
                        let end = rest.firstIndex(where: \.isWhitespace) ?? rest.endIndex
                        value = String(rest[..<end])
                        rest = rest[end...]
                    }
                }
                if !name.isEmpty {
                    result.append((name, value))
                }
                rest = rest.drop { $0.isWhitespace || $0 == "/" }
            }
            return result
        }
    }
}

// MARK: - Character references

extension HTMLNormalizer {
    private enum ReferencePiece {
        case text(String)
        /// A recognized reference, decoded.
        case reference(Character)
    }

    private enum References {

        private static let named: [String: Character] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\""]

        /// Splits text into plain runs and recognized character references.
        static func split(_ text: String) -> [ReferencePiece] {
            var pieces: [ReferencePiece] = []
            var plain = ""
            var rest = text[...]
            while let ampersand = rest.firstIndex(of: "&") {
                plain += rest[..<ampersand]
                let candidate = rest[ampersand...]
                if let semicolon = candidate.firstIndex(of: ";"),
                    let character = character(for: candidate[candidate.index(after: ampersand)..<semicolon])
                {
                    if !plain.isEmpty {
                        pieces.append(.text(plain))
                        plain = ""
                    }
                    pieces.append(.reference(character))
                    rest = candidate[candidate.index(after: semicolon)...]
                } else {
                    plain += "&"
                    rest = candidate.dropFirst()
                }
            }
            plain += rest
            if !plain.isEmpty {
                pieces.append(.text(plain))
            }
            return pieces
        }

        /// Decodes recognized references in an attribute value; others stay verbatim.
        static func decode(_ text: String) -> String {
            split(text).map { piece in
                switch piece {
                case .text(let plain): plain
                case .reference(let character): String(character)
                }
            }
            .joined()
        }

        /// Escapes like `html.escape(value, quote=True)`.
        static func escape(_ text: String) -> String {
            var result = ""
            for character in text {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\"": result += "&quot;"
                case "'": result += "&#x27;"
                default: result.append(character)
                }
            }
            return result
        }

        /// The character a reference body (`amp`, `#38`, `#x26`) stands for, if recognized.
        private static func character(for body: Substring) -> Character? {
            if let character = named[String(body)] {
                return character
            }
            guard body.first == "#" else {
                return nil
            }
            let digits = body.dropFirst()
            let value: UInt32? =
                if digits.first == "x" || digits.first == "X" {
                    UInt32(digits.dropFirst(), radix: 16)
                } else {
                    UInt32(digits, radix: 10)
                }
            guard let value, let scalar = Unicode.Scalar(value) else {
                return nil
            }
            return Character(scalar)
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    fileprivate var trimmedTrailing: String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}

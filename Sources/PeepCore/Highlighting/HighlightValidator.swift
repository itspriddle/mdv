/// Checks a `SyntaxHighlighter`'s output before `HTMLRenderer` inserts it into trusted markup.
///
/// Highlighted HTML is accepted only when it consists of:
/// - `<span class="C">` where `C` is 1–128 bytes of `[a-z0-9_ -]` starting with `hljs-` or
///   `language-` (highlight.js scopes such as `hljs-title function_`, and `language-xml` around
///   embedded sub-languages),
/// - `</span>` closing an open span (nesting at most `maximumDepth` deep, all closed at the end),
/// - text in which `&`, `<`, `>`, `"`, and `'` appear only as `&amp;`, `&lt;`, `&gt;`,
///   `&quot;`, `&#x27;`, or `&#39;`,
///
/// and when its unescaped text is exactly the original code. Anything else is rejected, and the
/// block falls back to plain escaped code.
///
/// Accepted output is re-serialized from the parsed tokens (text re-escaped the same way as
/// plain code blocks), so the renderer never copies the highlighter's string to its output.
enum HighlightValidator {
    static let maximumDepth = 32
    static let maximumClassLength = 128

    /// The validated, re-serialized markup, or `nil` if `html` breaks a rule above.
    static func validated(_ html: String, source: String) -> String? {
        var parser = Parser(bytes: Array(html.utf8))
        var output = HTMLOutput(capacity: html.utf8.count)
        var text: [UInt8] = []
        text.reserveCapacity(source.utf8.count)
        var depth = 0

        while let token = parser.next() {
            switch token {
            case .open(let className):
                guard depth < maximumDepth else {
                    return nil
                }
                depth += 1
                output.raw("<span class=\"")
                output.raw(className)
                output.raw("\">")
            case .close:
                guard depth > 0 else {
                    return nil
                }
                depth -= 1
                output.raw("</span>")
            case .text(let decoded):
                text.append(contentsOf: decoded.utf8)
                output.text(decoded)
            case .invalid:
                return nil
            }
        }
        guard depth == 0, text.elementsEqual(source.utf8) else {
            return nil
        }
        return output.string
    }

    private enum Token {
        case open(String)
        case close
        case text(String)
        case invalid
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        private static let openPrefix = Array("<span class=\"".utf8)
        private static let openSuffix = Array("\">".utf8)
        private static let close = Array("</span>".utf8)
        private static let classPrefixes = [Array("hljs-".utf8), Array("language-".utf8)]
        private static let entities: [(escaped: [UInt8], byte: UInt8)] = [
            (Array("&amp;".utf8), UInt8(ascii: "&")),
            (Array("&lt;".utf8), UInt8(ascii: "<")),
            (Array("&gt;".utf8), UInt8(ascii: ">")),
            (Array("&quot;".utf8), UInt8(ascii: "\"")),
            (Array("&#x27;".utf8), UInt8(ascii: "'")),
            (Array("&#39;".utf8), UInt8(ascii: "'")),
        ]

        mutating func next() -> Token? {
            guard index < bytes.count else {
                return nil
            }
            if bytes[index] == UInt8(ascii: "<") {
                return tag()
            }
            return text()
        }

        private func hasPrefix(_ prefix: [UInt8], at position: Int) -> Bool {
            position + prefix.count <= bytes.count && bytes[position..<position + prefix.count].elementsEqual(prefix)
        }

        private mutating func tag() -> Token {
            if hasPrefix(Self.close, at: index) {
                index += Self.close.count
                return .close
            }
            guard hasPrefix(Self.openPrefix, at: index) else {
                return .invalid
            }
            let start = index + Self.openPrefix.count
            var end = start
            while end < bytes.count, end - start <= Self.maximumClassLength, Self.isClassByte(bytes[end]) {
                end += 1
            }
            let className = bytes[start..<end]
            guard (1...HighlightValidator.maximumClassLength).contains(className.count),
                Self.classPrefixes.contains(where: { className.starts(with: $0) }),
                hasPrefix(Self.openSuffix, at: end),
                let value = String(validating: className, as: UTF8.self)
            else {
                return .invalid
            }
            index = end + Self.openSuffix.count
            return .open(value)
        }

        private mutating func text() -> Token {
            var decoded: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: "<"):
                    return Self.token(decoded)
                case UInt8(ascii: "&"):
                    guard let entity = Self.entities.first(where: { hasPrefix($0.escaped, at: index) }) else {
                        return .invalid
                    }
                    decoded.append(entity.byte)
                    index += entity.escaped.count
                case UInt8(ascii: ">"), UInt8(ascii: "\""), UInt8(ascii: "'"):
                    return .invalid
                default:
                    decoded.append(byte)
                    index += 1
                }
            }
            return Self.token(decoded)
        }

        /// Text runs split only at ASCII `<`, so they hold whole UTF-8 sequences.
        private static func token(_ decoded: [UInt8]) -> Token {
            String(validating: decoded, as: UTF8.self).map(Token.text) ?? .invalid
        }

        private static var maximumClassLength: Int { HighlightValidator.maximumClassLength }

        private static func isClassByte(_ byte: UInt8) -> Bool {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                UInt8(ascii: "_"), UInt8(ascii: " "), UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
    }
}

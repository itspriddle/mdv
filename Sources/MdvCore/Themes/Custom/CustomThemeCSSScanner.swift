/// The tokenizer behind `CustomThemeCSS.validate`: one pass over the UTF-8 bytes, skipping
/// comments and strings, decoding escapes in names, and keeping a stack of open brackets.
struct CustomThemeCSSScanner {
    let bytes: [UInt8]
    var index = 0
    /// An open bracket: the closing byte expected, where it opened, and for `(`, the function.
    struct Bracket {
        let closer: UInt8
        let offset: Int
        let function: String?
    }

    var open: [Bracket] = []

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func run() throws(CustomThemeProblem) {
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "*"):
                try skipComment()
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                try scanString()
            case UInt8(ascii: "{"), UInt8(ascii: "["), UInt8(ascii: "("):
                open.append(Bracket(closer: Self.closer(of: byte), offset: index, function: nil))
                index += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"), UInt8(ascii: ")"):
                guard let last = open.last, last.closer == byte else {
                    throw .unexpectedClose(String(UnicodeScalar(byte)), line: line(at: index))
                }
                open.removeLast()
                index += 1
            case UInt8(ascii: "@"):
                let start = index
                index += 1
                if startsName(at: index), try readName() == "import" {
                    throw .importRule(line: line(at: start))
                }
            case UInt8(ascii: "#"):
                // A hash token (`#fff`, `#id`): its name can't be a function.
                index += 1
                if startsName(at: index) {
                    _ = try readName()
                }
            case _ where startsName(at: index):
                try scanNameOrFunction()
            default:
                index += 1
            }
        }
        if let last = open.last {
            let opener =
                switch last.closer {
                case UInt8(ascii: "}"): "{"
                case UInt8(ascii: "]"): "["
                default: "("
                }
            throw .unclosed(opener, line: line(at: last.offset))
        }
    }

    // MARK: Tokens

    /// A quoted string; inside a function that takes URLs, it must be an allowed one.
    private mutating func scanString() throws(CustomThemeProblem) {
        let start = index
        let value = try readString()
        if let function = open.last?.function, CustomThemeCSS.urlStringFunctions.contains(function),
            !CustomThemeCSS.isAllowedURL(value)
        {
            throw .externalURL(line: line(at: start))
        }
    }

    /// An identifier, or a function when `(` follows it.
    private mutating func scanNameOrFunction() throws(CustomThemeProblem) {
        let start = index
        let name = try readName()
        guard peek(0) == UInt8(ascii: "(") else {
            return
        }
        index += 1
        switch name {
        case "expression":
            throw .expression(line: line(at: start))
        case "url":
            try scanURL(start: start)
        default:
            open.append(Bracket(closer: UInt8(ascii: ")"), offset: start, function: name))
        }
    }

    /// After `url(`: a quoted URL is an ordinary function holding a string (checked when the
    /// string is read); an unquoted one is a single URL token up to `)`.
    private mutating func scanURL(start: Int) throws(CustomThemeProblem) {
        skipWhitespace()
        if let next = peek(0), next == UInt8(ascii: "\"") || next == UInt8(ascii: "'") {
            open.append(Bracket(closer: UInt8(ascii: ")"), offset: start, function: "url"))
            return
        }
        var value = String.UnicodeScalarView()
        while let byte = peek(0) {
            switch byte {
            case UInt8(ascii: ")"):
                index += 1
                guard CustomThemeCSS.isAllowedURL(String(value)) else {
                    throw .externalURL(line: line(at: start))
                }
                return
            case UInt8(ascii: "\\"):
                guard let scalar = readEscape() else {
                    throw .externalURL(line: line(at: start))
                }
                value.append(scalar)
            case UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "("):
                // A bad URL token: CSS drops it, mdv rejects it.
                throw .externalURL(line: line(at: start))
            default:
                value.append(readScalar())
            }
        }
        throw .unclosed("(", line: line(at: start))
    }

    /// A name: letters, digits, `-`, `_`, non-ASCII, and escapes, decoded and ASCII
    /// lowercased.
    private mutating func readName() throws(CustomThemeProblem) -> String {
        var name = String.UnicodeScalarView()
        while let byte = peek(0) {
            if byte == UInt8(ascii: "\\") {
                guard let scalar = readEscape() else {
                    break
                }
                name.append(scalar)
            } else if Self.isNameByte(byte) {
                name.append(readScalar())
            } else {
                break
            }
        }
        return CustomThemeCSS.asciiLowercased(String(name))
    }

    /// A quoted string's value, escapes decoded. A line break or the end of the file before
    /// the closing quote is an error (CSS would make it a bad string).
    private mutating func readString() throws(CustomThemeProblem) -> String {
        let start = index
        let quote = bytes[index]
        index += 1
        var value = String.UnicodeScalarView()
        while let byte = peek(0) {
            switch byte {
            case quote:
                index += 1
                return String(value)
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"), 0x0C:
                throw .unterminatedString(line: line(at: start))
            case UInt8(ascii: "\\"):
                if let next = peek(1), Self.isNewline(next) {
                    // An escaped line break continues the string.
                    index += next == UInt8(ascii: "\r") && peek(2) == UInt8(ascii: "\n") ? 3 : 2
                } else if let scalar = readEscape() {
                    value.append(scalar)
                } else {
                    index += 1
                }
            default:
                value.append(readScalar())
            }
        }
        throw .unterminatedString(line: line(at: start))
    }

    /// An escape at `index` (a backslash): up to six hex digits and one optional whitespace,
    /// or any other character. Nil (and nothing consumed) for a backslash before a line
    /// break or the end of the file, which isn't an escape.
    private mutating func readEscape() -> Unicode.Scalar? {
        guard let next = peek(1), !Self.isNewline(next) else {
            return nil
        }
        index += 1
        guard Self.isHexDigit(next) else {
            return readScalar()
        }
        var value: UInt32 = 0
        var digits = 0
        while digits < 6, let byte = peek(0), Self.isHexDigit(byte) {
            value = value * 16 + Self.hexValue(byte)
            digits += 1
            index += 1
        }
        if let byte = peek(0), byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || Self.isNewline(byte) {
            index += byte == UInt8(ascii: "\r") && peek(1) == UInt8(ascii: "\n") ? 2 : 1
        }
        guard value != 0, let scalar = Unicode.Scalar(value) else {
            return Unicode.Scalar(0xFFFD)
        }
        return scalar
    }

    /// The UTF-8 scalar at `index` (the input is valid UTF-8; anything else becomes U+FFFD).
    private mutating func readScalar() -> Unicode.Scalar {
        let lead = bytes[index]
        let length =
            switch lead {
            case 0..<0x80: 1
            case 0xC0..<0xE0: 2
            case 0xE0..<0xF0: 3
            case 0xF0..<0xF8: 4
            default: 1
            }
        let end = min(index + length, bytes.count)
        defer { index = end }
        guard let scalar = String(validating: bytes[index..<end], as: UTF8.self)?.unicodeScalars.first else {
            return "\u{FFFD}"
        }
        return scalar
    }

    private mutating func skipComment() throws(CustomThemeProblem) {
        let start = index
        index += 2
        while index + 1 < bytes.count {
            if bytes[index] == UInt8(ascii: "*"), bytes[index + 1] == UInt8(ascii: "/") {
                index += 2
                return
            }
            index += 1
        }
        throw .unterminatedComment(line: line(at: start))
    }

    private mutating func skipWhitespace() {
        while let byte = peek(0), byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || Self.isNewline(byte) {
            index += 1
        }
    }

    // MARK: Helpers

    private func peek(_ offset: Int) -> UInt8? {
        index + offset < bytes.count ? bytes[index + offset] : nil
    }

    /// Whether a name (or escape) starts at `offset`.
    private func startsName(at offset: Int) -> Bool {
        guard offset < bytes.count else {
            return false
        }
        let byte = bytes[offset]
        if byte == UInt8(ascii: "\\") {
            return offset + 1 < bytes.count && !Self.isNewline(bytes[offset + 1])
        }
        return Self.isNameByte(byte)
    }

    /// The 1-based line of `offset`.
    private func line(at offset: Int) -> Int {
        bytes[..<min(offset, bytes.count)].reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    }
}

// MARK: Byte classes

extension CustomThemeCSSScanner {
    fileprivate static func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"), 0x80...:
            true
        default:
            false
        }
    }

    fileprivate static func isNewline(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == 0x0C
    }

    fileprivate static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"),
            UInt8(ascii: "A")...UInt8(ascii: "F"):
            true
        default:
            false
        }
    }

    fileprivate static func hexValue(_ byte: UInt8) -> UInt32 {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        default: UInt32(byte - UInt8(ascii: "A") + 10)
        }
    }
    fileprivate static func closer(of opener: UInt8) -> UInt8 {
        switch opener {
        case UInt8(ascii: "{"): UInt8(ascii: "}")
        case UInt8(ascii: "["): UInt8(ascii: "]")
        default: UInt8(ascii: ")")
        }
    }
}

/// Which bytes of a text node were written as is in the source, as opposed to coming from a
/// backslash escape (`\[`) or a character reference (`&#91;`) (#53).
///
/// cmark merges adjacent text nodes after parsing, so `\[[Page]]` and `[[Page]]` both reach the
/// tree as the text `[[Page]]`. Wiki link brackets must be written as is (an escaped `\[[`
/// stays literal), so `WikiLinks` lines each candidate text node up with its source line.
///
/// cmark's columns for inline text are only a hint (they drift on continuation lines, lazy
/// lines, and after escapes in table cells), so the node is aligned at its reported column
/// first, then at nearby offsets on its line (and the next, where a hard break can put it).
/// Alignment accepts a byte as is, a backslash escape of ASCII punctuation, or a character
/// reference that decodes to the next bytes. A node that can't be aligned counts as not written
/// as is, so its brackets stay literal: a missed link, never an escape ignored.
struct SourceLines {
    private let bytes: [UInt8]
    /// Byte ranges of each line (1-based line `n` is `lines[n - 1]`), without line endings.
    private let lines: [Range<Int>]

    /// Lines longer than this are only checked at the reported column, not searched, so a
    /// pathological line can't make alignment quadratic.
    static let maximumSearchedLineBytes = 4096

    /// Splits `source` the way cmark counts lines (`\n`, `\r\n`, or `\r`). A leading byte order
    /// mark stays in line 1: cmark skips it but counts it in columns.
    init(_ source: String) {
        bytes = Array(source.utf8)
        var lines: [Range<Int>] = []
        var start = 0
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\n"):
                lines.append(start..<index)
                index += 1
                start = index
            case UInt8(ascii: "\r"):
                lines.append(start..<index)
                index += bytes.indices.contains(index + 1) && bytes[index + 1] == UInt8(ascii: "\n") ? 2 : 1
                start = index
            default:
                index += 1
            }
        }
        lines.append(start..<bytes.count)
        self.lines = lines
    }

    /// For each byte of `literal` (a text node's text), whether it was written as is; `nil` when
    /// the node can't be found in the source.
    func verbatimMask(of literal: String, at range: SourceRange) -> [Bool]? {
        let text = Array(literal.utf8)
        var candidates = [range.start.line]
        for line in [range.end.line, range.start.line + 1] where !candidates.contains(line) {
            candidates.append(line)
        }
        for (position, number) in candidates.enumerated() where lines.indices.contains(number - 1) {
            let line = lines[number - 1]
            let hint = position == 0 ? max(0, min(range.start.column - 1, line.count)) : 0
            if let mask = Self.align(text, in: bytes[line], at: line.lowerBound + hint) {
                return mask
            }
            guard line.count <= Self.maximumSearchedLineBytes else {
                continue
            }
            for distance in 1...max(1, line.count) {
                for offset in [hint + distance, hint - distance] where offset >= 0 && offset < line.count {
                    if let mask = Self.align(text, in: bytes[line], at: line.lowerBound + offset) {
                        return mask
                    }
                }
            }
        }
        return nil
    }

    /// Aligns `text` with `raw` starting at `start`, or returns `nil`.
    ///
    /// A start right after an unescaped backslash that escapes it is refused: there the node's
    /// first byte came from the escape, and aligning past the backslash would read it as written.
    private static func align(_ text: [UInt8], in raw: ArraySlice<UInt8>, at start: Int) -> [Bool]? {
        guard !isEscaped(raw, at: start) else {
            return nil
        }
        var mask: [Bool] = []
        mask.reserveCapacity(text.count)
        var index = start
        while mask.count < text.count {
            guard index < raw.endIndex else {
                return nil
            }
            let byte = raw[index]
            let next = mask.count
            if byte == UInt8(ascii: "\\"), index + 1 < raw.endIndex, raw[index + 1].isASCIIPunctuation,
                raw[index + 1] == text[next]
            {
                mask.append(false)
                index += 2
            } else if byte == UInt8(ascii: "&"), let (length, value) = characterReference(in: raw, at: index),
                text[next...].starts(with: value)
            {
                mask += repeatElement(false, count: value.count)
                index += length
            } else if byte == text[next] {
                mask.append(true)
                index += 1
            } else {
                return nil
            }
        }
        return mask
    }

    /// Whether the byte at `index` is ASCII punctuation preceded by an odd run of backslashes.
    private static func isEscaped(_ raw: ArraySlice<UInt8>, at index: Int) -> Bool {
        guard index < raw.endIndex, raw[index].isASCIIPunctuation else {
            return false
        }
        var backslashes = 0
        var previous = index - 1
        while previous >= raw.startIndex, raw[previous] == UInt8(ascii: "\\") {
            backslashes += 1
            previous -= 1
        }
        return backslashes % 2 == 1
    }

    /// The character reference at `start` (`&name;`, `&#123;`, `&#x7B;`): its length in source
    /// bytes and its UTF-8 value, as cmark decodes it.
    private static func characterReference(in raw: ArraySlice<UInt8>, at start: Int) -> (Int, [UInt8])? {
        guard let semicolon = raw[start...].prefix(40).firstIndex(of: UInt8(ascii: ";")), semicolon > start + 1,
            let body = String(validating: raw[(start + 1)..<semicolon], as: UTF8.self)
        else {
            return nil
        }
        let length = semicolon - start + 1
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let isHex = digits.first == "x" || digits.first == "X"
            let number = isHex ? digits.dropFirst() : digits
            guard !number.isEmpty, number.count <= (isHex ? 6 : 7),
                number.allSatisfy({ isHex ? $0.isHexDigit : $0.isASCII && $0.isNumber }),
                let value = UInt32(number, radix: isHex ? 16 : 10)
            else {
                return nil
            }
            let scalar = value == 0 ? nil : Unicode.Scalar(value)
            return (length, Array(String(scalar ?? "\u{FFFD}").utf8))
        }
        guard let value = HTMLEntities.all[body] else {
            return nil
        }
        return (length, Array(value.utf8))
    }
}

extension UInt8 {
    /// CommonMark's ASCII punctuation, the characters a backslash escapes.
    fileprivate var isASCIIPunctuation: Bool {
        switch self {
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E: true
        default: false
        }
    }
}

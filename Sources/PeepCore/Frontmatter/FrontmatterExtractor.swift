extension Frontmatter {
    /// Detects frontmatter at the very start of `markdown` (after an optional UTF-8 BOM) and splits
    /// it from the body. YAML is parsed; TOML is only detected.
    ///
    /// The opening fence must be the first line, and the closing fence must stand alone on its own
    /// line (trailing spaces and tabs are allowed on both). Without a closing fence the document has
    /// no frontmatter and renders as plain Markdown. Line endings may be `\n`, `\r\n`, or `\r`, as
    /// in cmark, so `lineCount` agrees with cmark's line numbers.
    ///
    /// - Returns: `nil` when there is no frontmatter; otherwise the frontmatter and the body that
    ///   follows its closing fence. Parse the body with `lineOffset: frontmatter.lineCount`.
    public static func extract(from markdown: String) -> (frontmatter: Frontmatter, body: Substring)? {
        let utf8 = markdown.utf8
        var cursor = utf8.startIndex
        if utf8.starts(with: byteOrderMark) {
            cursor = utf8.index(cursor, offsetBy: byteOrderMark.count)
        }

        guard let opening = FrontmatterLine(in: utf8, from: cursor), let next = opening.next else {
            return nil
        }
        let format: Format
        let closers: [[UInt8]]
        if opening.isFence(yamlFence, in: utf8) {
            format = .yaml
            closers = [yamlFence, yamlDocumentEnd]
        } else if opening.isFence(tomlFence, in: utf8) {
            format = .toml
            closers = [tomlFence]
        } else {
            return nil
        }

        let rawStart = next
        var lineCount = 1
        var lineStart: String.Index? = next
        while let start = lineStart, let line = FrontmatterLine(in: utf8, from: start) {
            lineCount += 1
            if closers.contains(where: { line.isFence($0, in: utf8) }) {
                let raw = String(Substring(utf8[rawStart..<start]))
                let body = Substring(utf8[(line.next ?? utf8.endIndex)...])
                let frontmatter =
                    format == .yaml
                    ? YAMLFrontmatter.parse(raw, lineCount: lineCount)
                    : Frontmatter(format: .toml, raw: raw, lineCount: lineCount)
                return (frontmatter, body)
            }
            lineStart = line.next
        }
        return nil
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let yamlFence = Array("---".utf8)
    private static let yamlDocumentEnd = Array("...".utf8)
    private static let tomlFence = Array("+++".utf8)
}

/// One line of the source: its content (without terminator) and where the next line starts.
private struct FrontmatterLine {
    let start: String.Index
    let end: String.Index
    /// Start of the following line, or `nil` when this line has no terminator (end of input).
    let next: String.Index?

    /// `nil` when `start` is at the end of the input.
    init?(in utf8: String.UTF8View, from start: String.Index) {
        guard start < utf8.endIndex else {
            return nil
        }
        self.start = start
        var index = start
        while index < utf8.endIndex, utf8[index] != Self.lineFeed, utf8[index] != Self.carriageReturn {
            index = utf8.index(after: index)
        }
        end = index
        if index == utf8.endIndex {
            next = nil
        } else {
            let terminator = utf8[index]
            index = utf8.index(after: index)
            if terminator == Self.carriageReturn, index < utf8.endIndex, utf8[index] == Self.lineFeed {
                index = utf8.index(after: index)
            }
            next = index
        }
    }

    /// The line is exactly `fence`, optionally followed by spaces and tabs.
    func isFence(_ fence: [UInt8], in utf8: String.UTF8View) -> Bool {
        let content = utf8[start..<end]
        guard content.starts(with: fence) else {
            return false
        }
        return content.dropFirst(fence.count).allSatisfy { $0 == Self.space || $0 == Self.tab }
    }

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
}

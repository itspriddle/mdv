/// One of GitHub's five alert types, written `> [!NOTE]` and so on (#52).
public enum GitHubAlert: String, CaseIterable, Sendable {
    case note
    case tip
    case important
    case warning
    case caution

    /// The title GitHub shows, whatever case the marker was written in ("Note").
    public var title: String {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }

    /// The class on the alert's `div` besides `markdown-alert` (`markdown-alert-note`).
    public var className: String { "markdown-alert-\(rawValue)" }
}

/// Turns GitHub alert block quotes into `alert` nodes (#52). Part of the GFM flavor.
///
/// github.com's rules, each checked against its renderer (`gh api markdown`, mode `gfm`; see
/// `GitHubAlertTests` and `Fixtures/flavors/gfm/alerts*.md`):
///
/// - Only block quotes at the top level of the document become alerts. A block quote in a list
///   item, a footnote, or another block quote stays a block quote, and so does one inside an
///   alert (no nesting).
/// - The block quote's first block is a paragraph whose first line is the marker alone: `[!`,
///   one of the five type names in any case (ASCII), `]`, with nothing else on the line but
///   trailing spaces or tabs. `[!NOTE] text`, `[! NOTE]`, `**[!NOTE]**`, `# [!NOTE]`, a marker
///   that is a link (`[!note]: url` defined), and unknown types stay block quotes. The marker
///   is matched on the text the parser produced, so `\[!NOTE]` and `&#91;!NOTE]` count, as
///   they do on GitHub.
/// - The line ends with a soft or hard line break (or a raw `<br>`, which is dropped with the
///   newline after it), or ends the paragraph.
/// - The alert needs a body: more text after the marker line, or another block. A marker
///   alone, or followed only by raw HTML that leaves no element (a comment, or a `<script>` the
///   sanitizer drops), stays a block quote.
/// - The marker line is removed. Text after it becomes the alert's first paragraph; the other
///   blocks follow unchanged.
///
/// Known divergence: github.com applies the rule to the HTML tree, so a block quote between
/// raw HTML tags (`<details>` … `</details>` in separate HTML blocks) isn't top level there and
/// stays a block quote; mdv's tree has it at the top level, so it becomes an alert.
enum GitHubAlerts {
    /// Returns `root` with each top-level alert block quote replaced by an `alert` node.
    static func replace(in root: MarkdownNode, options: RenderOptions) -> MarkdownNode {
        guard case .document = root.kind else {
            return root
        }
        var root = root
        for index in root.children.indices {
            if let alert = alert(from: root.children[index], options: options) {
                root.children[index] = alert
            }
        }
        return root
    }

    /// The alert `quote` stands for, or `nil` when it isn't one.
    static func alert(from quote: MarkdownNode, options: RenderOptions) -> MarkdownNode? {
        guard case .blockQuote = quote.kind, let first = quote.children.first, case .paragraph = first.kind,
            let (type, rest) = marker(in: first)
        else {
            return nil
        }
        let blocks = quote.children.dropFirst()
        guard !rest.isEmpty || blocks.contains(where: { hasContent($0, options: options) }) else {
            return nil
        }
        var body: [MarkdownNode] = []
        if !rest.isEmpty {
            body.append(MarkdownNode(.paragraph, children: rest, sourceRange: bodyRange(of: first, rest: rest)))
        }
        body += blocks
        return MarkdownNode(.alert(type), children: body, sourceRange: quote.sourceRange)
    }

    /// The alert type named on `paragraph`'s first line and the inlines after that line, or
    /// `nil` when the first line isn't a marker alone.
    static func marker(in paragraph: MarkdownNode) -> (GitHubAlert, rest: [MarkdownNode])? {
        let children = paragraph.children
        // cmark leaves `[`, `!NOTE`, and `]` as separate text nodes; GitHub sees one string.
        var end = 0
        var line = ""
        while end < children.count, case .text(let literal) = children[end].kind {
            line += literal
            end += 1
        }
        guard let type = alertType(named: line) else {
            return nil
        }
        guard end < children.count else {
            return (type, [])
        }
        switch children[end].kind {
        case .softBreak, .lineBreak:
            return (type, Array(children[(end + 1)...]))
        case .htmlInline(let html) where isLineBreakTag(html):
            var next = end + 1
            if next < children.count, children[next].kind == .softBreak {
                next += 1
            }
            return (type, Array(children[next...]))
        default:
            return nil
        }
    }

    // MARK: - Private

    /// The type `line` names when it is `[!TYPE]` with optional surrounding spaces or tabs.
    private static func alertType(named line: String) -> GitHubAlert? {
        var trimmed = Substring(line)
        while let first = trimmed.first, first == " " || first == "\t" {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, last == " " || last == "\t" {
            trimmed.removeLast()
        }
        guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]"), trimmed.count > 3 else {
            return nil
        }
        let name = trimmed.dropFirst(2).dropLast()
        guard name.allSatisfy(\.isASCII) else {
            return nil
        }
        return GitHubAlert(rawValue: name.lowercased())
    }

    /// `<br>`, `<br/>`, or `<br />`, in any case.
    private static func isLineBreakTag(_ html: String) -> Bool {
        html.wholeMatch(of: /<[bB][rR]\s*\/?>/) != nil
    }

    /// Whether a block after the marker paragraph gives the alert a body. Raw HTML counts only
    /// if it leaves an element (after sanitizing, when that's on), as on github.com, where a
    /// comment or a removed `<script>` leaves the block quote alone.
    private static func hasContent(_ block: MarkdownNode, options: RenderOptions) -> Bool {
        guard case .htmlBlock(let html) = block.kind else {
            return true
        }
        let output = options.sanitize ? HTMLSanitizer(for: options).sanitize(fragment: html) : html
        return output.contains(/<[A-Za-z]/)
    }

    /// The body paragraph starts on the line after the marker (the marker line is one text run,
    /// which never spans a line break), at its first inline's position when the parser has one.
    private static func bodyRange(of paragraph: MarkdownNode, rest: [MarkdownNode]) -> SourceRange? {
        guard let range = paragraph.sourceRange else {
            return nil
        }
        let start =
            rest.first?.sourceRange?.start ?? SourcePosition(line: range.start.line + 1, column: 1)
        return SourceRange(start: start, end: range.end)
    }
}

extension GitHubAlerts: MarkdownTreeTransform {
    static func apply(to root: MarkdownNode, context: TransformContext) -> MarkdownNode {
        replace(in: root, options: context.options)
    }
}

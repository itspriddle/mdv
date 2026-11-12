/// A node in Peep's Markdown syntax tree.
///
/// Built by `MarkdownParser` from cmark's tree, then rendered by `HTMLRenderer`. The tree is a
/// plain value: it holds no C pointers and is safe to share across concurrency domains.
public struct MarkdownNode: Sendable, Equatable {
    public var kind: Kind
    public var children: [MarkdownNode]
    /// Where the node came from in the parsed text, or `nil` when cmark did not record it.
    public var sourceRange: SourceRange?

    public init(_ kind: Kind, children: [MarkdownNode] = [], sourceRange: SourceRange? = nil) {
        self.kind = kind
        self.children = children
        self.sourceRange = sourceRange
    }
}

extension MarkdownNode {
    /// Every node type Peep understands: all CommonMark kinds plus the GFM extensions.
    public enum Kind: Sendable, Equatable {
        // MARK: CommonMark blocks

        case document
        case blockQuote
        case list(ListInfo)
        case item
        case codeBlock(CodeBlock)
        /// Raw HTML block, verbatim.
        case htmlBlock(String)
        case paragraph
        case heading(level: Int)
        case thematicBreak

        // MARK: CommonMark inlines

        case text(String)
        case softBreak
        case lineBreak
        /// Inline code span contents.
        case code(String)
        /// Raw inline HTML tag, verbatim.
        case htmlInline(String)
        case emphasis
        case strong
        case link(destination: String, title: String?)
        /// An image; its children are the alt text.
        case image(source: String, title: String?)

        // MARK: GFM extensions

        /// A table. Children are `tableRow`s; the first is the header row.
        case table(alignments: [TableAlignment])
        case tableRow(isHeader: Bool)
        /// A table cell. `alignment` comes from the table's delimiter row for this column.
        case tableCell(alignment: TableAlignment, isHeader: Bool)
        case strikethrough
        /// A list item that starts with `[ ]` or `[x]` (replaces `item`).
        case taskItem(isChecked: Bool)
        /// A footnote reference. `number` is the footnote's 1-based display number and
        /// `referenceIndex` counts references to the same footnote (1 for the first).
        case footnoteReference(label: String, number: Int, referenceIndex: Int)
        /// A footnote definition, moved by cmark to the end of the document in display order.
        case footnoteDefinition(label: String, number: Int, referenceCount: Int)

        // MARK: swift-cmark extensions

        /// Apple's `^[text](attributes)` syntax, which swift-cmark always parses. Children are the
        /// text; cmark's own HTML renderer outputs only the children.
        case attribute(String)

        // MARK: Peep transforms

        /// An emoji shortcode such as `:tada:`, replaced by `EmojiShortcodes` (#10). `shortcode`
        /// is the alias without colons; `character` is the emoji it stands for.
        case emoji(shortcode: String, character: String)
        /// A GitHub alert (`> [!NOTE]`), made from a top-level block quote by `GitHubAlerts`
        /// (#52). Children are the body blocks, without the marker; the renderer writes the title.
        case alert(GitHubAlert)
        /// A wiki link (`[[Page]]`, `[[Page#Heading|label]]`), made from text by `WikiLinks` (#53).
        /// Children are the label (text); `WikiLink.destination` is `nil` for a missing page.
        case wikiLink(WikiLink)
    }
}

extension MarkdownNode.Kind {
    /// Whether this node's children are blocks (block quotes, lists, items, footnotes, alerts):
    /// the containers tree passes descend into to reach nested blocks.
    var isBlockContainer: Bool {
        switch self {
        case .document, .blockQuote, .list, .item, .taskItem, .footnoteDefinition, .alert: true
        default: false
        }
    }
}

/// A 1-based line and column (in UTF-8 bytes) in the parsed text.
public struct SourcePosition: Sendable, Equatable, Comparable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// An inclusive range of positions in the parsed text.
public struct SourceRange: Sendable, Equatable {
    public var start: SourcePosition
    public var end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }
}

public struct ListInfo: Sendable, Equatable {
    public enum Delimiter: Sendable, Equatable {
        case none
        case period
        case parenthesis
    }

    public var isOrdered: Bool
    /// First item number for ordered lists; 0 for bullet lists.
    public var start: Int
    public var delimiter: Delimiter
    /// Tight lists render their item paragraphs without `<p>` tags.
    public var isTight: Bool

    public init(isOrdered: Bool, start: Int = 1, delimiter: Delimiter = .none, isTight: Bool = true) {
        self.isOrdered = isOrdered
        self.start = start
        self.delimiter = delimiter
        self.isTight = isTight
    }
}

public struct CodeBlock: Sendable, Equatable {
    /// The full info string after the opening fence (entities and escapes already resolved).
    public var info: String
    public var literal: String
    public var isFenced: Bool
    /// Syntax-highlighted markup for `literal`, set by the render-time highlighting pass
    /// (`CodeHighlighting`) and written verbatim by `HTMLRenderer`. Internal, so only output that
    /// passed `HighlightValidator` can get here.
    var highlightedHTML: String?

    public init(info: String = "", literal: String, isFenced: Bool) {
        self.info = info
        self.literal = literal
        self.isFenced = isFenced
    }

    /// The first word of the info string, or `nil` when there is none.
    public var language: String? {
        let word = info.prefix { !$0.isCmarkWhitespace }
        return word.isEmpty ? nil : String(word)
    }
}

public enum TableAlignment: Sendable, Equatable {
    case none
    case left
    case center
    case right
}

extension Character {
    /// cmark's `cmark_isspace`: space, tab, newline, vertical tab, form feed, carriage return.
    var isCmarkWhitespace: Bool {
        switch self {
        case " ", "\t", "\n", "\u{0B}", "\u{0C}", "\r", "\r\n": true
        default: false
        }
    }
}

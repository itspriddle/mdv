import cmark_gfm
import cmark_gfm_extensions

/// Parses Markdown into a `MarkdownNode` tree using swift-cmark (cmark-gfm).
///
/// The cmark parser and node tree live only for the duration of `parse(_:)`: both are freed with
/// `defer`, and the returned tree holds no C pointers.
public struct MarkdownParser: Sendable {
    /// Containers nested deeper than this are flattened into their nearest kept ancestor (their
    /// content is kept, their wrapper is dropped). Real documents never come close; the limit
    /// keeps pathological input (e.g. 100k `>` characters) from exhausting the stack when the
    /// tree is rendered, compared, or deallocated.
    public static let maximumNestingDepth = 128

    public var extensions: Set<MarkdownExtension>

    public init(extensions: Set<MarkdownExtension> = []) {
        self.extensions = extensions
    }

    public func parse(_ markdown: String) -> MarkdownNode {
        parse(markdown, allocator: nil)
    }

    /// `allocator` lets tests count cmark allocations to prove every node is freed.
    func parse(_ markdown: String, allocator: UnsafeMutablePointer<cmark_mem>?) -> MarkdownNode {
        cmark_gfm_core_extensions_ensure_registered()

        // Source positions are always recorded. Smart punctuation (CMARK_OPT_SMART) is never
        // enabled: GitHub keeps quotes and dashes as typed.
        let options = extensions.reduce(CMARK_OPT_SOURCEPOS) { $0 | $1.parserOptions }
        let newParser = allocator.map { cmark_parser_new_with_mem(options, $0) } ?? cmark_parser_new(options)
        guard let parser = newParser else {
            return MarkdownNode(.document)
        }
        defer { cmark_parser_free(parser) }

        for name in extensions.compactMap(\.syntaxExtensionName).sorted() {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }

        var source = markdown
        source.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress {
                    cmark_parser_feed(parser, base, chars.count)
                }
            }
        }

        guard let root = cmark_parser_finish(parser) else {
            return MarkdownNode(.document)
        }
        defer { cmark_node_free(root) }

        var builder = TreeBuilder()
        return builder.build(root)
    }
}

private typealias CmarkNode = UnsafeMutablePointer<cmark_node>

/// Copies a cmark tree into `MarkdownNode`s without recursion, so deep input cannot overflow the
/// stack during conversion.
private struct TreeBuilder {
    private var footnoteDefinitionCount = 0
    private var tableAlignments: [TableAlignment] = []
    private var rowIsHeader = false
    private var column = 0

    mutating func build(_ root: CmarkNode) -> MarkdownNode {
        // Nodes still collecting children, innermost last. Index 0 is the document.
        var open = [MarkdownNode(.document, sourceRange: sourceRange(of: root))]
        // One entry per cmark container we descended into: whether it got its own entry in `open`.
        var descended: [Bool] = []

        var cursor = cmark_node_first_child(root)
        while let node = cursor {
            let kind = convert(node)
            if let child = cmark_node_first_child(node) {
                let keep = kind != nil && open.count < MarkdownParser.maximumNestingDepth
                if let kind, keep {
                    open.append(MarkdownNode(kind, sourceRange: sourceRange(of: node)))
                }
                descended.append(keep)
                cursor = child
                continue
            }

            if let kind {
                open[open.count - 1].children.append(MarkdownNode(kind, sourceRange: sourceRange(of: node)))
            }

            // Move to the next sibling, closing finished containers on the way up.
            cursor = nil
            var current = node
            while cursor == nil {
                if let next = cmark_node_next(current) {
                    cursor = next
                } else if let parent = cmark_node_parent(current), parent != root {
                    if descended.removeLast() {
                        let finished = open.removeLast()
                        open[open.count - 1].children.append(finished)
                    }
                    current = parent
                } else {
                    break
                }
            }
        }
        return open[0]
    }

    private func sourceRange(of node: CmarkNode) -> SourceRange? {
        let startLine = Int(cmark_node_get_start_line(node))
        guard startLine > 0 else {
            return nil
        }
        return SourceRange(
            start: SourcePosition(line: startLine, column: Int(cmark_node_get_start_column(node))),
            end: SourcePosition(
                line: Int(cmark_node_get_end_line(node)),
                column: Int(cmark_node_get_end_column(node))
            )
        )
    }

    /// Returns `nil` for nodes mdv does not model (custom nodes); their children are kept.
    private mutating func convert(_ node: CmarkNode) -> MarkdownNode.Kind? {
        if cmark_node_get_syntax_extension(node) != nil, let kind = convertExtension(node) {
            return kind
        }
        switch cmark_node_get_type(node) {
        case CMARK_NODE_DOCUMENT: return .document
        case CMARK_NODE_BLOCK_QUOTE: return .blockQuote
        case CMARK_NODE_LIST: return .list(listInfo(node))
        case CMARK_NODE_ITEM: return .item
        case CMARK_NODE_CODE_BLOCK: return .codeBlock(codeBlock(node))
        case CMARK_NODE_HTML_BLOCK: return .htmlBlock(literal(node))
        case CMARK_NODE_PARAGRAPH: return .paragraph
        case CMARK_NODE_HEADING: return .heading(level: Int(cmark_node_get_heading_level(node)))
        case CMARK_NODE_THEMATIC_BREAK: return .thematicBreak
        case CMARK_NODE_FOOTNOTE_DEFINITION: return footnoteDefinition(node)
        case CMARK_NODE_TEXT: return .text(literal(node))
        case CMARK_NODE_SOFTBREAK: return .softBreak
        case CMARK_NODE_LINEBREAK: return .lineBreak
        case CMARK_NODE_CODE: return .code(literal(node))
        case CMARK_NODE_HTML_INLINE: return .htmlInline(literal(node))
        case CMARK_NODE_EMPH: return .emphasis
        case CMARK_NODE_STRONG: return .strong
        case CMARK_NODE_LINK: return .link(destination: string(cmark_node_get_url(node)), title: title(node))
        case CMARK_NODE_IMAGE: return .image(source: string(cmark_node_get_url(node)), title: title(node))
        case CMARK_NODE_FOOTNOTE_REFERENCE: return footnoteReference(node)
        case CMARK_NODE_ATTRIBUTE: return .attribute(string(cmark_node_get_attributes(node)))
        default: return nil
        }
    }

    /// GFM extension nodes, identified by their extension's type string.
    private mutating func convertExtension(_ node: CmarkNode) -> MarkdownNode.Kind? {
        switch string(cmark_node_get_type_string(node)) {
        case "table":
            tableAlignments = alignments(node)
            return .table(alignments: tableAlignments)
        case "table_header", "table_row":
            rowIsHeader = cmark_gfm_extensions_get_table_row_is_header(node) != 0
            column = 0
            return .tableRow(isHeader: rowIsHeader)
        case "table_cell":
            let alignment = tableAlignments.indices.contains(column) ? tableAlignments[column] : .none
            column += 1
            return .tableCell(alignment: alignment, isHeader: rowIsHeader)
        case "strikethrough":
            return .strikethrough
        case "tasklist":
            return .taskItem(isChecked: cmark_gfm_extensions_get_tasklist_item_checked(node))
        default:
            return nil
        }
    }

    private func listInfo(_ node: CmarkNode) -> ListInfo {
        let delimiter: ListInfo.Delimiter =
            switch cmark_node_get_list_delim(node) {
            case CMARK_PERIOD_DELIM: .period
            case CMARK_PAREN_DELIM: .parenthesis
            default: .none
            }
        return ListInfo(
            isOrdered: cmark_node_get_list_type(node) == CMARK_ORDERED_LIST,
            start: Int(cmark_node_get_list_start(node)),
            delimiter: delimiter,
            isTight: cmark_node_get_list_tight(node) != 0
        )
    }

    private func codeBlock(_ node: CmarkNode) -> CodeBlock {
        var length: Int32 = 0
        var offset: Int32 = 0
        var character: CChar = 0
        let fenced = cmark_node_get_fenced(node, &length, &offset, &character) != 0
        return CodeBlock(info: string(cmark_node_get_fence_info(node)), literal: literal(node), isFenced: fenced)
    }

    private func alignments(_ node: CmarkNode) -> [TableAlignment] {
        let count = Int(cmark_gfm_extensions_get_table_columns(node))
        guard count > 0, let raw = cmark_gfm_extensions_get_table_alignments(node) else {
            return []
        }
        return UnsafeBufferPointer(start: raw, count: count).map { byte in
            switch byte {
            case UInt8(ascii: "l"): .left
            case UInt8(ascii: "c"): .center
            case UInt8(ascii: "r"): .right
            default: .none
            }
        }
    }

    /// cmark (`process_footnotes`) numbers footnotes by first reference in source order, sets a
    /// resolved reference's literal to that number, links it to its definition (whose literal is
    /// the label), and records its index among references to the same definition. Unresolved
    /// references are already plain text.
    private func footnoteReference(_ node: CmarkNode) -> MarkdownNode.Kind {
        let label = cmark_node_parent_footnote_def(node).map(literal) ?? literal(node)
        return .footnoteReference(
            label: label,
            number: Int(literal(node)) ?? 0,
            referenceIndex: Int(node.pointee.footnote.ref_ix)
        )
    }

    /// cmark drops unreferenced definitions and appends the rest to the document in number
    /// order, so a definition's number is its position among them. `def_count` is how many
    /// references point at it.
    private mutating func footnoteDefinition(_ node: CmarkNode) -> MarkdownNode.Kind {
        footnoteDefinitionCount += 1
        return .footnoteDefinition(
            label: literal(node),
            number: footnoteDefinitionCount,
            referenceCount: Int(node.pointee.footnote.def_count)
        )
    }

    private func literal(_ node: CmarkNode) -> String {
        string(cmark_node_get_literal(node))
    }

    private func title(_ node: CmarkNode) -> String? {
        let title = string(cmark_node_get_title(node))
        return title.isEmpty ? nil : title
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }
}

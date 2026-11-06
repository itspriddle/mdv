/// mdv's HTML renderer: parses with `MarkdownParser` and walks the resulting `MarkdownNode` tree.
///
/// Output for CommonMark nodes matches cmark's `cmark_render_html` byte for byte (safe mode for
/// URLs; raw HTML passed through when `RenderOptions.sanitize` is off), so the CommonMark/GFM
/// spec suites can check it directly. Raw HTML is otherwise filtered by `HTMLSanitizer`. GFM
/// tables and strikethrough match cmark too; task lists and footnotes follow
/// `RenderOptions.gfmMarkup`. Later M1 features (emoji, highlighting, source lines) hook in here.
public struct HTMLRenderer: MarkdownRenderer {
    public var options: RenderOptions
    /// Highlights fenced code blocks when `options.highlighting` is on; `nil` renders them plain.
    public var highlighter: (any SyntaxHighlighter)?
    /// Per-render state: the footnote ids of the tree being rendered (set in `render(_:headings:into:)`).
    private(set) var footnoteIDs = FootnoteIDs()

    public init(
        options: RenderOptions = RenderOptions(),
        highlighter: (any SyntaxHighlighter)? = HighlightJSHighlighter.shared
    ) {
        self.options = options
        self.highlighter = highlighter
    }

    public func render(_ markdown: String) -> RenderedDocument {
        let extracted = options.detectsFrontmatter ? Frontmatter.extract(from: markdown) : nil
        let frontmatter = extracted?.frontmatter
        let body = extracted.map { String($0.body) } ?? markdown
        let document = transformed(
            MarkdownParser(extensions: options.extensions).parse(body, lineOffset: frontmatter?.lineCount ?? 0))

        var output = HTMLOutput(capacity: markdown.utf8.count + markdown.utf8.count / 4)
        if let frontmatter, options.frontmatterDisplay == .table {
            FrontmatterHTML.render(frontmatter, into: &output)
        }
        let headings = Heading.collect(in: document)
        render(document, headings: headings, into: &output)
        return RenderedDocument(
            html: output.string,
            title: Self.title(frontmatter: frontmatter, headings: headings),
            headings: headings,
            frontmatter: frontmatter
        )
    }

    /// Renders an already-parsed tree to an HTML fragment.
    public func html(for node: MarkdownNode) -> String {
        let node = transformed(node)
        var output = HTMLOutput()
        render(node, headings: options.headingAnchors ? Heading.collect(in: node) : [], into: &output)
        return output.string
    }

    /// Applies the tree transforms `options` enables (emoji shortcodes), before headings are
    /// collected so heading text and slugs see their result.
    private func transformed(_ node: MarkdownNode) -> MarkdownNode {
        options.emoji ? EmojiShortcodes.replace(in: node) : node
    }

    /// The document title: frontmatter `title` first, then the first non-empty `h1`.
    static func title(frontmatter: Frontmatter?, headings: [Heading]) -> String? {
        frontmatter?.title ?? headings.first { $0.level == 1 && !$0.text.isEmpty }?.text
    }

    /// `headings` are `root`'s headings in document order (`Heading.collect(in:)`); their slugs
    /// become heading ids when `options.headingAnchors` is on.
    private func render(_ root: MarkdownNode, headings: [Heading], into output: inout HTMLOutput) {
        let anchors = options.headingAnchors ? headings : []
        var root = options.sanitize ? HTMLSanitizer().sanitize(root) : root
        if options.highlighting, let highlighter {
            var highlighting = CodeHighlighting(highlighter: highlighter)
            root = highlighting.apply(to: root)
        }
        var renderer = self
        renderer.footnoteIDs = FootnoteIDs(for: root, reserving: Set(anchors.map(\.slug)))
        renderer.walk(root, anchors: anchors, into: &output)
    }

    private func walk(_ root: MarkdownNode, anchors: [Heading], into output: inout HTMLOutput) {
        var anchors = anchors.makeIterator()
        // Walk with an explicit stack rather than recursion so deep trees cannot overflow it.
        var stack: [Step] = [.enter(root, Context())]
        while let step = stack.popLast() {
            switch step {
            case .enter(let node, let context):
                var anchor: String?
                if case .heading = node.kind {
                    anchor = anchors.next()?.slug
                }
                guard renderEnter(node, context, anchor: anchor, into: &output) else {
                    continue
                }
                stack.append(.exit(node, context))
                let childContext = context.forChildren(of: node.kind)
                for (index, child) in node.children.enumerated().reversed() {
                    stack.append(.enter(child, childContext.forChild(child, at: index, of: node, options)))
                }
            case .exit(let node, let context):
                renderExit(node, context, into: &output)
            }
        }
    }
}

// MARK: - Traversal state

extension HTMLRenderer {
    private enum Step {
        case enter(MarkdownNode, Context)
        case exit(MarkdownNode, Context)
    }

    /// What a node needs to know about its ancestors.
    struct Context {
        /// The parent is `strong`; cmark collapses `****x****` into a single `<strong>`.
        var parentIsStrong = false
        /// The parent is a tight list, so this node is one of its items.
        var parentIsTightList = false
        /// The parent is an item of a tight list; paragraphs here render without `<p>`.
        var inTightListItem = false
        /// This table row is the first body row, so it opens `<tbody>`.
        var opensTableBody = false
        /// This paragraph starts a task item: GitHub markup puts the checkbox (checked or not)
        /// inside it rather than directly after `<li>`.
        var taskCheckbox: Bool?
        /// This node is the first footnote definition, so it opens the footnotes section.
        var opensFootnoteSection = false
        /// This paragraph ends a footnote definition, so the back-references go inside it.
        var footnoteBackrefs: FootnoteBackrefs?

        /// The context shared by all children of a node of `kind`.
        func forChildren(of kind: MarkdownNode.Kind) -> Context {
            var child = Context()
            switch kind {
            case .strong:
                child.parentIsStrong = true
            case .list(let info):
                child.parentIsTightList = info.isTight
            case .item, .taskItem:
                child.inTightListItem = parentIsTightList
            default:
                break
            }
            return child
        }

        /// Refines the shared children's context for the child at `index` of `parent`.
        func forChild(_ child: MarkdownNode, at index: Int, of parent: MarkdownNode, _ options: RenderOptions)
            -> Context
        {
            // Body rows follow the header row, and footnote definitions end the document, so the
            // first of each is the one whose previous sibling is something else.
            let previous = index > 0 ? parent.children[index - 1].kind : nil
            var context = self
            switch (parent.kind, child.kind) {
            case (.table, .tableRow(isHeader: false)):
                context.opensTableBody = previous?.isTableBodyRow != true
            case (.taskItem(let isChecked), .paragraph) where index == 0 && options.gfmMarkup == .github:
                context.taskCheckbox = isChecked
            case (_, .footnoteDefinition):
                context.opensFootnoteSection = previous?.isFootnoteDefinition != true
            case (.footnoteDefinition(let label, let number, let referenceCount), .paragraph)
            where index == parent.children.count - 1:
                context.footnoteBackrefs = FootnoteBackrefs(
                    label: label, number: number, referenceCount: referenceCount)
            default:
                break
            }
            return context
        }
    }
}

// MARK: - Node rendering

extension HTMLRenderer {
    /// Writes a node's opening markup. Returns `false` when the node is fully rendered and its
    /// children must not be visited (leaves, and images, whose alt text is written here).
    /// `anchor` is the heading id to write when `node` is a heading and anchors are on.
    private func renderEnter(
        _ node: MarkdownNode, _ context: Context, anchor: String?, into output: inout HTMLOutput
    ) -> Bool {
        switch node.kind {
        case .document, .attribute:
            break
        case .blockQuote:
            openBlock("blockquote", node, into: &output)
            output.raw("\n")
        case .list(let info):
            renderListStart(node, info, into: &output)
        case .item:
            openBlock("li", node, into: &output)
        case .paragraph:
            if !context.inTightListItem {
                openBlock("p", node, into: &output)
            }
            if let isChecked = context.taskCheckbox {
                writeTaskCheckbox(isChecked: isChecked, into: &output)
            }
        case .heading(let level):
            renderHeadingStart(node, level: level, anchor: anchor, into: &output)
        case .emphasis:
            output.raw("<em>")
        case .strong:
            if !context.parentIsStrong {
                output.raw("<strong>")
            }
        case .link(let destination, let title):
            output.raw("<a href=\"")
            writeURL(destination, into: &output)
            if let title {
                output.raw("\" title=\"")
                output.text(title)
            }
            output.raw("\">")
        case .image(let source, let title):
            renderImage(node, source: source, title: title, into: &output)
            return false
        case .codeBlock, .htmlBlock, .thematicBreak, .text, .softBreak, .lineBreak, .code, .htmlInline, .emoji:
            renderLeaf(node, into: &output)
            return false
        case .table, .tableRow, .tableCell, .strikethrough, .taskItem, .footnoteReference, .footnoteDefinition:
            renderExtensionEnter(node, context, into: &output)
        }
        return true
    }

    private func renderExit(_ node: MarkdownNode, _ context: Context, into output: inout HTMLOutput) {
        switch node.kind {
        case .document:
            if node.children.last?.kind.isFootnoteDefinition == true {
                output.raw("</ol>\n</section>\n")
            }
        case .blockQuote:
            output.newlineIfNeeded()
            output.raw("</blockquote>\n")
        case .list(let info):
            output.raw(info.isOrdered ? "</ol>\n" : "</ul>\n")
        case .item:
            output.raw("</li>\n")
        case .paragraph:
            if !context.inTightListItem {
                if let backrefs = context.footnoteBackrefs {
                    output.raw(" ")
                    writeFootnoteBackrefs(backrefs, into: &output)
                }
                output.raw("</p>\n")
            }
        case .heading(let level):
            output.raw("</h\(level)>\n")
        case .emphasis:
            output.raw("</em>")
        case .strong:
            if !context.parentIsStrong {
                output.raw("</strong>")
            }
        case .link:
            output.raw("</a>")
        case .table, .tableRow, .tableCell, .strikethrough, .taskItem, .footnoteReference, .footnoteDefinition:
            renderExtensionExit(node, context, into: &output)
        default:
            break
        }
    }

    private func renderListStart(_ node: MarkdownNode, _ info: ListInfo, into output: inout HTMLOutput) {
        output.newlineIfNeeded()
        output.raw(info.isOrdered ? "<ol" : "<ul")
        if info.isOrdered, info.start != 1 {
            output.raw(" start=\"\(info.start)\"")
        }
        if options.gfmMarkup == .github, node.children.contains(where: \.kind.isTaskItem) {
            output.raw(" class=\"contains-task-list\"")
        }
        writeSourceLine(of: node, into: &output)
        output.raw(">\n")
    }

    private func renderLeaf(_ node: MarkdownNode, into output: inout HTMLOutput) {
        switch node.kind {
        case .codeBlock(let block):
            openBlock("pre", node, into: &output)
            if let language = block.language {
                output.raw("<code class=\"language-")
                output.text(language)
                output.raw("\">")
            } else {
                output.raw("<code>")
            }
            if let highlighted = block.highlightedHTML {
                output.raw(highlighted)
            } else {
                output.text(block.literal)
            }
            output.raw("</code></pre>\n")
        case .htmlBlock(let html):
            // Already sanitized by `HTMLSanitizer` unless `options.sanitize` is off.
            output.newlineIfNeeded()
            output.raw(html)
            output.newlineIfNeeded()
        case .htmlInline(let html):
            // Already sanitized by `HTMLSanitizer` unless `options.sanitize` is off.
            output.raw(html)
        case .thematicBreak:
            output.newlineIfNeeded()
            output.raw("<hr")
            writeSourceLine(of: node, into: &output)
            output.raw(" />\n")
        case .text(let text), .emoji(_, let text):
            output.text(text)
        case .softBreak:
            output.raw(UInt8(ascii: "\n"))
        case .lineBreak:
            output.raw("<br />\n")
        case .code(let code):
            output.raw("<code>")
            output.text(code)
            output.raw("</code>")
        default:
            break
        }
    }

    /// `<hN>`, or with an anchor `<hN id="slug"><a class="anchor" aria-hidden="true"
    /// href="#slug"></a>`; the theme draws the link's hover glyph.
    private func renderHeadingStart(
        _ node: MarkdownNode, level: Int, anchor: String?, into output: inout HTMLOutput
    ) {
        guard let anchor else {
            openBlock("h\(level)", node, into: &output)
            return
        }
        output.newlineIfNeeded()
        output.raw("<h\(level) id=\"")
        output.text(anchor)
        output.raw("\"")
        writeSourceLine(of: node, into: &output)
        output.raw("><a class=\"anchor\" aria-hidden=\"true\" href=\"#")
        output.text(anchor)
        output.raw("\"></a>")
    }

    private func renderImage(_ node: MarkdownNode, source: String, title: String?, into output: inout HTMLOutput) {
        output.raw("<img src=\"")
        writeURL(source, into: &output)
        output.raw("\" alt=\"")
        output.text(plainText(of: node))
        if let title {
            output.raw("\" title=\"")
            output.text(title)
        }
        output.raw("\" />")
    }

    /// Writes `url` percent-encoded, or nothing when its scheme is unsafe (cmark's safe mode).
    private func writeURL(_ url: String, into output: inout HTMLOutput) {
        if !DangerousURL.matches(url) {
            output.url(url)
        }
    }

    /// The plain text of a node's descendants (for image alt text): text, code, and raw HTML
    /// verbatim, breaks as spaces, markup dropped. Escaping is left to the caller.
    private func plainText(of node: MarkdownNode) -> String {
        var text = ""
        var stack = node.children.reversed() as [MarkdownNode]
        while let current = stack.popLast() {
            switch current.kind {
            case .text(let literal), .code(let literal), .htmlInline(let literal), .emoji(_, let literal):
                text += literal
            case .softBreak, .lineBreak:
                text += " "
            default:
                stack.append(contentsOf: current.children.reversed())
            }
        }
        return text
    }
}

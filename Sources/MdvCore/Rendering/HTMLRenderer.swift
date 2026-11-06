/// mdv's HTML renderer: parses with `MarkdownParser` and walks the resulting `MarkdownNode` tree.
///
/// Output for CommonMark nodes matches cmark's `cmark_render_html` byte for byte (safe mode for
/// URLs, raw HTML passed through), so the CommonMark/GFM spec suites can check it directly. Later
/// M1 features (anchors, emoji, sanitizing, highlighting, source lines) hook in here.
public struct HTMLRenderer: MarkdownRenderer {
    public var options: RenderOptions

    public init(options: RenderOptions = RenderOptions()) {
        self.options = options
    }

    public func render(_ markdown: String) -> RenderedDocument {
        let extracted = options.detectsFrontmatter ? Frontmatter.extract(from: markdown) : nil
        let frontmatter = extracted?.frontmatter
        let body = extracted.map { String($0.body) } ?? markdown
        let document = MarkdownParser(extensions: options.extensions)
            .parse(body, lineOffset: frontmatter?.lineCount ?? 0)

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
        var output = HTMLOutput()
        render(node, headings: options.headingAnchors ? Heading.collect(in: node) : [], into: &output)
        return output.string
    }

    /// The document title: frontmatter `title` first, then the first non-empty `h1`.
    static func title(frontmatter: Frontmatter?, headings: [Heading]) -> String? {
        frontmatter?.title ?? headings.first { $0.level == 1 && !$0.text.isEmpty }?.text
    }

    /// `headings` are `root`'s headings in document order (`Heading.collect(in:)`); their slugs
    /// become heading ids when `options.headingAnchors` is on.
    private func render(_ root: MarkdownNode, headings: [Heading], into output: inout HTMLOutput) {
        var anchors = (options.headingAnchors ? headings : []).makeIterator()
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
                stack.append(contentsOf: node.children.reversed().map { .enter($0, childContext) })
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
    private struct Context {
        /// The parent is `strong`; cmark collapses `****x****` into a single `<strong>`.
        var parentIsStrong = false
        /// The parent is a tight list, so this node is one of its items.
        var parentIsTightList = false
        /// The parent is an item of a tight list; paragraphs here render without `<p>`.
        var inTightListItem = false

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
            output.newlineIfNeeded()
            output.raw("<blockquote>\n")
        case .list(let info):
            output.newlineIfNeeded()
            if !info.isOrdered {
                output.raw("<ul>\n")
            } else if info.start == 1 {
                output.raw("<ol>\n")
            } else {
                output.raw("<ol start=\"\(info.start)\">\n")
            }
        case .item:
            output.newlineIfNeeded()
            output.raw("<li>")
        case .paragraph:
            if !context.inTightListItem {
                output.newlineIfNeeded()
                output.raw("<p>")
            }
        case .heading(let level):
            renderHeadingStart(level: level, anchor: anchor, into: &output)
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
        case .codeBlock, .htmlBlock, .thematicBreak, .text, .softBreak, .lineBreak, .code, .htmlInline:
            renderLeaf(node.kind, into: &output)
            return false
        case .table, .tableRow, .tableCell, .strikethrough, .taskItem, .footnoteReference, .footnoteDefinition:
            renderExtensionEnter(node.kind, into: &output)
        }
        return true
    }

    private func renderExit(_ node: MarkdownNode, _ context: Context, into output: inout HTMLOutput) {
        switch node.kind {
        case .blockQuote:
            output.newlineIfNeeded()
            output.raw("</blockquote>\n")
        case .list(let info):
            output.raw(info.isOrdered ? "</ol>\n" : "</ul>\n")
        case .item:
            output.raw("</li>\n")
        case .paragraph:
            if !context.inTightListItem {
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
            renderExtensionExit(node.kind, into: &output)
        default:
            break
        }
    }

    private func renderLeaf(_ kind: MarkdownNode.Kind, into output: inout HTMLOutput) {
        switch kind {
        case .codeBlock(let block):
            output.newlineIfNeeded()
            if let language = block.language {
                output.raw("<pre><code class=\"language-")
                output.text(language)
                output.raw("\">")
            } else {
                output.raw("<pre><code>")
            }
            output.text(block.literal)
            output.raw("</code></pre>\n")
        case .htmlBlock(let html):
            // TODO(#7): sanitize raw HTML with the allowlist instead of passing it through.
            output.newlineIfNeeded()
            output.raw(html)
            output.newlineIfNeeded()
        case .htmlInline(let html):
            // TODO(#7): sanitize raw HTML with the allowlist instead of passing it through.
            output.raw(html)
        case .thematicBreak:
            output.newlineIfNeeded()
            output.raw("<hr />\n")
        case .text(let text):
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
    private func renderHeadingStart(level: Int, anchor: String?, into output: inout HTMLOutput) {
        output.newlineIfNeeded()
        guard let anchor else {
            output.raw("<h\(level)>")
            return
        }
        output.raw("<h\(level) id=\"")
        output.text(anchor)
        output.raw("\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#")
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
            case .text(let literal), .code(let literal), .htmlInline(let literal):
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

// MARK: - GFM extensions

extension HTMLRenderer {
    // TODO(#4): render tables, strikethrough, and task list items. Until then their content
    // renders without the extension's markup (task items as plain list items).
    // TODO(#5): render footnote references and the footnotes section.
    private func renderExtensionEnter(_ kind: MarkdownNode.Kind, into output: inout HTMLOutput) {
        if case .taskItem = kind {
            output.newlineIfNeeded()
            output.raw("<li>")
        }
    }

    private func renderExtensionExit(_ kind: MarkdownNode.Kind, into output: inout HTMLOutput) {
        if case .taskItem = kind {
            output.raw("</li>\n")
        }
    }
}

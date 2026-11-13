// The render pipeline (#51): source to `RenderedDocument`, in the stages VISION documents.

extension HTMLRenderer {
    /// Runs stages 2-6 of the render pipeline on `markdown` (VISION, "Render pipeline"):
    ///
    /// 1. Custom preprocessor (#56, opt-in, whole file): runs *before* this method; its output is
    ///    `markdown` (`render(_:preprocessor:)`). Everything below sees only that output.
    /// 2. Frontmatter extraction (`options.detectsFrontmatter`), for every flavor.
    /// 3. Document overrides (#54, `DocumentOverrides`): the frontmatter's `peep.flavor` beats
    ///    `options.flavor`, so it changes how the body parses (`RenderOptions.applying(_:)`),
    ///    unless the caller pinned it (`options.pinnedOverrides`, #64).
    /// 4. Parse the body with the flavor's extensions (`MarkdownParser`).
    /// 5. AST transforms: the flavor's and `options.builtInPreprocessors`, in `MarkdownTransform`
    ///    order.
    /// 6. HTML: sanitize raw HTML, collect headings and anchors, highlight code, write markup.
    ///    The word count (`WordCount`) reads the same transformed body.
    public func render(_ markdown: String) -> RenderedDocument {
        let extracted = options.detectsFrontmatter ? Frontmatter.extract(from: markdown) : nil
        let frontmatter = extracted?.frontmatter
        let body = extracted.map { String($0.body) } ?? markdown

        let overrides =
            options.appliesDocumentOverrides ? DocumentOverrides(frontmatter: frontmatter) : DocumentOverrides.none
        var renderer = self
        renderer.options = options.applying(overrides)

        let tree = MarkdownParser(extensions: renderer.options.flavor.extensions)
            .parse(body, lineOffset: frontmatter?.lineCount ?? 0)
        let document = renderer.transformed(tree, source: markdown)

        var output = HTMLOutput(capacity: markdown.utf8.count + markdown.utf8.count / 4)
        if let frontmatter, options.frontmatterDisplay == .table {
            FrontmatterHTML.render(frontmatter, into: &output)
        }
        let (headings, blockedRemoteImages) = renderer.render(document, into: &output)
        return RenderedDocument(
            html: output.string,
            title: Self.title(frontmatter: frontmatter, headings: headings),
            headings: headings,
            frontmatter: frontmatter,
            blockedRemoteImages: blockedRemoteImages,
            overrides: overrides,
            flavor: renderer.options.flavor,
            wordCount: WordCount.count(in: document)
        )
    }

    /// Renders an already-parsed tree to an HTML fragment, running `options`' transforms first
    /// (stages 5 and 6 of the pipeline).
    public func html(for node: MarkdownNode) -> String {
        let node = transformed(node)
        var output = HTMLOutput()
        render(node, into: &output)
        return output.string
    }

    /// Stage 5: the AST transforms `options` enables, in pipeline order, before headings are
    /// collected so heading text and slugs see their result.
    /// `source` is the text the tree's source ranges refer to (wiki links check their brackets
    /// against it); `nil` for a tree parsed elsewhere.
    fileprivate func transformed(_ node: MarkdownNode, source: String? = nil) -> MarkdownNode {
        MarkdownTransform.apply(
            to: node, context: TransformContext(options: options, source: source, wikiLinkResolver: wikiLinkResolver))
    }

    /// The document title: frontmatter `title` first, then the first non-empty `h1`.
    static func title(frontmatter: Frontmatter?, headings: [Heading]) -> String? {
        frontmatter?.title ?? headings.first { $0.level == 1 && !$0.text.isEmpty }?.text
    }
}

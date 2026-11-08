// The render pipeline (#51): source to `RenderedDocument`, in the stages VISION documents.

extension HTMLRenderer {
    /// Runs stages 2-6 of the render pipeline on `markdown` (VISION, "Render pipeline"):
    ///
    /// 1. Custom preprocessor (#56, opt-in, whole file): runs *before* this method; its output is
    ///    `markdown` (`render(_:preprocessor:)`). Everything below sees only that output.
    /// 2. Frontmatter extraction (`options.detectsFrontmatter`), for every flavor.
    /// 3. Flavor resolution (`resolvedFlavor(for:)`): `options.flavor` today; frontmatter
    ///    `mdv.flavor` (#54) is applied here, so it can change how the body parses.
    /// 4. Parse the body with the flavor's extensions (`MarkdownParser`).
    /// 5. AST transforms: the flavor's and `options.builtInPreprocessors`, in `MarkdownTransform`
    ///    order.
    /// 6. HTML: sanitize raw HTML, collect headings and anchors, highlight code, write markup.
    public func render(_ markdown: String) -> RenderedDocument {
        let extracted = options.detectsFrontmatter ? Frontmatter.extract(from: markdown) : nil
        let frontmatter = extracted?.frontmatter
        let body = extracted.map { String($0.body) } ?? markdown

        var renderer = self
        renderer.options.flavor = resolvedFlavor(for: frontmatter)

        let tree = MarkdownParser(extensions: renderer.options.flavor.extensions)
            .parse(body, lineOffset: frontmatter?.lineCount ?? 0)
        let document = renderer.transformed(tree)

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
            blockedRemoteImages: blockedRemoteImages
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

    /// Stage 3: the flavor a document renders with. `options.flavor` until #54 reads the
    /// frontmatter's `mdv.flavor` here (through `FlavorRegistry`, falling back to
    /// `options.flavor`, never to a flavor the frontmatter can't name).
    func resolvedFlavor(for frontmatter: Frontmatter?) -> Flavor {
        options.flavor
    }

    /// Stage 5: the AST transforms `options` enables, in pipeline order, before headings are
    /// collected so heading text and slugs see their result.
    fileprivate func transformed(_ node: MarkdownNode) -> MarkdownNode {
        MarkdownTransform.apply(to: node, context: TransformContext(options: options))
    }

    /// The document title: frontmatter `title` first, then the first non-empty `h1`.
    static func title(frontmatter: Frontmatter?, headings: [Heading]) -> String? {
        frontmatter?.title ?? headings.first { $0.level == 1 && !$0.text.isEmpty }?.text
    }
}

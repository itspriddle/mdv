/// Converts Markdown source into a rendered document.
public protocol MarkdownRenderer: Sendable {
    func render(_ markdown: String) -> RenderedDocument
}

/// Feature toggles for parsing and rendering. Later M1 issues add their switches here.
public struct RenderOptions: Sendable, Equatable {
    /// Syntax extensions enabled on top of CommonMark. Defaults to GitHub Flavored Markdown.
    public var extensions: Set<MarkdownExtension>
    /// Markup for GFM extensions whose HTML differs between GitHub and cmark (task lists and
    /// footnotes). `RenderOptions.spec` switches to `.cmark`.
    public var gfmMarkup: GFMMarkup = .github

    public init(extensions: Set<MarkdownExtension> = MarkdownExtension.gfm) {
        self.extensions = extensions
    }
}

/// Which HTML flavor `HTMLRenderer` writes for GFM extensions where GitHub's markup differs from
/// cmark-gfm's reference renderer. Parsing, numbering, and nesting are the same in both.
public enum GFMMarkup: Sendable, Equatable {
    /// GitHub's markup (`task-list-item` classes and labeled checkboxes; plain `<sup>` footnote
    /// references, an `sr-only` "Footnotes" heading, `data-footnote-backref` classes), minus what
    /// github.com adds on top: `user-content-` id prefixes, `rel="nofollow"`, `notranslate`
    /// classes, and the table accessibility wrapper element.
    case github
    /// cmark-gfm's `cmark_render_html` markup, which the spec fixtures expect.
    case cmark
}

/// The output of a `MarkdownRenderer`.
public struct RenderedDocument: Sendable, Equatable {
    /// HTML body fragment (the contents of `<article class="markdown-body">`).
    public var html: String
    /// Document title, from frontmatter or the first `h1` (#8).
    public var title: String?
    /// Headings in document order, with their anchors (#6).
    public var headings: [Heading]

    public init(html: String, title: String? = nil, headings: [Heading] = []) {
        self.html = html
        self.title = title
        self.headings = headings
    }
}

/// A heading in a rendered document, for outlines and anchor links.
public struct Heading: Sendable, Equatable {
    public var level: Int
    /// Plain text of the heading.
    public var text: String
    /// The `id` attribute (slug) of the rendered heading.
    public var anchor: String

    public init(level: Int, text: String, anchor: String) {
        self.level = level
        self.text = text
        self.anchor = anchor
    }
}

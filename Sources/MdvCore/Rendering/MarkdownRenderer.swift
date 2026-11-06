/// Converts Markdown source into a rendered document.
public protocol MarkdownRenderer: Sendable {
    func render(_ markdown: String) -> RenderedDocument
}

/// Feature toggles for parsing and rendering. Later M1 issues add their switches here.
public struct RenderOptions: Sendable, Equatable {
    /// Syntax extensions enabled on top of CommonMark. Defaults to GitHub Flavored Markdown.
    public var extensions: Set<MarkdownExtension>
    /// Strip a leading YAML/TOML frontmatter block before parsing (#8). Turn off for spec
    /// conformance, where a leading `---` block is ordinary Markdown.
    public var detectsFrontmatter = true
    /// How detected frontmatter is shown (#8).
    public var frontmatterDisplay = FrontmatterDisplay.hidden
    /// Markup for GFM extensions whose HTML differs between GitHub and cmark (task lists and
    /// footnotes). `RenderOptions.spec` switches to `.cmark`.
    public var gfmMarkup: GFMMarkup = .github
    /// Give headings GitHub-compatible `id`s and a hover anchor link (#6). `headings` and the
    /// first-`h1` title are filled in either way.
    public var headingAnchors = true
    /// Annotate block elements with the line they start on in the original file (#9), for
    /// scroll sync and position-preserving reload in the app (M2). Off by default, so headless
    /// output (`mdv --html`) and the spec suites stay clean; the app turns it on. See
    /// `HTMLRenderer.writeSourceLine(of:into:)` for the attribute contract.
    public var sourceLines = false

    /// Filter raw HTML through `HTMLSanitizer`'s allowlist. On by default; turn it off only
    /// for trusted input (the spec suites expect raw HTML to pass through).
    public var sanitize: Bool

    public init(extensions: Set<MarkdownExtension> = MarkdownExtension.gfm, sanitize: Bool = true) {
        self.extensions = extensions
        self.sanitize = sanitize
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
    /// Document title: the frontmatter `title` (#8), else the first non-empty `h1` (#6).
    public var title: String?
    /// Headings in document order, with their slugs (#6).
    public var headings: [Heading]
    /// The document's frontmatter, when `RenderOptions.detectsFrontmatter` found one (#8).
    public var frontmatter: Frontmatter?

    public init(html: String, title: String? = nil, headings: [Heading] = [], frontmatter: Frontmatter? = nil) {
        self.html = html
        self.title = title
        self.headings = headings
        self.frontmatter = frontmatter
    }
}

/// A heading in a rendered document, for outlines and anchor links.
public struct Heading: Sendable, Equatable {
    public var level: Int
    /// Plain text of the heading (text and code spans; markup, raw HTML, and image alt dropped).
    public var text: String
    /// The heading's GitHub-compatible `id`, unique within the document. Link to it with `#slug`.
    public var slug: String
    /// 1-based line of the heading in the original file (frontmatter included), or `nil` for a
    /// tree that has no source positions.
    public var sourceLine: Int?

    public init(level: Int, text: String, slug: String, sourceLine: Int? = nil) {
        self.level = level
        self.text = text
        self.slug = slug
        self.sourceLine = sourceLine
    }
}

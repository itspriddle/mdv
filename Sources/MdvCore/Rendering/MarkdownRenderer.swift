/// Converts Markdown source into a rendered document.
public protocol MarkdownRenderer: Sendable {
    func render(_ markdown: String) -> RenderedDocument
}

/// Feature toggles for parsing and rendering. Later M1 issues add their switches here.
public struct RenderOptions: Sendable, Equatable {
    /// Syntax extensions enabled on top of CommonMark.
    public var extensions: Set<MarkdownExtension>
    /// Strip a leading YAML/TOML frontmatter block before parsing (#8). Turn off for spec
    /// conformance, where a leading `---` block is ordinary Markdown.
    public var detectsFrontmatter = true
    /// How detected frontmatter is shown (#8).
    public var frontmatterDisplay = FrontmatterDisplay.hidden
    /// Give headings GitHub-compatible `id`s and a hover anchor link (#6). `headings` and the
    /// first-`h1` title are filled in either way.
    public var headingAnchors = true

    public init(extensions: Set<MarkdownExtension> = []) {
        self.extensions = extensions
    }
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

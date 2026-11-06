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

    public init(extensions: Set<MarkdownExtension> = []) {
        self.extensions = extensions
    }
}

/// The output of a `MarkdownRenderer`.
public struct RenderedDocument: Sendable, Equatable {
    /// HTML body fragment (the contents of `<article class="markdown-body">`).
    public var html: String
    /// Document title, from frontmatter or the first `h1` (#8).
    public var title: String?
    /// Headings in document order, with their anchors (#6).
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

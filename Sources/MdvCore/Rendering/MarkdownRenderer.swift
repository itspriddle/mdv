/// Converts Markdown source into a rendered document.
public protocol MarkdownRenderer: Sendable {
    func render(_ markdown: String) -> RenderedDocument
}

/// Feature toggles for parsing and rendering. Later M1 issues add their switches here.
public struct RenderOptions: Sendable, Equatable {
    /// Syntax extensions enabled on top of CommonMark.
    public var extensions: Set<MarkdownExtension>
    /// Filter raw HTML through `HTMLSanitizer`'s allowlist. On by default; turn it off only
    /// for trusted input (the spec suites expect raw HTML to pass through).
    public var sanitize: Bool

    public init(extensions: Set<MarkdownExtension> = [], sanitize: Bool = true) {
        self.extensions = extensions
        self.sanitize = sanitize
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

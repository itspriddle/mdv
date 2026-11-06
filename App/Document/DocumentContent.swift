import Foundation
import MdvCore

/// A document's source text and its rendered page: what `MarkdownDocument` holds after a read.
/// A plain value, so it can be built off the main thread and tested without AppKit.
struct DocumentContent: Equatable, Sendable {
    let source: String
    let page: RenderedPage

    /// Renders `source`. The page title is the document's own (frontmatter `title`, then the
    /// first `h1`) or `fallbackTitle` (the file name).
    init(
        source: String,
        fallbackTitle: String,
        renderer: some MarkdownRenderer = HTMLRenderer(options: DocumentContent.renderOptions)
    ) {
        self.source = source
        self.page = RenderedPage(rendered: renderer.render(source), fallbackTitle: fallbackTitle)
    }

    /// Decodes UTF-8 file contents and renders them.
    init(data: Data, fallbackTitle: String) throws {
        guard let source = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.init(source: source, fallbackTitle: fallbackTitle)
    }

    /// The app's render options: the defaults plus `data-source-line` annotations, which the
    /// scroll bridge (`WebViewCoordinator`) reads. `mdv --html` leaves them off.
    static var renderOptions: RenderOptions {
        var options = RenderOptions()
        options.sourceLines = true
        return options
    }
}

/// A rendered document as the window shows it.
struct RenderedPage: Equatable, Sendable {
    /// Shown as the window title and the page `<title>`.
    let title: String
    /// The complete HTML page (`HTMLDocument`: CSP, theme, body).
    let html: String
    /// The rendered body fragment alone (the `<article class="markdown-body">` contents), for
    /// swapping content into an already loaded page.
    let body: String
    /// Headings in document order, for the outline and anchor navigation.
    let headings: [Heading]

    init(rendered: RenderedDocument, fallbackTitle: String) {
        let title = rendered.title ?? fallbackTitle
        self.title = title
        self.html = HTMLDocument(title: title, body: rendered.html).html
        self.body = rendered.html
        self.headings = rendered.headings
    }
}

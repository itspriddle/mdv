import Foundation
import MdvCore

/// A document's source text and its rendered page: what `MarkdownDocument` holds after a read.
/// A plain value, so it can be built off the main thread and tested without AppKit.
struct DocumentContent: Equatable, Sendable {
    let source: String
    /// The page with remote images blocked (placeholders, `.viewer` CSP): what every window
    /// shows until the user opts in (#20).
    let page: RenderedPage
    /// The page with `https:` images loaded (`ContentSecurityPolicy.viewerAllowingRemoteImages`),
    /// for windows that opted in; `nil` when `page` blocked no `https:` image. Rendered with
    /// `page` (off the main thread on live reload) so opting in and reloading never render on
    /// main; only documents with remote images pay for it.
    let remoteImagesPage: RenderedPage?

    /// Renders `source`. The page title is the document's own (frontmatter `title`, then the
    /// first `h1`) or `fallbackTitle` (the file name).
    init(source: String, fallbackTitle: String) {
        self.source = source
        let page = Self.render(source, fallbackTitle: fallbackTitle, allowingRemoteImages: false)
        self.page = page
        remoteImagesPage =
            page.blockedRemoteImages.contains(where: \.isHTTPS)
            ? Self.render(source, fallbackTitle: fallbackTitle, allowingRemoteImages: true) : nil
    }

    /// The page for a window, depending on whether it opted in to remote images.
    func page(allowingRemoteImages: Bool) -> RenderedPage {
        allowingRemoteImages ? remoteImagesPage ?? page : page
    }

    private static func render(_ source: String, fallbackTitle: String, allowingRemoteImages: Bool) -> RenderedPage {
        let options = renderOptions(allowingRemoteImages: allowingRemoteImages)
        return RenderedPage(
            rendered: HTMLRenderer(options: options).render(source), fallbackTitle: fallbackTitle,
            contentSecurityPolicy: allowingRemoteImages ? .viewerAllowingRemoteImages : .viewer)
    }

    /// Decodes UTF-8 file contents and renders them.
    init(data: Data, fallbackTitle: String) throws {
        guard let source = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.init(source: source, fallbackTitle: fallbackTitle)
    }

    /// The app's render options: the defaults plus `data-source-line` annotations, which the
    /// scroll bridge (`WebViewCoordinator`) reads, and remote images blocked (placeholders)
    /// unless the window opted in, then `https:` only. `mdv --html` leaves both off.
    static func renderOptions(allowingRemoteImages: Bool = false) -> RenderOptions {
        var options = RenderOptions()
        options.sourceLines = true
        options.remoteImages = allowingRemoteImages ? .allowHTTPS : .block
        return options
    }
}

/// A rendered document as the window shows it.
struct RenderedPage: Equatable, Sendable {
    /// Shown as the window title and the page `<title>`.
    let title: String
    /// The complete HTML page (`HTMLDocument`: the CSP, theme, body).
    let html: String
    /// The page's CSP: `.viewer`, or `.viewerAllowingRemoteImages` after the window opted in.
    /// Changing it needs a full `load`; `replaceContent` keeps the loaded page's CSP.
    let contentSecurityPolicy: ContentSecurityPolicy
    /// The rendered body fragment alone (the `<article class="markdown-body">` contents), for
    /// swapping content into an already loaded page.
    let body: String
    /// Headings in document order, for the outline and anchor navigation.
    let headings: [Heading]
    /// Remote images shown as placeholders (#20); the remote images bar offers to load the
    /// `https:` ones.
    let blockedRemoteImages: [RemoteImage]

    init(
        rendered: RenderedDocument, fallbackTitle: String, contentSecurityPolicy: ContentSecurityPolicy = .viewer
    ) {
        let title = rendered.title ?? fallbackTitle
        self.title = title
        self.html = HTMLDocument(title: title, body: rendered.html, contentSecurityPolicy: contentSecurityPolicy).html
        self.contentSecurityPolicy = contentSecurityPolicy
        self.body = rendered.html
        self.headings = rendered.headings
        self.blockedRemoteImages = rendered.blockedRemoteImages
    }
}

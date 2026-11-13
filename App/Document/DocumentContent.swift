import Foundation
import PeepCore

/// A document's source text and its rendered page: what `MarkdownDocument` holds after a read.
/// A plain value, so it can be built off the main thread and tested without AppKit.
struct DocumentContent: Equatable, Sendable {
    /// The file's text.
    let source: String
    /// The Markdown the pages were rendered from: the custom preprocessor's output (#57), else
    /// `source`. Copy as HTML renders it again.
    let renderedSource: String
    /// Why the custom preprocessor failed, when it did: the pages are then `source` rendered
    /// without it, and the window shows a bar with the reason (`PreprocessorFailureBar`).
    let preprocessorError: PreprocessorError?
    /// The page with remote images blocked (placeholders, `.viewer` CSP): what every window
    /// shows until the user opts in (#20).
    let page: RenderedPage
    /// The page with `https:` images loaded (`ContentSecurityPolicy.viewerAllowingRemoteImages`),
    /// for windows that opted in; `nil` when `page` blocked no `https:` image. Rendered with
    /// `page` (off the main thread on live reload) so opting in and reloading never render on
    /// main; only documents with remote images pay for it.
    let remoteImagesPage: RenderedPage?
    /// The Settings > Markdown preferences (#55) both pages were rendered with. A document
    /// whose content doesn't match the current settings renders again
    /// (`MarkdownDocument.setContent(_:)`).
    let preferences: MarkdownPreferences

    /// Renders `source`. The page title is the document's own (frontmatter `title`, then the
    /// first `h1`) or `fallbackTitle` (the file name). Root-relative links and images
    /// (`/docs/x.png`) resolve against `linkRoot`, the document's allowed root
    /// (`linkRoot(forDocumentAt:)`), as GitHub resolves them against the repository.
    /// `preferences` are Settings > Markdown's (#55): the default flavor, frontmatter display,
    /// and built-in preprocessors. Wiki links (#53), when Settings or the document's frontmatter
    /// turn them on, are resolved now, from `documentURL`'s folder and `linkRoot`
    /// (`DocumentWikiLinks`); without a `documentURL` every page link is missing.
    ///
    /// This never runs the custom preprocessor (`preferences.customPreprocessor`); that is
    /// asynchronous, in `rendering(_:of:preferences:)`.
    init(
        source: String, fallbackTitle: String, linkRoot: String? = nil, preferences: MarkdownPreferences = .default,
        documentURL: URL? = nil
    ) {
        self.init(
            source: source, renderedSource: source, preprocessorError: nil, fallbackTitle: fallbackTitle,
            linkRoot: linkRoot, preferences: preferences, documentURL: documentURL)
    }

    /// Renders `renderedSource` (the custom preprocessor's output, or `source`) as the content of
    /// a file whose text is `source`.
    init(
        source: String, renderedSource: String, preprocessorError: PreprocessorError?, fallbackTitle: String,
        linkRoot: String?, preferences: MarkdownPreferences, documentURL: URL?
    ) {
        self.source = source
        self.renderedSource = renderedSource
        self.preprocessorError = preprocessorError
        self.preferences = preferences
        let options = Self.renderOptions(preferences: preferences, linkRoot: linkRoot)
        let resolver = DocumentWikiLinks.resolver(forDocumentAt: documentURL, linkRoot: linkRoot)
        let page = Self.render(
            renderedSource, fallbackTitle: fallbackTitle, options: options, resolver: resolver,
            allowingRemoteImages: false)
        self.page = page
        remoteImagesPage =
            page.blockedRemoteImages.contains(where: \.isHTTPS)
            ? Self.render(
                renderedSource, fallbackTitle: fallbackTitle, options: options, resolver: resolver,
                allowingRemoteImages: true)
            : nil
    }

    /// The folder root-relative URLs resolve against for the document at `fileURL`: the same
    /// allowed root its images are served from (`LocalResourceRoot`: the git work tree, else the
    /// document's folder). Nil without a file.
    static func linkRoot(forDocumentAt fileURL: URL?) -> String? {
        fileURL.flatMap { LocalResourceRoot.forDocument(at: $0) }
    }

    /// The page for a window, depending on whether it opted in to remote images.
    func page(allowingRemoteImages: Bool) -> RenderedPage {
        allowingRemoteImages ? remoteImagesPage ?? page : page
    }

    private static func render(
        _ source: String, fallbackTitle: String, options: RenderOptions, resolver: (any WikiLinkResolver)?,
        allowingRemoteImages: Bool
    ) -> RenderedPage {
        var options = options
        options.remoteImages = allowingRemoteImages ? .allowHTTPS : .block
        return RenderedPage(
            rendered: HTMLRenderer(options: options, wikiLinkResolver: resolver).render(source),
            fallbackTitle: fallbackTitle,
            contentSecurityPolicy: allowingRemoteImages ? .viewerAllowingRemoteImages : .viewer)
    }

    /// Decodes UTF-8 file contents and renders them.
    init(
        data: Data, fallbackTitle: String, linkRoot: String? = nil, preferences: MarkdownPreferences = .default
    ) throws {
        self.init(
            source: try Self.source(from: data), fallbackTitle: fallbackTitle, linkRoot: linkRoot,
            preferences: preferences)
    }

    /// Decodes file contents as UTF-8, the only encoding Peep reads. Throws
    /// `CocoaError(.fileReadInapplicableStringEncoding)` for anything else. Cheap next to
    /// rendering (a few milliseconds for 5 MB), so `MarkdownDocument` decodes on the main thread
    /// and its open still fails with NSDocument's own error.
    static func source(from data: Data) throws -> String {
        guard let source = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return source
    }

    /// The app's render options: the default options with Settings > Markdown's `preferences`
    /// (#55: the default flavor, which a document's frontmatter can still override, #54;
    /// frontmatter display; built-in preprocessors), plus `data-source-line` annotations, which the
    /// scroll bridge (`WebViewCoordinator`) reads, and remote images blocked (placeholders)
    /// unless the window opted in, then `https:` only, and root-relative URLs resolved against
    /// `linkRoot`. `peep --html` leaves the last three off.
    static func renderOptions(
        preferences: MarkdownPreferences = .default, allowingRemoteImages: Bool = false, linkRoot: String? = nil
    ) -> RenderOptions {
        var options = RenderOptions()
        preferences.apply(to: &options)
        options.sourceLines = true
        options.remoteImages = allowingRemoteImages ? .allowHTTPS : .block
        options.linkRoot = linkRoot
        return options
    }
}

/// A rendered document as the window shows it, without a theme (`html(theme:)`).
struct RenderedPage: Equatable, Sendable {
    /// Shown as the window title and the page `<title>`.
    let title: String
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
    /// The theme the document's frontmatter names (`peep.theme`, #54), unresolved. Each window
    /// resolves it like a pick, below the reader's own pick (`DocumentWindowController.themeID`).
    let documentThemeID: String?
    /// The words in the rendered body (`RenderedDocument.wordCount`), for the status bar.
    let wordCount: Int

    init(
        rendered: RenderedDocument, fallbackTitle: String, contentSecurityPolicy: ContentSecurityPolicy = .viewer
    ) {
        self.title = rendered.title ?? fallbackTitle
        self.contentSecurityPolicy = contentSecurityPolicy
        self.body = rendered.html
        self.headings = rendered.headings
        self.blockedRemoteImages = rendered.blockedRemoteImages
        self.documentThemeID = rendered.overrides.theme
        self.wordCount = rendered.wordCount
    }

    /// The complete HTML page (`HTMLDocument`: the CSP, `theme`, `userStyle`, body). The
    /// rendered content is the document's, shared by its windows; the theme is each window's
    /// own (#34), so the page is put together when a window loads it.
    func html(theme: Theme, userStyle: UserStyle = .themeDefaults) -> String {
        HTMLDocument(
            title: title, body: body, theme: theme, userStyle: userStyle, contentSecurityPolicy: contentSecurityPolicy
        ).html
    }
}

import AppKit
import MdvCore
import WebKit

/// Owns one window's `WKWebView`: loads pages, swaps content in place, and talks to the page
/// through the app-script bridge (`WebViewCoordinator+Bridge.swift`). It is the web view's
/// navigation and UI delegate; the navigation policy lives in `WebViewCoordinator+Navigation.swift`.
///
/// One per document window, created and kept by `DocumentWindowController`. The SwiftUI view
/// tree only embeds `webView` (`MarkdownWebView`); it never loads content.
@MainActor
final class WebViewCoordinator: NSObject {
    let webView: DocumentWebView

    /// Serves this window's `mdv-doc` URLs (scoped local images).
    let localResources: LocalResourceSchemeHandler

    /// Whether a page has finished loading. Bridge calls need a loaded page.
    private(set) var hasLoadedPage = false

    /// The main-frame URL of the load this coordinator started and has not yet allowed.
    /// The navigation policy allows exactly that one `.other` navigation per load.
    var expectedLoadURL: URL?

    /// Called after the web content process exits; the owner loads the page again.
    var webContentProcessDidTerminate: (@MainActor () -> Void)?

    private var pendingLoads: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    // MARK: Theme (#34)

    /// The theme this web view shows: every full load embeds it, and `show(_:)` swaps a new one
    /// into the loaded page in place. Paints the under-page area.
    private(set) var theme: Theme
    /// The theme in the loaded page's `mdv-theme` style element; nil for a page that isn't a
    /// rendered document (the first-load preparation page, test pages).
    private(set) var loadedTheme: Theme?
    /// The in-place swap `show(_:)` started, if any (for tests).
    private(set) var pendingThemeSwap: Task<Void, Never>?

    // MARK: Links (#19, `WebViewCoordinator+Navigation.swift`)

    /// What the window's link status overlay shows (hovered link, link messages).
    let linkStatus = LinkStatus()
    /// The shown document's file, so links to it stay in-page. Set by the window controller.
    var documentFileURL: URL?
    /// Performs every link action except in-page scrolling (opening documents and URLs).
    var linkHandler: ((LinkAction, LinkOpening) -> Void)?

    /// The reader's style controls (#37) every page this coordinator loads starts with. Set it
    /// before the first load; after a change, `applyUserStyleToPage()`
    /// (`WebViewCoordinator+UserStyle.swift`) updates the loaded page in place.
    var userStyle = UserStyle.themeDefaults

    /// Find in page (#25, `WebViewCoordinator+Find.swift`): the find bar's state and commands,
    /// sharing the system find pasteboard (#42).
    private(set) lazy var find = FindInPage(host: self, pasteboard: NSPasteboard(name: .find))

    /// - Parameter configuration: a fresh configuration (`WebViewConfiguration.make()`); this
    ///   coordinator installs its own `mdv-doc` scheme handler on it, so it can't be reused.
    init(
        configuration: WKWebViewConfiguration = WebViewConfiguration.make(),
        theme: Theme = ThemeRegistry.bundled.defaultTheme
    ) {
        self.theme = theme
        let localResources = LocalResourceSchemeHandler()
        configuration.setURLSchemeHandler(localResources, forURLScheme: DocumentURLScheme.name)
        self.localResources = localResources
        webView = DocumentWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        // Pinch-to-zoom: each window's own magnification (#26).
        webView.allowsMagnification = true
        // Behind and around the page (rubber-band overscroll): the theme background.
        webView.themeUnderPageBackgroundColor = .themeBackground(theme.background)
        // A fresh WKWebView paints white until its first page draws. Keep it hidden until then,
        // so the window's theme-colored background shows instead (no white flash in dark mode).
        webView.isHidden = true
        webView.setAccessibilityIdentifier("document-web-view")
        webView.copyLinkHandler = { [weak self] in self?.copyContextMenuLink() }
        // Hover reports from `LinkHover.js`, accepted from the app's content world only.
        webView.configuration.userContentController.add(
            LinkHoverMessageHandler(coordinator: self), contentWorld: AppScripts.world,
            name: LinkHoverMessageHandler.name)
    }

    /// Scopes local image access to the document at `fileURL` (its `LocalResourceRoot`) and
    /// returns the `mdv-doc` URL to load its page at (the `baseURL` for `load`), so relative
    /// images resolve against the document. Nil, and no local images, when there is no file.
    func documentURL(forFileAt fileURL: URL?) -> URL? {
        localResources.scope(toDocumentAt: fileURL)
    }

    /// The URL of the blank page `prepareForFirstLoad()` loads: distinct from every real load's
    /// URL (`about:blank` without a base URL), so the navigation policy's one allowed load per
    /// `expectedLoadURL` stays unambiguous.
    static let preparationURL = URL(string: "about:blank#mdv-prepare")

    /// Starts the web view's first load, of an empty page, before there is a page to show (the
    /// document is still rendering off the main actor, #32). A web view's first load costs a
    /// fixed 15-30 ms on the main thread (attaching its web content process); paying it here,
    /// while the window is built, overlaps it with the render, so the page load after the
    /// render is cheap. The next `load` replaces the page, finished or not. Does nothing once a
    /// load has started.
    func prepareForFirstLoad() {
        guard !hasLoadedPage, expectedLoadURL == nil, webView.url == nil else {
            return
        }
        expectedLoadURL = Self.preparationURL
        webView.loadHTMLString(
            #"<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'"><title></title>"#,
            baseURL: Self.preparationURL)
    }

    /// Loads a full page and waits for it to finish. Replaces whatever was loaded, including the
    /// scroll position; use `replaceContent(with:)` to keep it.
    ///
    /// - Parameter baseURL: resolves relative URLs in the page: the document's
    ///   `documentURL(forFileAt:)`.
    ///
    /// The page gets the current `theme` and `userStyle`, so a load never paints another look
    /// first and then jumps. If either changed while it loaded, it is swapped in before this
    /// returns. The page text is put together off the main actor: for a large document,
    /// joining it with the styles takes milliseconds (#32).
    func load(_ page: RenderedPage, baseURL: URL?) async throws {
        let theme = theme
        let style = userStyle
        let html = await Task.detached(priority: .userInitiated) {
            page.html(theme: theme, userStyle: style)
        }.value
        try await load(html: html, baseURL: baseURL)
        loadedTheme = theme
        // The theme or the style changed while the page was loading.
        try await swapThemeIfNeeded()
        if userStyle != style {
            try await applyUserStyleToPage()
        }
    }

    /// Loads a complete HTML page and waits for it to finish. `html` must be a page built by
    /// `HTMLDocument` (CSP, theme); tests also use it for hand-written hostile pages.
    func load(html: String, baseURL: URL?) async throws {
        loadedTheme = nil
        expectedLoadURL = baseURL ?? URL(string: "about:blank")
        LaunchTiming.mark("loadStarted")
        guard let navigation = webView.loadHTMLString(html, baseURL: baseURL) else {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            pendingLoads[ObjectIdentifier(navigation)] = continuation
        }
        hasLoadedPage = true
        webView.isHidden = false
    }

    /// Shows `theme`: paints the under-page area at once and swaps the theme into the loaded
    /// page in place (`DocumentBridge.js` `replaceTheme`), keeping the reading position, the
    /// find highlights, the zoom, and the page's CSP. No reload. Without a loaded page, the next
    /// `load` uses it.
    func show(_ theme: Theme) {
        guard theme != self.theme else {
            return
        }
        self.theme = theme
        webView.themeUnderPageBackgroundColor = .themeBackground(theme.background)
        pendingThemeSwap = Task { [weak self] in
            try? await self?.swapThemeIfNeeded()
        }
    }

    /// Swaps `theme` into the loaded page if the page has another one. Runs after every load
    /// and theme change, so whichever finishes last, the page ends with the current theme.
    private func swapThemeIfNeeded() async throws {
        guard hasLoadedPage, let loadedTheme, loadedTheme != theme else {
            return
        }
        let theme = theme
        let swapped = try await replaceTheme(css: theme.layerCSS)
        if swapped {
            self.loadedTheme = theme
        }
    }

    enum LoadError: Error, Equatable {
        /// The web content process exited before the page finished loading.
        case webContentProcessTerminated
    }

    private func finish(_ navigation: WKNavigation?, error: (any Error)?) {
        guard let navigation, let continuation = pendingLoads.removeValue(forKey: ObjectIdentifier(navigation))
        else {
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

extension WebViewCoordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(policy(for: navigationAction))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish(navigation, error: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        finish(navigation, error: error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        finish(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        for continuation in pendingLoads.values {
            continuation.resume(throwing: LoadError.webContentProcessTerminated)
        }
        pendingLoads.removeAll()
        hasLoadedPage = false
        webContentProcessDidTerminate?()
    }
}

extension WebViewCoordinator: WKUIDelegate {
    /// The viewer never opens web view windows (`target="_blank"`, `window.open`). The context
    /// menu's "Open Link in New Window" lands here: it follows the link through the navigation
    /// policy, as a new-tab open.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            followLink(url, opening: .newTab)
        }
        return nil
    }
}

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

    // MARK: Links (#19, `WebViewCoordinator+Navigation.swift`)

    /// What the window's link status overlay shows (hovered link, link messages).
    let linkStatus = LinkStatus()
    /// The shown document's file, so links to it stay in-page. Set by the window controller.
    var documentFileURL: URL?
    /// Performs every link action except in-page scrolling (opening documents and URLs).
    var linkHandler: ((LinkAction, LinkOpening) -> Void)?

    /// - Parameter configuration: a fresh configuration (`WebViewConfiguration.make()`); this
    ///   coordinator installs its own `mdv-doc` scheme handler on it, so it can't be reused.
    init(configuration: WKWebViewConfiguration = WebViewConfiguration.make()) {
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
        webView.underPageBackgroundColor = .themeBackground
        // A fresh WKWebView paints white until its first page draws. Keep it hidden until then,
        // so the window's theme-colored background shows instead (no white flash in dark mode).
        webView.isHidden = true
        webView.setAccessibilityIdentifier("document-web-view")
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

    /// Loads a full page and waits for it to finish. Replaces whatever was loaded, including the
    /// scroll position; use `replaceContent(with:)` to keep it.
    ///
    /// - Parameter baseURL: resolves relative URLs in the page: the document's
    ///   `documentURL(forFileAt:)`.
    func load(_ page: RenderedPage, baseURL: URL?) async throws {
        try await load(html: page.html, baseURL: baseURL)
    }

    /// Loads a complete HTML page and waits for it to finish. `html` must be a page built by
    /// `HTMLDocument` (CSP, theme); tests also use it for hand-written hostile pages.
    func load(html: String, baseURL: URL?) async throws {
        expectedLoadURL = baseURL ?? URL(string: "about:blank")
        guard let navigation = webView.loadHTMLString(html, baseURL: baseURL) else {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            pendingLoads[ObjectIdentifier(navigation)] = continuation
        }
        hasLoadedPage = true
        webView.isHidden = false
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

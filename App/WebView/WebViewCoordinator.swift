import AppKit
import WebKit

/// Owns one window's `WKWebView`: loads pages, swaps content in place, and talks to the page
/// through the app-script bridge (`WebViewCoordinator+Bridge.swift`). It is the web view's
/// navigation and UI delegate; the navigation policy lives in `WebViewCoordinator+Navigation.swift`.
///
/// One per document window, created and kept by `DocumentWindowController`. The SwiftUI view
/// tree only embeds `webView` (`MarkdownWebView`); it never loads content.
@MainActor
final class WebViewCoordinator: NSObject {
    let webView: WKWebView

    /// Whether a page has finished loading. Bridge calls need a loaded page.
    private(set) var hasLoadedPage = false

    /// The main-frame URL of the load this coordinator started and has not yet allowed.
    /// The navigation policy allows exactly that one `.other` navigation per load.
    var expectedLoadURL: URL?

    /// Called after the web content process exits; the owner loads the page again.
    var webContentProcessDidTerminate: (@MainActor () -> Void)?

    private var pendingLoads: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    init(configuration: WKWebViewConfiguration = WebViewConfiguration.make()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        // Behind and around the page (rubber-band overscroll): the theme background.
        webView.underPageBackgroundColor = .themeBackground
        // A fresh WKWebView paints white until its first page draws. Keep it hidden until then,
        // so the window's theme-colored background shows instead (no white flash in dark mode).
        webView.isHidden = true
        webView.setAccessibilityIdentifier("document-web-view")
    }

    /// Loads a full page and waits for it to finish. Replaces whatever was loaded, including the
    /// scroll position; use `replaceContent(with:)` to keep it.
    ///
    /// - Parameter baseURL: resolves relative URLs in the page (the document's folder).
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
    /// The viewer never opens new windows (`target="_blank"`, `window.open`).
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

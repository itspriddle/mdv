import WebKit

extension WebViewCoordinator {
    /// Decides every navigation in the document web view. The main frame never leaves the
    /// rendered document.
    ///
    /// Interim policy until #19: allow the page loads this coordinator starts and same-document
    /// fragment links (in-page anchors); cancel everything else.
    ///
    /// TODO(#19): replace with the tested navigation policy (open external links in the browser,
    /// local Markdown links in mdv, `#foo` fallback to `#user-content-foo` via `scroll(toFragment:)`).
    func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard action.targetFrame?.isMainFrame == true, let url = action.request.url else {
            return .cancel
        }
        if action.navigationType == .other, url == expectedLoadURL {
            expectedLoadURL = nil
            return .allow
        }
        if action.navigationType == .linkActivated, url.fragment != nil, let current = webView.url,
            url.withoutFragment == current.withoutFragment
        {
            return .allow
        }
        return .cancel
    }
}

extension URL {
    /// This URL without its `#fragment`.
    var withoutFragment: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
    }
}

import AppKit
import PeepCore
import WebKit

/// How a link was followed, which decides where it opens.
enum LinkOpening: Equatable {
    /// A plain click: a local document opens the way the system opens documents (window or tab).
    case normal
    /// Cmd-click, middle-click, or the context menu's "Open Link in New Window": a local document
    /// opens in a new tab of this window, and a web link opens without activating the browser.
    case newTab

    init(modifiers: NSEvent.ModifierFlags, buttonNumber: Int) {
        // Button 2 is the middle button (0 left, 1 right).
        self = modifiers.contains(.command) || buttonNumber == 2 ? .newTab : .normal
    }
}

extension WebViewCoordinator {
    /// Where the shown document lives, for `LinkPolicy`. The page is served at
    /// `peep-doc://<token>/<absolute path>` (#18), so links resolve to `peep-doc` URLs; this
    /// window's token maps them back to files and folders (`DocumentURLScheme.fileURL(from:token:)`;
    /// a folder link such as `sub/` is revealed in Finder). Any other `peep-doc` URL (another token, an unclean path) names no file and is blocked, and so
    /// are `file:` URLs, which a document can't produce (cmark's safe mode and the sanitizer drop
    /// them).
    var linkContext: LinkContext {
        let token = localResources.token
        return LinkContext(pageURL: webView.url?.withoutFragment, documentFileURL: documentFileURL) { url in
            DocumentURLScheme.fileURL(from: url, token: token)
        }
    }

    /// Decides every navigation in the document web view. The main frame never leaves the
    /// rendered document: the only navigations allowed are the page loads this coordinator
    /// starts. Link clicks are cancelled and handled by `followLink(_:opening:)`; everything
    /// else (reloads, form submissions, back/forward, redirects, subframes) is cancelled.
    func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else {
            return .cancel
        }
        let targetsMainFrame = action.targetFrame?.isMainFrame ?? true
        if action.targetFrame?.isMainFrame == true, action.navigationType == .other, isExpectedLoad(url) {
            expectedLoadURL = nil
            return .allow
        }
        if action.navigationType == .linkActivated, targetsMainFrame {
            followLink(url, opening: LinkOpening(modifiers: action.modifierFlags, buttonNumber: action.buttonNumber))
        }
        return .cancel
    }

    /// Whether `url` is the load this coordinator started: `expectedLoadURL`, or the preparation
    /// page in either of WebKit's spellings (`isPreparationURL(_:)`).
    func isExpectedLoad(_ url: URL) -> Bool {
        guard let expectedLoadURL else {
            return false
        }
        if expectedLoadURL == Self.preparationURL {
            return Self.isPreparationURL(url)
        }
        return url == expectedLoadURL
    }

    /// Follows a clicked link through `LinkPolicy`: in-page fragments scroll here; every other
    /// action goes to `linkHandler` (the window controller).
    func followLink(_ url: URL, opening: LinkOpening) {
        let action = LinkPolicy.action(for: url, in: linkContext)
        guard case .scrollToFragment(let fragment) = action else {
            linkHandler?(action, opening)
            return
        }
        Task {
            let found = (try? await scroll(toFragment: fragment)) ?? false
            if !found {
                linkStatus.show(message: "No section named “#\(fragment.removingPercentEncoding ?? fragment)”")
            }
        }
    }
}

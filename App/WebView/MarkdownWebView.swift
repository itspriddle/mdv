import SwiftUI
import WebKit

/// Embeds a window's web view in SwiftUI. Loading and scrolling go through the
/// `WebViewCoordinator` that owns the view, never through SwiftUI updates.
struct MarkdownWebView: NSViewRepresentable {
    let coordinator: WebViewCoordinator

    func makeNSView(context: Context) -> WKWebView {
        coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

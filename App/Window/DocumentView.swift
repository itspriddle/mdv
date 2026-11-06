import SwiftUI

/// The content of a document window. Window chrome that later features add (outline sidebar,
/// find bar, banners) composes around the web view here; the document is `@Observable`, so
/// views can read `document.content` directly.
struct DocumentView: View {
    let document: MarkdownDocument
    let coordinator: WebViewCoordinator

    var body: some View {
        MarkdownWebView(coordinator: coordinator)
            .frame(minWidth: 480, minHeight: 360)
            .overlay(alignment: .bottomLeading) { LinkStatusView(status: coordinator.linkStatus) }
    }
}

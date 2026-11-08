import SwiftUI

/// The content of a document window. Window chrome that later features add (outline sidebar,
/// find bar, banners) composes around the web view here; the document is `@Observable`, so
/// views can read `document.content` directly.
struct DocumentView: View {
    let document: MarkdownDocument
    let coordinator: WebViewCoordinator
    let remoteImages: RemoteImageOptIn
    let loadRemoteImages: () -> Void

    var body: some View {
        MarkdownWebView(coordinator: coordinator)
            .frame(minWidth: 480, minHeight: 360)
            .safeAreaInset(edge: .top, spacing: 0) { FileStatusBanner(status: document.fileStatus) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = document.content?.preprocessorError {
                    PreprocessorFailureBar(error: error)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let summary = remoteImages.bar(for: document.content?.page) {
                    RemoteImageBar(summary: summary, load: loadRemoteImages)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { FindBar(find: coordinator.find) }
            .overlay(alignment: .bottomLeading) { LinkStatusView(status: coordinator.linkStatus) }
    }
}

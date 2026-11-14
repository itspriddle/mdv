import SwiftUI

/// The content of a document window. Window chrome that later features add (outline sidebar,
/// find bar, banners, status bar) composes around the web view here; the document is `@Observable`, so
/// views can read `document.content` directly.
struct DocumentView: View {
    let document: MarkdownDocument
    let coordinator: WebViewCoordinator
    let remoteImages: RemoteImageOptIn
    let renderProgress: RenderProgress
    let statusBar: StatusBarModel
    let chrome: WindowChrome
    let loadRemoteImages: () -> Void
    let toggleOutline: () -> Void
    let togglePinned: () -> Void

    var body: some View {
        MarkdownWebView(coordinator: coordinator)
            .overlay { RenderProgressIndicator(progress: renderProgress) }
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
            // Outermost, so it sits right under the titlebar (or the tab bar).
            .safeAreaInset(edge: .top, spacing: 0) { ChromeBorder(chrome: chrome) }
            .overlay(alignment: .bottomLeading) { LinkStatusView(status: coordinator.linkStatus) }
            // After the link status overlay, so it floats above the bar rather than over it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if statusBar.isVisible {
                    StatusBar(
                        document: document, model: statusBar, chrome: chrome, toggleOutline: toggleOutline,
                        togglePinned: togglePinned)
                }
            }
    }
}

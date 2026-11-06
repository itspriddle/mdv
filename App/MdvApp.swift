import MdvCore
import SwiftUI

@main
struct MdvApp: App {
    init() {
        // Load highlight.js into its JavaScriptCore context off the main thread, so the first
        // document doesn't pay for it.
        Task.detached(priority: .utility) {
            HighlightJSHighlighter.shared.prepare()
        }
    }

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
    }
}

struct DocumentView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    var body: some View {
        let page = document.renderedPage(fallbackTitle: fileURL?.lastPathComponent ?? "Untitled")
        MarkdownWebView(html: page.html, baseURL: fileURL?.deletingLastPathComponent())
            .frame(minWidth: 480, minHeight: 360)
            .navigationTitle(page.title)
    }
}

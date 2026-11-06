import SwiftUI

@main
struct MdvApp: App {
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

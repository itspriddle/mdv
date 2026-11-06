import MdvCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared as an imported type in Info.plist (via project.yml).
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// Read-only Markdown document. mdv is a viewer, so writing is unsupported.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = []

    let source: String

    init(source: String) {
        self.source = source
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
            let source = String(bytes: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.source = source
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }

    /// Renders the source into a full HTML page. The title is the document's own (frontmatter
    /// `title`, then the first `h1`) or `fallbackTitle` (the file name).
    func renderedPage(fallbackTitle: String, renderer: some MarkdownRenderer = HTMLRenderer()) -> RenderedPage {
        let rendered = renderer.render(source)
        let title = rendered.title ?? fallbackTitle
        return RenderedPage(title: title, html: HTMLDocument(title: title, body: rendered.html).html)
    }
}

struct RenderedPage: Equatable {
    /// Shown as the window title and the page `<title>`.
    let title: String
    let html: String
}

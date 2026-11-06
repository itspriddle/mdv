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

    func renderedHTML(title: String, renderer: some MarkdownRenderer = SwiftMarkdownRenderer()) -> String {
        HTMLDocument(title: title, body: renderer.renderBody(source)).html
    }
}

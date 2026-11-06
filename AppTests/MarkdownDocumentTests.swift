import AppKit
import Foundation
import Testing

@testable import MdvApp

@MainActor
@Suite("MarkdownDocument", .serialized)
struct MarkdownDocumentTests {
    static let markdownType = "net.daringfireball.markdown"

    /// A Markdown file in a fresh temporary folder.
    static func temporaryFile(_ contents: String, name: String = "notes.md") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("Info.plist maps Markdown and plain text to MarkdownDocument")
    func documentClass() {
        let controller = NSDocumentController.shared
        #expect(controller.documentClass(forType: Self.markdownType) == MarkdownDocument.self)
        #expect(controller.documentClass(forType: "public.plain-text") == MarkdownDocument.self)
    }

    @Test("reads and renders the file")
    func read() throws {
        let url = try Self.temporaryFile("# Title\n\nBody")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        #expect(document.content?.source == "# Title\n\nBody")
        #expect(document.content?.page.title == "Title")
    }

    @Test("falls back to the file name for the title")
    func fileNameTitle() throws {
        let url = try Self.temporaryFile("no heading", name: "README.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        #expect(document.content?.page.title == "README.md")
    }

    @Test("rejects files that aren't UTF-8")
    func notUTF8() throws {
        let url = try Self.temporaryFile("")
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)
        #expect(throws: CocoaError.self) {
            try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        }
    }

    @Test("never writes")
    func viewerOnly() throws {
        let url = try Self.temporaryFile("text")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        #expect(throws: CocoaError.self) {
            try document.data(ofType: Self.markdownType)
        }
        #expect(!MarkdownDocument.autosavesInPlace)
    }

    /// The web view's `document.title`, once the window's coordinator has loaded `expected`.
    func pageTitle(in controller: DocumentWindowController, becoming expected: String) async throws -> String? {
        var title: String?
        for _ in 0..<100 where title != expected {
            try await Task.sleep(for: .milliseconds(20))
            if controller.coordinator.hasLoadedPage {
                title =
                    try await controller.coordinator.webView.callAsyncJavaScript(
                        "return document.title;", arguments: [:], in: nil, contentWorld: AppScripts.world) as? String
            }
        }
        return title
    }

    @Test("a window shows the document and follows reverts", .timeLimit(.minutes(1)))
    func windowFollowsRevert() async throws {
        let url = try Self.temporaryFile("# First")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        #expect(controller.window?.title == "First")
        #expect(controller.window?.contentViewController != nil)
        #expect(try await pageTitle(in: controller, becoming: "First") == "First")
        #expect(controller.coordinator.webView.url == url.deletingLastPathComponent())

        // A revert is how a reload reaches the window (#21 triggers it on file changes).
        try Data("# Second".utf8).write(to: url)
        try document.revert(toContentsOf: url, ofType: Self.markdownType)
        #expect(document.content?.page.title == "Second")
        #expect(controller.window?.title == "Second")
        #expect(try await pageTitle(in: controller, becoming: "Second") == "Second")
    }
}

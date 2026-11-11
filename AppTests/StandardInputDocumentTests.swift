import AppKit
import Foundation
import MdvCore
import Testing

@testable import MdvApp

/// `cmd | mdv` (#68): the document controller reads a verified standard input handoff, deletes
/// it, and opens an untitled document, on `DocumentOpener`'s path and AppKit's; anything else
/// opens as a file.
@MainActor
@Suite("Standard input windows", .serialized, .timeLimit(.minutes(1)))
final class StandardInputDocumentTests {
    let folder: URL
    let throwawayDefaults: ThrowawayDefaults
    var errors: [any Error] = []
    var posted: [UUID] = []
    /// The last opener, kept so its `WindowWaits` keeps observing windows.
    var opener: DocumentOpener?

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-stdin-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        throwawayDefaults = try ThrowawayDefaults("mdv-stdin-tests")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func handoff(_ markdown: String) throws -> URL {
        try StandardInputHandoff.write(Data(markdown.utf8), inFolder: folder)
    }

    func folderContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    var standardInputDocuments: [MarkdownDocument] {
        NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }.filter { $0.fileURL == nil }
    }

    func open(_ urls: [URL], parameters: AppOpenParameters = AppOpenParameters()) async {
        let opener = DocumentOpener(
            themeSettings: ThemeSettings(defaults: throwawayDefaults.defaults, isPersistent: true),
            waits: WindowWaits(post: { [weak self] in self?.posted.append($0) }),
            presentError: { [weak self] in self?.errors.append($0) })
        self.opener = opener
        await withCheckedContinuation { continuation in
            opener.open(urls, parameters: parameters) { continuation.resume() }
        }
    }

    /// The one standard input document, rendered.
    func renderedStandardInput() async throws -> MarkdownDocument {
        let documents = standardInputDocuments
        try #require(documents.count == 1)
        let document = documents[0]
        await document.pendingRender?.value
        try #require(document.content != nil)
        return document
    }

    func closeAll() {
        for document in NSDocumentController.shared.documents {
            document.close()
        }
    }

    func until(_ what: String, _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a handoff opens an untitled window titled from its heading, with the theme, and is deleted")
    func handoffOpens() async throws {
        defer { closeAll() }
        let file = try handoff("# Piped Heading\n\nFrom a pipe.\n")
        await open([file], parameters: AppOpenParameters(themeID: "serif"))

        let document = try await renderedStandardInput()
        #expect(try folderContents().isEmpty, "the handoff and its folder are gone")
        #expect(document.content?.source == "# Piped Heading\n\nFrom a pipe.\n")
        #expect(document.content?.page.title == "Piped Heading")
        #expect(!NSDocumentController.shared.recentDocumentURLs.contains(file))
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        #expect(controller.pickedThemeID == "serif")
        #expect(controller.window?.isVisible == true)
        #expect(controller.window?.isRestorable == false, "nothing for restoration to bring back")
        try await until("the window title") { controller.window?.title == "Piped Heading" }
        #expect(errors.isEmpty)
    }

    @Test("without a heading, the window is Standard Input")
    func fallbackTitle() async throws {
        defer { closeAll() }
        let file = try handoff("Just a paragraph.\n")
        await open([file])
        let document = try await renderedStandardInput()
        #expect(document.displayName.hasPrefix("Standard Input"))
        #expect(document.content?.page.title == "Standard Input")
    }

    @Test("files and standard input open together, in the event's order")
    func withFiles() async throws {
        defer { closeAll() }
        let notes = folder.appending(path: "notes.md")
        try Data("# Notes\n".utf8).write(to: notes)
        let file = try handoff("# Piped\n")
        await open([notes, file])
        #expect(NSDocumentController.shared.document(for: notes) != nil)
        #expect(try await renderedStandardInput().content?.page.title == "Piped")
        #expect(try folderContents() == ["notes.md"])
    }

    @Test("a stdin.md that isn't a handoff (others can read it) opens as a file and is kept")
    func notAHandoff() async throws {
        defer { closeAll() }
        let file = try handoff("# Shared\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        await open([file])
        #expect(NSDocumentController.shared.document(for: file) != nil)
        #expect(standardInputDocuments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test("AppKit's own open (display: true, no mdv parameters) takes a handoff too")
    func appKitPath() async throws {
        defer { closeAll() }
        let file = try handoff("# Scripted\n")
        let (document, alreadyOpen) = try await NSDocumentController.shared.openDocument(
            withContentsOf: file, display: true)
        #expect(!alreadyOpen)
        #expect((document as? MarkdownDocument)?.fileURL == nil)
        #expect(document.windowControllers.first?.window?.isVisible == true)
        #expect(try folderContents().isEmpty)
    }

    @Test("--wait: the standard input window joins the token, which posts when it closes")
    func waitToken() async throws {
        defer { closeAll() }
        let token = UUID()
        let file = try handoff("# Waited\n")
        await open([file], parameters: AppOpenParameters(waitToken: token))
        let document = try await renderedStandardInput()
        #expect(posted.isEmpty, "still open")
        document.windowControllers.first?.window?.close()
        try await until("the token's notification") { posted == [token] }
    }

    @Test("a handoff that is too large or not UTF-8 is deleted and presented; no window")
    func badHandoffs() async throws {
        defer { closeAll() }
        let large = try StandardInputHandoff.write(
            Data(repeating: 0x61, count: StandardInputHandoff.maximumBytes + 1), inFolder: folder)
        await open([large])
        let binary = try StandardInputHandoff.write(Data([0xFF]), inFolder: folder)
        await open([binary])
        #expect(errors.compactMap { $0 as? StandardInputHandoff.Failure } == [.tooLarge, .notUTF8])
        #expect(standardInputDocuments.isEmpty)
        #expect(try folderContents().isEmpty)
    }

    @Test("Settings > Markdown changes render standard input again")
    func settingsApply() async throws {
        defer { closeAll() }
        let file = try handoff("| a |\n| - |\n| 1 |\n")
        await open([file])
        let document = try await renderedStandardInput()
        let store = MarkdownSettings(defaults: throwawayDefaults.defaults, isPersistent: true)
        document.markdownSettings = store
        try await until("the GFM render") { document.content?.page.body.contains("<table") == true }
        store.defaultFlavorID = "commonmark"
        try await until("the CommonMark render") { document.content?.preferences.flavor == .commonmark }
        #expect(document.content?.page.body.contains("<table") == false)
    }
}

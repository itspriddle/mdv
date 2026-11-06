import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
import WebKit

@testable import MdvApp

/// Opening documents (#22): the document controller's policies, the declared document types,
/// dropped files, tabs, and window restoration of the reading position.
@MainActor
@Suite("Opening documents", .serialized, .timeLimit(.minutes(1)))
struct OpeningTests {
    static let markdownType = "net.daringfireball.markdown"
    /// 200 one-line paragraphs: paragraph N is on line 2N - 1.
    static let longSource = (1...200).map { "Paragraph \($0)." }.joined(separator: "\n\n")

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-opening-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ contents: String = "# Title") throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func until(
        _ what: String, timeout: Duration = .seconds(5), _ condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Opens `url` through the shared document controller, without showing it.
    func openThroughController(_ url: URL) async throws -> (MarkdownDocument, alreadyOpen: Bool) {
        let (document, alreadyOpen) = try await NSDocumentController.shared.openDocument(
            withContentsOf: url, display: false)
        return (try #require(document as? MarkdownDocument), alreadyOpen)
    }

    // MARK: Document controller

    @Test("the shared document controller is mdv's, and tests don't touch Open Recent")
    func sharedController() throws {
        #expect(NSDocumentController.shared is DocumentController)
        #expect(!DocumentController.recordsRecentDocuments)
        let url = try file("recent.md")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        #expect(!NSDocumentController.shared.recentDocumentURLs.contains(url))
    }

    @Test("the same file under another name is the same file")
    func sameFile() throws {
        let url = try file("same.md")
        let link = folder.appending(path: "link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let other = try file("other.md")
        let dotted = URL(filePath: folder.path(percentEncoded: false) + "/./same.md")

        #expect(DocumentController.isSameFile(url, link))
        #expect(DocumentController.isSameFile(url, dotted))
        #expect(!DocumentController.isSameFile(url, other))
        #expect(!DocumentController.isSameFile(url, folder.appending(path: "missing.md")))
        #expect(!DocumentController.isSameFile(url, try #require(URL(string: "https://example.com/same.md"))))
    }

    @Test("opening a file that is already open, by another path, finds the open document")
    func alreadyOpenThroughSymlink() async throws {
        let url = try file("open.md")
        let link = folder.appending(path: "open-link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)

        let (document, firstAlreadyOpen) = try await openThroughController(url)
        defer { document.close() }
        #expect(!firstAlreadyOpen)
        #expect(NSDocumentController.shared.document(for: link) === document)
        let (again, alreadyOpen) = try await openThroughController(link)
        #expect(again === document)
        #expect(alreadyOpen)
    }

    @Test("a file that isn't UTF-8 fails to open with an error and leaves no document")
    func invalidFileFailsToOpen() async throws {
        let url = folder.appending(path: "invalid.md")
        try Data([0x23, 0x20, 0xFF, 0xFE, 0x0A]).write(to: url)
        await #expect(throws: (any Error).self) {
            _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: false)
        }
        #expect(NSDocumentController.shared.document(for: url) == nil)
    }

    @Test("restoration skips files that are gone, quietly")
    func restorationSkipsMissingFiles() async throws {
        let existing = try file("here.md")
        let missing = folder.appending(path: "gone.md")
        #expect(DocumentController.canRestore(existing))
        #expect(!DocumentController.canRestore(missing))
        #expect(!DocumentController.canRestore(folder.appending(path: "here.md/child")))

        let result: (NSDocument?, (any Error)?) = await withCheckedContinuation { continuation in
            let controller = NSDocumentController.shared
            controller.reopenDocument(for: nil, withContentsOf: missing, display: false) { document, _, error in
                continuation.resume(returning: (document, error))
            }
        }
        #expect(result.0 == nil)
        // A cancelled error is never presented to the user.
        #expect((result.1 as? CocoaError)?.code == .userCancelled)
    }

    // MARK: Document types

    /// `.md` and `.markdown` are the system's `net.daringfireball.markdown`. The other
    /// extensions may belong to another app's type on a given Mac (iA Writer declares
    /// `net.ia.markdown`), but every such type conforms to plain text, which mdv also opens.
    @Test("Markdown files open as MarkdownDocument", arguments: ["md", "markdown", "mdown", "mkd", "mkdn", "txt"])
    func markdownExtensions(fileExtension: String) throws {
        let url = try file("doc.\(fileExtension)")
        let typeName = try NSDocumentController.shared.typeForContents(of: url)
        if ["md", "markdown"].contains(fileExtension) {
            #expect(typeName == Self.markdownType)
        }
        let type = try #require(UTType(typeName))
        #expect(type.conforms(to: .plainText))
        #expect(NSDocumentController.shared.documentClass(forType: typeName) == MarkdownDocument.self)
        #expect(MarkdownDocument.canConcurrentlyReadDocuments(ofType: typeName) == false)
    }

    @Test("the declared Markdown type has the text/markdown MIME type")
    func markdownMIMEType() throws {
        let type = try #require(UTType(Self.markdownType))
        #expect(type.preferredMIMEType == "text/markdown")
        #expect(UTType(mimeType: "text/markdown")?.conforms(to: type) == true)
    }

    @Test("dropped Markdown and plain text files open; images and folders don't")
    func droppedFiles() throws {
        let markdown = try file("a.md")
        let text = try file("b.txt", "plain")
        let image = try file("c.png", "not really a png")
        let subfolder = folder.appending(path: "sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mdv-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([markdown, image, subfolder, text].map { $0 as NSURL })
        let names = DocumentDrop.openableFiles(on: pasteboard).map(\.lastPathComponent)
        #expect(names == ["a.md", "b.txt"])
    }

    // MARK: Windows and tabs

    @Test("document windows are restorable and share one tab group")
    func windowConfiguration() throws {
        let document = try MarkdownDocument(contentsOf: try file("window.md"), ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)
        #expect(window.identifier == DocumentWindowController.windowIdentifier)
        #expect(window.isRestorable)
        #expect(window.tabbingMode == .automatic)
        #expect(window.tabbingIdentifier == DocumentWindowController.tabbingIdentifier)
    }

    @Test("files dropped on a window open as its tabs, in order; an open file is focused")
    func dropOpensTabs() async throws {
        let first = try MarkdownDocument(contentsOf: try file("first.md", "# First"), ofType: Self.markdownType)
        NSDocumentController.shared.addDocument(first)
        first.makeWindowControllers()
        first.showWindows()
        let controller = try #require(first.windowControllers.first as? DocumentWindowController)
        let window = try #require(controller.window)
        let second = try file("second.md", "# Second")
        let third = try file("third.md", "# Third")
        var opened: [NSDocument] = []
        defer {
            for document in opened + [first] {
                document.close()
            }
        }

        controller.openDroppedFiles([second, third, try #require(first.fileURL)])
        try await until("both tabs") { (window.tabbedWindows?.count ?? 0) == 3 }
        opened = NSDocumentController.shared.documents.filter { $0 !== first }
        let titles = (window.tabbedWindows ?? []).map(\.title)
        #expect(titles == ["First", "Second", "Third"])
        #expect(opened.count == 2)
    }

    // MARK: Restoration

    @Test("the reading position is saved with the window and restored after the page loads")
    func restoresReadingPosition() async throws {
        let url = try file("long.md", Self.longSource)
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        try await until("the first load") { controller.coordinator.hasLoadedPage }

        // Paragraph 60 is on line 119; ScrollPosition.js reports it after the scroll.
        try await controller.coordinator.scroll(toSourceLine: 119)
        try await until("the scroll report") { abs((controller.lastSourceLine ?? 0) - 119) < 0.5 }

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        controller.encodeReadingPosition(with: archiver)
        archiver.finishEncoding()

        let restored = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        restored.makeWindowControllers()
        defer { restored.close() }
        let restoredController = try #require(restored.windowControllers.first as? DocumentWindowController)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        restoredController.restoreReadingPosition(with: unarchiver)
        try await until("the restored position") {
            guard restoredController.coordinator.hasLoadedPage else {
                return false
            }
            return abs(try await restoredController.coordinator.currentSourceLine() - 119) < 0.5
        }
    }

    @Test("the window's own restorable state includes the reading position")
    func windowEncodesControllerState() async throws {
        let document = try MarkdownDocument(contentsOf: try file("state.md"), ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        let window = try #require(controller.window)
        controller.sourceLineDidChange(42)

        let coder = KeyRecordingCoder()
        window.encodeRestorableState(with: coder)
        #expect(coder.keys.contains(DocumentWindowController.sourceLineStateKey))
    }

    @Test("bad positions from restorable state or scripts are ignored")
    func validSourceLine() {
        #expect(DocumentWindowController.validSourceLine(1) == 1)
        #expect(DocumentWindowController.validSourceLine(12.5) == 12.5)
        #expect(DocumentWindowController.validSourceLine(0) == nil)
        #expect(DocumentWindowController.validSourceLine(-3) == nil)
        #expect(DocumentWindowController.validSourceLine(.nan) == nil)
        #expect(DocumentWindowController.validSourceLine(.infinity) == nil)
    }
}

/// Records the keys a restorable-state encoder writes, without archiving objects.
final class KeyRecordingCoder: NSCoder {
    private(set) var keys: [String] = []

    override var allowsKeyedCoding: Bool { true }
    override var requiresSecureCoding: Bool { true }

    override func encode(_ object: Any?, forKey key: String) { keys.append(key) }
    override func encodeConditionalObject(_ object: Any?, forKey key: String) { keys.append(key) }
    override func encode(_ value: Bool, forKey key: String) { keys.append(key) }
    override func encode(_ value: Int, forKey key: String) { keys.append(key) }
    override func encode(_ value: Int32, forKey key: String) { keys.append(key) }
    override func encode(_ value: Int64, forKey key: String) { keys.append(key) }
    override func encode(_ value: Float, forKey key: String) { keys.append(key) }
    override func encode(_ value: Double, forKey key: String) { keys.append(key) }
    override func encodeBytes(_ bytes: UnsafePointer<UInt8>?, length: Int, forKey key: String) { keys.append(key) }
}

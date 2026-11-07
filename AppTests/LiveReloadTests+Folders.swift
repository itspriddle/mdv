import Foundation
import Testing

@testable import MdvApp

/// Live reload when the document's folder goes away and comes back (#41).
extension LiveReloadTests {
    @Test("the document's folder deleted and recreated (#41): deleted state, then the new file reloads")
    func folderDeleteAndRecreate() async throws {
        let docs = folder.appending(path: "docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let nested = docs.appending(path: "notes.md")
        try Data("# Kept".utf8).write(to: nested)
        let document = try MarkdownDocument(contentsOf: nested, ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        try await until("the first load") { controller.coordinator.hasLoadedPage }

        try shell("rm -rf docs")
        try await until("deleted status") { document.fileStatus == .deleted }
        #expect(try await pageTitle(controller) == "Kept")

        try shell("mkdir docs && printf '# Recreated\\n' > docs/notes.md")
        try await waitForPageTitle("Recreated", in: controller)
        #expect(document.fileStatus == .current)
        #expect(document.fileURL?.lastPathComponent == "notes.md")

        try shell("printf '# Still watched\\n' > docs/notes.md")
        try await waitForPageTitle("Still watched", in: controller)
    }

    @Test("the document's folder swapped quickly (git checkout) reloads the new file")
    func folderSwapped() async throws {
        let docs = folder.appending(path: "docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let nested = docs.appending(path: "notes.md")
        try Data("# Before".utf8).write(to: nested)
        let document = try MarkdownDocument(contentsOf: nested, ofType: Self.markdownType)
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        try await until("the first load") { controller.coordinator.hasLoadedPage }

        try shell("rm -rf docs && mkdir docs && printf '# After\\n' > docs/notes.md")
        try await waitForPageTitle("After", in: controller)
        #expect(document.fileStatus == .current)
    }
}

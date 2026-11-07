import AppKit
import Foundation
import MdvCore
import Testing

@testable import MdvApp

/// Shared setup for the #26 suites (`ZoomTests`, `PrintCopyTests`): document windows over files
/// in a temporary folder, a throwaway defaults suite for `ZoomSettings`, and a private
/// pasteboard, so tests never touch the general one or the reader's defaults.
@MainActor
class DocumentWindowTestCase {
    static let markdownType = "net.daringfireball.markdown"
    static let source = """
        # Title

        Some *text* with a [link](https://example.com/page) and ![remote](https://example.com/a.png).

        ```swift
        let x = 1
        ```
        """

    let folder: URL
    let defaultsSuite = "mdv-zoom-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    /// A private pasteboard, so tests never touch the general one.
    let pasteboardName = NSPasteboard.Name("mdv-tests-\(UUID().uuidString)")
    var pasteboard: NSPasteboard { NSPasteboard(name: pasteboardName) }
    var documents: [MarkdownDocument] = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-zoom-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: defaultsSuite))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        NSPasteboard(name: pasteboardName).releaseGlobally()
    }

    func settings() -> ZoomSettings {
        ZoomSettings(defaults: defaults, isPersistent: true)
    }

    /// Theme settings over the throwaway defaults suite, so tests never read the reader's theme.
    func themeSettings(registry: ThemeRegistry = .bundled) -> ThemeSettings {
        ThemeSettings(registry: registry, defaults: defaults, isPersistent: true)
    }

    /// Opens `source` in a document window that follows `zoomSettings`, `contentWidthSettings`,
    /// and `themeSettings` (all in this suite's defaults unless given), once the page has loaded.
    func open(
        _ source: String = source, name: String = "notes.md", zoomSettings: ZoomSettings? = nil,
        contentWidthSettings: ContentWidthSettings? = nil, themeSettings: ThemeSettings? = nil
    ) async throws -> (MarkdownDocument, DocumentWindowController) {
        let file = folder.appending(path: name)
        try Data(source.utf8).write(to: file)
        let document = try MarkdownDocument(contentsOf: file, ofType: Self.markdownType)
        let controller = DocumentWindowController(
            zoomSettings: zoomSettings ?? settings(),
            contentWidthSettings: contentWidthSettings ?? ContentWidthSettings(defaults: defaults, isPersistent: true),
            themeSettings: themeSettings ?? self.themeSettings())
        document.addWindowController(controller)
        documents.append(document)
        try await until("the first load") { controller.coordinator.hasLoadedPage }
        return (document, controller)
    }

    func until(_ what: String, timeout: Duration = .seconds(10), _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func closeAll() {
        for document in documents {
            document.close()
        }
        documents.removeAll()
    }

    func item(_ title: String, in menuTitle: String) -> NSMenuItem? {
        MainMenu.build().item(withTitle: menuTitle)?.submenu?.items.first { $0.title == title && !$0.isHidden }
    }
}

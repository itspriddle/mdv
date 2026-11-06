import AppKit

/// One open Markdown file. mdv is a viewer: the document reads and re-reads its file but never
/// writes it.
///
/// `NSDocument` gives us file coordination and `NSFilePresenter` change notifications (live
/// reload), revert, recents, window tabs, and state restoration. The document owns the source
/// text and the rendered page (`content`); each window's `DocumentWindowController` displays it.
/// Registered as `NSDocumentClass` for the document types declared in project.yml.
@Observable
final class MarkdownDocument: NSDocument {
    /// The source and rendered page from the last successful read; `nil` before the first one.
    private(set) var content: DocumentContent?

    override static var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    // MARK: Reading

    /// Reads and renders the file. NSDocument calls this for the initial open and for every
    /// revert (`revert(toContentsOf:ofType:)`), so a reload is a revert.
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        let content = try DocumentContent(data: Data(contentsOf: url), fallbackTitle: url.lastPathComponent)
        // NSDocument reads on the main thread unless `canConcurrentlyReadDocuments(ofType:)`
        // returns true, which this class does not.
        MainActor.assumeIsolated {
            setContent(content)
        }
    }

    /// Replaces the content and tells each window to show it. The single path every (re)load
    /// goes through.
    func setContent(_ content: DocumentContent) {
        self.content = content
        for case let controller as DocumentWindowController in windowControllers {
            controller.documentContentDidChange()
        }
    }

    // MARK: Viewer only

    override nonisolated func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }
}

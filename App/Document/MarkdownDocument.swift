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

    /// Whether the window shows the file's current contents; set by live reload.
    var fileStatus: FileStatus = .current

    /// Watches the file while the document has windows (live reload).
    @ObservationIgnored private var liveReloader: LiveReloader?

    override static var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
        startLiveReload()
    }

    override func close() {
        liveReloader?.stop()
        liveReloader = nil
        super.close()
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
        fileStatus = .current
        for case let controller as DocumentWindowController in windowControllers {
            controller.documentContentDidChange()
        }
    }

    // MARK: Live reload

    /// Starts reloading the document when its file changes. `makeWindowControllers()` calls
    /// this; `close()` stops it.
    func startLiveReload(timing: FileWatcher.Timing = FileWatcher.Timing()) {
        guard liveReloader == nil else {
            return
        }
        let reloader = LiveReloader(document: self, timing: timing)
        reloader.start()
        liveReloader = reloader
    }

    /// The reload in flight, if any (for tests).
    var pendingReload: Task<Void, Never>? { liveReloader?.pendingReload }

    // `LiveReloader`'s `FileWatcher` owns change detection and file location. NSFilePresenter
    // callbacks arrive about a second late for edits by other processes and stop after a
    // delete (measured in #21), so they only ask the watcher to check. They don't call super:
    // NSDocument would follow a move to wherever the file went, including Vim's backup name
    // or the Trash, and the watcher decides that instead.

    override nonisolated func presentedItemDidChange() {
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    override nonisolated func presentedItemDidMove(to newURL: URL) {
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    override nonisolated func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        // Keep the window and its last render; the watcher reports the deletion.
        completionHandler(nil)
        Task { @MainActor in
            self.liveReloader?.checkForChanges()
        }
    }

    // MARK: Viewer only

    override nonisolated func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }
}

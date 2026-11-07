import AppKit
import os

/// One open Markdown file. mdv is a viewer: the document reads and re-reads its file but never
/// writes it.
///
/// `NSDocument` gives us opening, revert, recents, window tabs, and state restoration. Live
/// reload is `LiveReloader` (a kqueue watcher), not NSDocument's file presenter, which is late
/// and misses deletes (#21). The document owns the source text and the rendered page
/// (`content`); each window's `DocumentWindowController` displays it.
///
/// Opening reads and decodes the file on the main thread (so a missing or non-UTF-8 file fails
/// the open with NSDocument's own error) and renders it off the main actor (#32): the window
/// appears right away, painted with the theme background, and the page loads when the render
/// finishes.
/// Registered as `NSDocumentClass` for the document types declared in project.yml.
@Observable
final class MarkdownDocument: NSDocument {
    /// The source and rendered page from the last successful read; `nil` until the first
    /// render finishes.
    private(set) var content: DocumentContent?

    /// The render of the last read while it runs off the main actor, for tests to await.
    @ObservationIgnored private(set) var pendingRender: Task<Void, Never>?
    /// Bumped by every read, every `setContent(_:)`, and `close()`: a render that finishes
    /// under an older value was overtaken (by a newer read, a live reload, or the window
    /// closing) and is dropped.
    @ObservationIgnored private var contentGeneration = 0

    /// Whether the window shows the file's current contents; set by live reload.
    var fileStatus: FileStatus = .current

    /// Watches the file while the document has windows (live reload).
    @ObservationIgnored private var liveReloader: LiveReloader?

    override static var autosavesInPlace: Bool { false }

    /// Signposts for opening (`Read` on main, `Render` off main), in Instruments' Points of
    /// Interest. Release builds keep them; they cost nothing unless recorded.
    nonisolated static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "mdv", category: .pointsOfInterest)

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
        startLiveReload()
    }

    override func close() {
        liveReloader?.stop()
        liveReloader = nil
        dropPendingRender()
        super.close()
    }

    // MARK: Reading

    /// Reads the file and starts rendering it off the main actor; `setContent(_:)` shows the
    /// result. NSDocument calls this for the initial open and for every revert
    /// (`revert(toContentsOf:ofType:)`).
    ///
    /// Reading and UTF-8 decoding stay here, on the main thread, so an unreadable or non-UTF-8
    /// file still fails the open (or revert) with the error NSDocument presents. They take a few
    /// milliseconds for 5 MB; rendering is what took hundreds (#27).
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        let interval = Self.signposter.beginInterval("Read", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Read", interval) }
        let source = try DocumentContent.source(from: Data(contentsOf: url))
        // NSDocument reads on the main thread unless `canConcurrentlyReadDocuments(ofType:)`
        // returns true, which this class does not (`NSDocument.init` is main-actor and traps
        // off main under Swift 6).
        MainActor.assumeIsolated {
            render(source, of: url)
        }
    }

    /// Renders `source` (the contents of `url`) off the main actor, then shows it with
    /// `setContent(_:)` unless something newer replaced the content or the document closed
    /// first. Starting a render drops the one in flight.
    func render(_ source: String, of url: URL) {
        dropPendingRender()
        let generation = contentGeneration
        pendingRender = Task { [weak self] in
            let content = await Task.detached(priority: .userInitiated) {
                Self.renderContent(source, of: url)
            }.value
            guard let self, generation == self.contentGeneration else {
                return
            }
            self.setContent(content)
        }
    }

    /// Renders a document's content. Runs off the main actor.
    nonisolated static func renderContent(_ source: String, of url: URL) -> DocumentContent {
        let interval = signposter.beginInterval("Render", id: signposter.makeSignpostID(), "\(source.utf8.count) bytes")
        defer { signposter.endInterval("Render", interval) }
        return DocumentContent(
            source: source, fallbackTitle: url.lastPathComponent,
            linkRoot: DocumentContent.linkRoot(forDocumentAt: url))
    }

    /// Marks the render in flight, if any, as stale. Its work finishes in the background (the
    /// renderer can't be interrupted) and the result is dropped.
    private func dropPendingRender() {
        contentGeneration += 1
        pendingRender?.cancel()
        pendingRender = nil
    }

    /// Replaces the content and tells each window to show it. The single path every (re)load
    /// goes through. A render still in flight from an earlier read is older than `content`
    /// and is dropped.
    func setContent(_ content: DocumentContent) {
        contentGeneration += 1
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

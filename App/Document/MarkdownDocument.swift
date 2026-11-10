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
///
/// Settings > Markdown (#55) applies to open documents: the document follows
/// `MarkdownSettings.didChangeNotification` and renders its source again with the new
/// preferences, and each window swaps the result in place like a live reload (keeping the
/// reading position).
///
/// The custom preprocessor (#57), when the reader turned it on, is part of every render: the
/// first render waits for it, each live reload runs it again, and a newer render, a newer
/// `setContent(_:)`, or closing the document cancels the run in flight, which stops the
/// script's process group. Changing it in Settings renders open documents again.
/// Registered as `NSDocumentClass` for the document types declared in project.yml.
@Observable
final class MarkdownDocument: NSDocument {
    /// The source and rendered page from the last successful read; `nil` until the first
    /// render finishes.
    private(set) var content: DocumentContent?

    /// The render in flight (of a read, or after a Settings change) while it runs off the main
    /// actor, for tests to await. Cancelling it stops a custom preprocessor it is running.
    @ObservationIgnored private(set) var pendingRender: Task<Void, Never>?
    /// What `pendingRender` renders, so a Settings change can restart it.
    @ObservationIgnored private var pendingRenderInput: RenderInput?
    /// Bumped by every read, every `setContent(_:)`, and `close()`: a render that finishes
    /// under an older value was overtaken (by a newer read, a live reload, or the window
    /// closing) and is dropped.
    @ObservationIgnored private var contentGeneration = 0

    /// Whether the window shows the file's current contents; set by live reload.
    var fileStatus: FileStatus = .current

    /// Whether a render (`pendingRender`) or a live reload is in flight: the windows show a
    /// progress indicator if it runs long (#58). Each window hears of a change through
    /// `DocumentWindowController.renderActivityDidChange()`.
    private(set) var isRendering = false

    /// Watches the file while the document has windows (live reload).
    @ObservationIgnored private var liveReloader: LiveReloader?

    /// The Markdown settings (#55) this document renders with. Changing them (or the store)
    /// renders the document again. Tests set their own store right after opening.
    @ObservationIgnored var markdownSettings: MarkdownSettings = .shared {
        didSet {
            renderIfSettingsChanged()
        }
    }

    /// The custom preprocessor settings (#57) this document renders with. Changing them (or
    /// the store) renders the document again. Tests set their own store right after opening.
    @ObservationIgnored var customPreprocessorSettings: CustomPreprocessorSettings = .shared {
        didSet {
            renderIfSettingsChanged()
        }
    }

    override init() {
        super.init()
        let center = NotificationCenter.default
        let selector = #selector(markdownSettingsDidChange(_:))
        center.addObserver(self, selector: selector, name: MarkdownSettings.didChangeNotification, object: nil)
        center.addObserver(
            self, selector: selector, name: CustomPreprocessorSettings.didChangeNotification, object: nil)
    }

    override static var autosavesInPlace: Bool { false }

    /// Signposts for opening (`Read` on main, `Render` off main), in Instruments' Points of
    /// Interest. Release builds keep them; they cost nothing unless recorded.
    nonisolated static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "mdv", category: .pointsOfInterest)

    override func makeWindowControllers() {
        LaunchTiming.mark("makeWindowControllers")
        // The first window of the launch gets the web view started at launch (#40).
        addWindowController(DocumentWindowController(coordinator: WebViewPrewarmer.shared.takeCoordinator()))
        startLiveReload()
    }

    override func showWindows() {
        super.showWindows()
        LaunchTiming.mark("windowShown")
    }

    override func close() {
        liveReloader?.stop()
        liveReloader = nil
        // A closed document no longer follows Settings > Markdown.
        NotificationCenter.default.removeObserver(self, name: MarkdownSettings.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: CustomPreprocessorSettings.didChangeNotification, object: nil)
        dropPendingRender()
        updateRenderActivity()
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
        LaunchTiming.mark("read")
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
    ///
    /// The first render of an open waits here (for the renderer, and for the custom
    /// preprocessor when one is on, up to its timeout); the window shows its blank,
    /// theme-colored page meanwhile (`DocumentWindowController`, `prepareForFirstLoad()`).
    func render(_ source: String, of url: URL) {
        dropPendingRender()
        let generation = contentGeneration
        let preferences = renderPreferences
        pendingRenderInput = RenderInput(source: source, url: url, preferences: preferences)
        pendingRender = Task { [weak self] in
            guard let content = try? await Self.renderContent(source, of: url, preferences: preferences),
                let self, generation == self.contentGeneration
            else {
                return
            }
            self.setContent(content)
        }
        updateRenderActivity()
    }

    /// What a render of this document uses now: Settings > Markdown's preferences (#55) and the
    /// custom preprocessor, if on (#57). Read on the main actor and passed to the render.
    var renderPreferences: MarkdownPreferences {
        var preferences = markdownSettings.preferences
        preferences.customPreprocessor = customPreprocessorSettings.preference
        return preferences
    }

    /// Renders a document's content with `preferences` (`renderPreferences`, read on the main
    /// actor by the caller) on a detached task, so it runs off the main actor. Cancelling the
    /// calling task cancels the render, which stops a custom preprocessor run (#57) and throws
    /// `CancellationError`; a render without one finishes and is dropped by the caller.
    nonisolated static func renderContent(
        _ source: String, of url: URL, preferences: MarkdownPreferences
    ) async throws -> DocumentContent {
        let work = Task.detached(priority: .userInitiated) {
            let interval = signposter.beginInterval(
                "Render", id: signposter.makeSignpostID(), "\(source.utf8.count) bytes")
            defer { signposter.endInterval("Render", interval) }
            if let delay = UITestHooks.renderDelay {
                try await Task.sleep(for: delay)
            }
            return try await DocumentContent.rendering(source, of: url, preferences: preferences)
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Marks the render in flight, if any, as stale and cancels it. A custom preprocessor it
    /// is running is stopped; otherwise its work finishes in the background (the renderer
    /// can't be interrupted) and the result is dropped. Callers call `updateRenderActivity()`
    /// once they're done, so a render replaced by another never reports a gap.
    private func dropPendingRender() {
        contentGeneration += 1
        pendingRender?.cancel()
        pendingRender = nil
        pendingRenderInput = nil
    }

    /// Replaces the content and tells each window to show it. The single path every (re)load
    /// goes through. A render still in flight from an earlier read is older than `content`
    /// and is dropped (and cancelled, stopping its custom preprocessor run).
    ///
    /// Content rendered before Settings > Markdown changed (a first render or live reload that
    /// was already running) is shown, then rendered again with the current preferences.
    func setContent(_ content: DocumentContent) {
        LaunchTiming.mark("rendered")
        dropPendingRender()
        self.content = content
        if content.preferences.customPreprocessor != nil {
            customPreprocessorSettings.recordRun(
                CustomPreprocessorRun(
                    documentName: fileURL?.lastPathComponent ?? displayName, date: .now,
                    error: content.preprocessorError))
        }
        fileStatus = .current
        for case let controller as DocumentWindowController in windowControllers {
            controller.documentContentDidChange()
        }
        renderIfSettingsChanged()
        updateRenderActivity()
    }

    /// Updates `isRendering` from the render and the live reload in flight, and tells the
    /// windows when it changed.
    func updateRenderActivity() {
        let rendering = pendingRender != nil || liveReloader?.isReloading == true
        guard rendering != isRendering else {
            return
        }
        isRendering = rendering
        for case let controller as DocumentWindowController in windowControllers {
            controller.renderActivityDidChange()
        }
    }

    // MARK: Markdown settings (#55)

    @objc private func markdownSettingsDidChange(_ notification: Notification) {
        let object = notification.object as AnyObject?
        guard object === markdownSettings || object === customPreprocessorSettings else {
            return
        }
        renderIfSettingsChanged()
    }

    /// Renders the current source again if it was rendered with other preferences than
    /// `renderPreferences` are now (Settings > Markdown, the custom preprocessor). The windows
    /// swap the result in place (`setContent(_:)`).
    ///
    /// A render or live reload in flight is newer than `content`: one with the current
    /// preferences is left to finish, and one with outdated preferences starts again, so turning
    /// a slow preprocessor off doesn't wait for it.
    private func renderIfSettingsChanged() {
        let preferences = renderPreferences
        liveReloader?.restartIfOutdated(preferences: preferences)
        if let pending = pendingRenderInput {
            if pending.preferences != preferences {
                render(pending.source, of: pending.url)
            }
            return
        }
        guard let content, let fileURL, content.preferences != preferences else {
            return
        }
        render(content.source, of: fileURL)
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

/// What a render renders: a document's text, its file, and the preferences it is rendered with.
private struct RenderInput {
    let source: String
    let url: URL
    let preferences: MarkdownPreferences
}

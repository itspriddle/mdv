import Foundation

/// Keeps a `MarkdownDocument` in step with its file: a `FileWatcher` reports changes, the file
/// is read and rendered off the main actor, and the newest result replaces the document's
/// content. Renders that a newer change overtakes are dropped. A file that can't be read or
/// isn't UTF-8 leaves the last good render in place and sets the document's `fileStatus`.
///
/// Reloads bypass `NSDocument.revert(toContentsOf:ofType:)` on purpose: a revert reads on the
/// main thread and reports a bad file with an error alert, while a reload reads off the main
/// actor, skips an unchanged file, and reports a bad one in the window (`fileStatus`). Both
/// render off the main actor (`MarkdownDocument.renderContent`, #32).
///
/// Each reload runs the custom preprocessor again when it's on (#57). A newer change, `stop()`
/// (the document closing), or a Settings change while the reload runs (`restartIfOutdated`)
/// cancels the reload in flight, which stops the script's process group.
@MainActor
final class LiveReloader {
    private weak var document: MarkdownDocument?
    private let timing: FileWatcher.Timing
    private var watcher: FileWatcher?
    /// Bumped by every event; a render finishing under an older generation is stale.
    private var generation = 0
    private var reloadTask: Task<Void, Never>?
    /// The preferences and `force` of the reload in flight; `nil` when none is.
    private var pendingReloadInput: (preferences: MarkdownPreferences, force: Bool)?

    init(document: MarkdownDocument, timing: FileWatcher.Timing = FileWatcher.Timing()) {
        self.document = document
        self.timing = timing
    }

    /// Starts watching the document's file. Does nothing for a document without a file.
    func start() {
        guard watcher == nil, let url = document?.fileURL else {
            return
        }
        let watcher = FileWatcher(url: url, timing: timing) { [weak self] event in
            // Main queue, not a Task: events must arrive in order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        cancelReload()
        document?.updateRenderActivity()
    }

    /// Whether a reload is in flight (the document's `isRendering`, #58).
    var isReloading: Bool { pendingReloadInput != nil }

    /// Drops the reload in flight (cancelling its custom preprocessor run). Callers tell the
    /// document (`updateRenderActivity()`) once they're done.
    private func cancelReload() {
        generation += 1
        reloadTask?.cancel()
        reloadTask = nil
        pendingReloadInput = nil
    }

    /// Starts the reload in flight again if it renders with other preferences than
    /// `preferences` (Settings changed while it ran, #57).
    func restartIfOutdated(preferences: MarkdownPreferences) {
        guard let pending = pendingReloadInput, pending.preferences != preferences else {
            return
        }
        reload(force: pending.force)
    }

    /// A hint that the file may have changed (an `NSFilePresenter` callback). The watcher checks
    /// the file and reports only real changes.
    func checkForChanges() {
        watcher?.checkForChanges()
    }

    /// The task of the reload in flight, for tests to await.
    var pendingReload: Task<Void, Never>? { reloadTask }

    private func handle(_ event: FileWatcher.Event) {
        guard let document, watcher != nil else {
            return
        }
        switch event {
        case .changed:
            reload(force: false)
        case .deleted:
            cancelReload()
            document.updateRenderActivity()
            document.fileStatus = .deleted
        case .moved(let url):
            document.fileURL = url
            // Re-render even if the text is the same: the fallback title (the file name) and
            // the base URL for relative links changed.
            reload(force: true)
        }
    }

    /// Reads and renders the file off the main actor, then shows it if no newer change came in.
    /// Unless `force` is set, an unchanged source is not rendered again.
    func reload(force: Bool) {
        guard let document, let url = document.fileURL else {
            return
        }
        cancelReload()
        let generation = generation
        let currentSource = force ? nil : document.content?.source
        let preferences = document.renderPreferences
        pendingReloadInput = (preferences, force)
        document.updateRenderActivity()
        reloadTask = Task { [weak self] in
            let result: Result<DocumentContent?, any Error>
            do {
                result = .success(
                    try await Self.render(contentsOf: url, unlessSourceIs: currentSource, preferences: preferences))
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error)
            }
            guard let self, generation == self.generation, let document = self.document else {
                return
            }
            pendingReloadInput = nil
            document.updateRenderActivity()
            switch result {
            case .success(let content?):
                document.setContent(content)
            case .success(nil):
                document.fileStatus = .current
            case .failure(let error):
                document.fileStatus = .unreadable(reason: error.localizedDescription)
            }
        }
    }

    /// Reads and renders `url` with `preferences` (Settings > Markdown, #55, and the custom
    /// preprocessor, #57) off the main actor; `nil` when its text equals `currentSource`.
    /// Cancelling the calling task stops a preprocessor run and throws `CancellationError`.
    nonisolated static func render(
        contentsOf url: URL, unlessSourceIs currentSource: String?, preferences: MarkdownPreferences = .default
    ) async throws -> DocumentContent? {
        let read = Task.detached(priority: .userInitiated) {
            try DocumentContent.source(from: Data(contentsOf: url))
        }
        let source = try await read.value
        if source == currentSource {
            return nil
        }
        return try await MarkdownDocument.renderContent(source, of: url, preferences: preferences)
    }
}

import Foundation

/// Keeps a `MarkdownDocument` in step with its file: a `FileWatcher` reports changes, the file
/// is read and rendered off the main actor, and the newest result replaces the document's
/// content. Renders that a newer change overtakes are dropped. A file that can't be read or
/// isn't UTF-8 leaves the last good render in place and sets the document's `fileStatus`.
///
/// Reloads bypass `NSDocument.revert(toContentsOf:ofType:)` on purpose: NSDocument reads on the
/// main thread, and rendering a 1 MB document there would stall the UI.
@MainActor
final class LiveReloader {
    private weak var document: MarkdownDocument?
    private let timing: FileWatcher.Timing
    private var watcher: FileWatcher?
    /// Bumped by every event; a render finishing under an older generation is stale.
    private var generation = 0
    private var reloadTask: Task<Void, Never>?

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
        generation += 1
        reloadTask?.cancel()
        reloadTask = nil
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
            generation += 1
            reloadTask?.cancel()
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
        generation += 1
        let generation = generation
        let currentSource = force ? nil : document.content?.source
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.render(contentsOf: url, unlessSourceIs: currentSource) }
            }.value
            guard let self, generation == self.generation, let document = self.document else {
                return
            }
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

    /// Reads and renders `url`; `nil` when its text equals `currentSource`. Runs off the main
    /// actor.
    nonisolated static func render(contentsOf url: URL, unlessSourceIs currentSource: String?) throws
        -> DocumentContent?
    {
        let data = try Data(contentsOf: url)
        guard let source = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if source == currentSource {
            return nil
        }
        return DocumentContent(source: source, fallbackTitle: url.lastPathComponent)
    }
}

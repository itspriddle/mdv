import Darwin
import Foundation
import MdvCore

/// Watches the custom themes folder (#35) for any change to its theme files and reports each
/// burst of changes once, after a short debounce.
///
/// `FileWatcher` watches one document; this watches a folder whose files come and go, with
/// the same kernel mechanism (kqueue `DispatchSource`s) and the same debounce shape:
/// - the folder itself (`.write` when an entry is added, removed, or renamed; `.delete` and
///   `.rename` when the folder goes away), which covers new files and atomic saves (a new
///   inode renamed over the old name);
/// - every theme file in it (`.write`, `.extend`, `.attrib`, …), which covers edits in place;
/// - while the folder doesn't exist, its nearest existing ancestor, so creating it (even with
///   `mkdir -p` of several levels) is noticed.
///
/// After each burst (`latency` of quiet, at most `maximumLatency` from the first event) the
/// watcher re-arms its sources for what is on disk now and then calls `handler`. Sources are
/// armed before the handler runs, so a change made while the handler reads the folder causes
/// another report. The handler decides whether anything really changed (the library compares
/// the loaded catalog).
///
/// Thread safety: all mutable state is confined to `queue`; `handler` runs on `queue`.
final class ThemeFolderWatcher: @unchecked Sendable {
    struct Timing: Sendable {
        /// Quiet time after the last kernel event before the handler runs.
        var latency: DispatchTimeInterval = .milliseconds(100)
        /// Longest wait from the first event of a burst, so a steady stream still reports.
        var maximumLatency: DispatchTimeInterval = .milliseconds(300)
    }

    /// The most theme files watched individually, as `CustomThemeFolder` loads at most that many.
    static var maximumWatchedFiles: Int { CustomThemeFolder.maximumThemeCount }

    let folder: URL
    private let queue: DispatchQueue
    private let timing: Timing
    private let handler: @Sendable () -> Void

    // Confined to `queue`.
    private var folderSource: Source?
    /// The ancestor watched while the folder is missing.
    private var ancestorSource: Source?
    private var fileSources: [String: Source] = [:]
    private var burstStart: DispatchTime?
    private var evaluation: DispatchWorkItem?
    private var isStopped = false

    init(
        folder: URL, timing: Timing = Timing(),
        queue: DispatchQueue = DispatchQueue(label: "mdv.theme-folder-watcher", qos: .utility),
        handler: @escaping @Sendable () -> Void
    ) {
        self.folder = folder.standardizedFileURL
        self.timing = timing
        self.queue = queue
        self.handler = handler
    }

    deinit {
        folderSource?.cancel()
        ancestorSource?.cancel()
        fileSources.values.forEach { $0.cancel() }
        evaluation?.cancel()
    }

    /// Starts watching and reports the folder's current state once (on `queue`), so the first
    /// load runs off the caller's thread too.
    func start() {
        queue.async { [weak self] in
            guard let self, !isStopped else {
                return
            }
            evaluate()
        }
    }

    /// Stops watching and closes every descriptor. Nothing is reported afterwards.
    func stop() {
        queue.sync {
            isStopped = true
            evaluation?.cancel()
            evaluation = nil
            folderSource?.cancel()
            folderSource = nil
            ancestorSource?.cancel()
            ancestorSource = nil
            fileSources.values.forEach { $0.cancel() }
            fileSources = [:]
        }
    }

    /// Reports soon, as if the folder had changed.
    func checkForChanges() {
        queue.async { [weak self] in
            self?.kernelEventDidArrive()
        }
    }

    // MARK: Debounce

    private func kernelEventDidArrive() {
        guard !isStopped else {
            return
        }
        let now = DispatchTime.now()
        let start = burstStart ?? now
        burstStart = start
        evaluation?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluate()
        }
        evaluation = item
        queue.asyncAfter(deadline: min(now + timing.latency, start + timing.maximumLatency), execute: item)
    }

    private func evaluate() {
        evaluation = nil
        burstStart = nil
        guard !isStopped else {
            return
        }
        rearm()
        handler()
    }

    // MARK: Sources

    /// Watches what exists now: the folder and its theme files, or the nearest ancestor.
    private func rearm() {
        let folderPath = folder.path(percentEncoded: false)
        if let identity = Self.directoryIdentity(atPath: folderPath) {
            ancestorSource?.cancel()
            ancestorSource = nil
            if folderSource?.identity != identity {
                folderSource?.cancel()
                folderSource = makeSource(path: folderPath, events: [.write, .delete, .rename, .revoke, .link])
            }
            rearmFiles()
            return
        }

        // The folder is missing: drop its sources, watch the deepest ancestor that exists.
        folderSource?.cancel()
        folderSource = nil
        fileSources.values.forEach { $0.cancel() }
        fileSources = [:]
        var ancestor = folder.deletingLastPathComponent()
        while Self.directoryIdentity(atPath: ancestor.path(percentEncoded: false)) == nil, ancestor.path != "/" {
            ancestor = ancestor.deletingLastPathComponent()
        }
        let path = ancestor.path(percentEncoded: false)
        if ancestorSource?.path != path || ancestorSource?.identity != Self.directoryIdentity(atPath: path) {
            ancestorSource?.cancel()
            ancestorSource = makeSource(path: path, events: [.write, .delete, .rename, .revoke])
        }
        // Something on the way down may have appeared between the walk and the open: look
        // again rather than miss it (its event went to a folder we weren't watching yet).
        if Self.directoryIdentity(atPath: Self.nextComponent(of: folder, below: ancestor).path(percentEncoded: false))
            != nil
        {
            kernelEventDidArrive()
        }
    }

    /// Watches each theme file in the folder (by name; replaced inodes are re-opened).
    private func rearmFiles() {
        let names = Set(
            CustomThemeFolder(url: folder).themeFileNames().prefix(Self.maximumWatchedFiles))
        for (name, source) in fileSources where !names.contains(name) {
            source.cancel()
            fileSources[name] = nil
        }
        for name in names {
            let path = folder.appending(path: name, directoryHint: .notDirectory).path(percentEncoded: false)
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                // Not a regular file (a link, a folder): the load reports it; nothing to watch.
                fileSources[name]?.cancel()
                fileSources[name] = nil
                continue
            }
            if fileSources[name]?.identity != FileIdentity(info) {
                fileSources[name]?.cancel()
                fileSources[name] = makeSource(
                    path: path, events: [.write, .extend, .attrib, .delete, .rename, .link, .revoke], noFollow: true)
            }
        }
    }

    private struct Source {
        let path: String
        let source: any DispatchSourceFileSystemObject
        let identity: FileIdentity

        func cancel() {
            source.cancel()
        }
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent, noFollow: Bool = false) -> Source? {
        // O_NONBLOCK: never wait on a pipe someone named *.css (the lstat check runs first, but
        // the name can be replaced in between).
        let descriptor = open(path, O_EVTONLY | O_CLOEXEC | O_NONBLOCK | (noFollow ? O_NOFOLLOW : 0))
        guard descriptor >= 0 else {
            return nil
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            close(descriptor)
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in
            self?.kernelEventDidArrive()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.activate()
        return Source(path: path, source: source, identity: FileIdentity(info))
    }

    // MARK: Paths

    /// The identity of the folder at `path` (following symbolic links), or nil if there is no
    /// folder there.
    private static func directoryIdentity(atPath path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            return nil
        }
        return FileIdentity(info)
    }

    /// The path one level below `ancestor` on the way to `folder`.
    private static func nextComponent(of folder: URL, below ancestor: URL) -> URL {
        let depth = ancestor.pathComponents.count
        guard folder.pathComponents.count > depth else {
            return folder
        }
        return ancestor.appending(path: folder.pathComponents[depth], directoryHint: .isDirectory)
    }
}

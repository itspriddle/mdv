import Darwin
import Foundation

/// Watches one file, by path, for changes made by any process, and reports them after a short
/// debounce.
///
/// Editors save in different ways, and the watcher handles each one:
/// - in place (`echo >>`, VS Code): the file's own kqueue source fires;
/// - atomically, writing a temporary file and renaming it over the original (TextEdit, most
///   editors), or renaming the original to a backup first (Vim's default `backupcopy=auto`):
///   the path now names a new inode, so the watcher reopens it;
/// - delete then recreate: the parent folder's source fires when the name comes back;
/// - the whole folder deleted and recreated (`git checkout` of a branch without it, build
///   tools): while the folder is missing, the watcher watches its nearest existing ancestor,
///   and follows the path back down as folders reappear.
///
/// After every burst of kernel events (`latency`, capped at `maximumLatency` for a steady
/// stream) the watcher `stat`s the path and compares it with what it last reported, so a burst
/// becomes one event. A path that stays missing for `missingGrace` is a move, if the watched
/// inode still exists under another name, or a deletion. The grace period keeps the middle of a
/// backup-and-rename save (Vim renames the file to `notes.md~` before writing the new one) from
/// looking like a move. A move into the Trash counts as a deletion. After a deletion the
/// watcher keeps watching the folder and reports `.changed` if the file reappears.
///
/// Why not `NSFilePresenter` (which `NSDocument` already is): measured in #21, it reports edits
/// from other processes about a second late, and after a delete it goes silent for good (no
/// deletion, recreation, rename, or later changes). kqueue sources report all of these within
/// milliseconds.
///
/// Thread safety: all mutable state is confined to `queue`. `handler` runs on `queue`.
final class FileWatcher: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        /// The file at the watched path has new contents (or came back after a deletion).
        case changed
        /// The file is gone. The watcher keeps watching for it to reappear.
        case deleted
        /// The file was renamed or moved; the watcher now watches the new location.
        case moved(URL)
    }

    struct Timing: Sendable {
        /// Quiet time after the last kernel event before the path is checked.
        var latency: DispatchTimeInterval = .milliseconds(50)
        /// Longest wait from the first event of a burst, so a steady stream still reports.
        var maximumLatency: DispatchTimeInterval = .milliseconds(150)
        /// How long the path must stay missing before it counts as moved or deleted.
        var missingGrace: DispatchTimeInterval = .milliseconds(300)
    }

    private let queue: DispatchQueue
    private let timing: Timing
    private let handler: @Sendable (Event) -> Void

    // Confined to `queue`.
    private var url: URL
    private var file: WatchedItem?
    private var directory: WatchedItem?
    private var reported: Fingerprint?
    private var isMissing = false
    private var missingSince: DispatchTime?
    private var burstStart: DispatchTime?
    private var evaluation: DispatchWorkItem?
    private var isStopped = false

    init(
        url: URL, timing: Timing = Timing(), queue: DispatchQueue = DispatchQueue(label: "mdv.file-watcher"),
        handler: @escaping @Sendable (Event) -> Void
    ) {
        self.url = url.standardizedFileURL
        self.timing = timing
        self.queue = queue
        self.handler = handler
    }

    deinit {
        file?.source.cancel()
        directory?.source.cancel()
        evaluation?.cancel()
    }

    /// Starts watching. Changes made after this returns are reported.
    func start() {
        queue.sync {
            guard !isStopped else {
                return
            }
            watchDirectory()
            watchFile()
            reported = Fingerprint(path: url.path(percentEncoded: false))
            isMissing = reported == nil
        }
    }

    /// Stops watching and closes the watched descriptors. No events are reported afterwards.
    func stop() {
        queue.sync {
            isStopped = true
            evaluation?.cancel()
            evaluation = nil
            file?.source.cancel()
            file = nil
            directory?.source.cancel()
            directory = nil
        }
    }

    /// Checks the path soon, as if a kernel event had arrived. For hints from other sources
    /// (`NSFilePresenter` callbacks); a check that finds nothing new reports nothing.
    func checkForChanges() {
        queue.async { [weak self] in
            self?.kernelEventDidArrive()
        }
    }

    // MARK: Kernel sources

    private struct WatchedItem {
        let source: any DispatchSourceFileSystemObject
        let path: String
        let identity: FileIdentity
    }

    private func watchFile() {
        file?.source.cancel()
        file = makeSource(
            path: url.path(percentEncoded: false), events: [.write, .extend, .attrib, .delete, .rename, .link, .revoke])
    }

    /// Watches the file's folder or, while that folder is missing, its nearest existing
    /// ancestor, so the folder (and then the file) coming back is seen. Does nothing if that
    /// folder is already watched. Returns whether the watched folder changed: a folder deeper
    /// on the path may have appeared before the new source started, so the caller checks again.
    @discardableResult
    private func watchDirectory() -> Bool {
        let target = Self.nearestExistingFolder(of: url.deletingLastPathComponent())
        if directory?.path == target?.path, directory?.identity == target?.identity {
            return false
        }
        directory?.source.cancel()
        directory = nil
        guard let target else {
            return false
        }
        // `.write`: an entry was added, removed, or renamed. `.delete`/`.rename`: the folder
        // itself went away, so watch further up. `.revoke`: its volume was unmounted.
        directory = makeSource(path: target.path, events: [.write, .delete, .rename, .revoke])
        // A folder that can't be opened isn't watched; checking again would only spin.
        return directory != nil
    }

    /// `folder`, or its nearest ancestor that exists, with its identity.
    private static func nearestExistingFolder(of folder: URL) -> (path: String, identity: FileIdentity)? {
        var candidate = folder.standardizedFileURL
        while true {
            let path = candidate.path(percentEncoded: false)
            var info = stat()
            if stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
                return (path, FileIdentity(info))
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path(percentEncoded: false) != path else {
                return nil
            }
            candidate = parent
        }
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent) -> WatchedItem? {
        let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
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
        return WatchedItem(source: source, path: path, identity: FileIdentity(info))
    }

    // MARK: Debounce and evaluation

    private func kernelEventDidArrive() {
        guard !isStopped else {
            return
        }
        let now = DispatchTime.now()
        let start = burstStart ?? now
        burstStart = start
        schedule(at: min(now + timing.latency, start + timing.maximumLatency))
    }

    private func schedule(at deadline: DispatchTime) {
        evaluation?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluate()
        }
        evaluation = item
        queue.asyncAfter(deadline: deadline, execute: item)
    }

    private func evaluate() {
        evaluation = nil
        burstStart = nil
        guard !isStopped else {
            return
        }
        // First, so a file created after the folder came back is seen by the `stat` below or
        // by the new source.
        if watchDirectory() {
            kernelEventDidArrive()
        }
        let path = url.path(percentEncoded: false)
        if let fingerprint = Fingerprint(path: path) {
            missingSince = nil
            if file?.identity != fingerprint.identity {
                // Replaced by a new inode (atomic save, recreate): watch that one now.
                watchFile()
            }
            if isMissing || fingerprint != reported {
                isMissing = false
                reported = fingerprint
                handler(.changed)
            }
            return
        }

        let now = DispatchTime.now()
        let since = missingSince ?? now
        missingSince = since
        if now < since + timing.missingGrace {
            schedule(at: since + timing.missingGrace)
            return
        }
        if let newURL = movedLocation() {
            url = newURL
            missingSince = nil
            reported = Fingerprint(path: newURL.path(percentEncoded: false))
            watchDirectory()
            handler(.moved(newURL))
            return
        }
        if !isMissing {
            isMissing = true
            reported = nil
            file?.source.cancel()
            file = nil
            handler(.deleted)
        }
    }

    /// Where the watched inode lives now, if it still has a name and that name isn't in a
    /// Trash folder.
    private func movedLocation() -> URL? {
        guard let file else {
            return nil
        }
        let descriptor = Int32(file.source.handle)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_nlink > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else {
            return nil
        }
        guard let path = String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
        else {
            return nil
        }
        let newURL = URL(filePath: path).standardizedFileURL
        guard newURL != url, Fingerprint(path: path)?.identity == file.identity,
            !newURL.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" })
        else {
            return nil
        }
        return newURL
    }
}

/// A file's device and inode: which file a path names.
struct FileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
    }
}

/// What the watcher compares to decide whether a path's contents changed.
struct Fingerprint: Equatable, Sendable {
    let identity: FileIdentity
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int

    /// The fingerprint of the regular file at `path` (following symlinks), or `nil` if there
    /// is none.
    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            return nil
        }
        identity = FileIdentity(info)
        size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec
        modifiedNanoseconds = info.st_mtimespec.tv_nsec
    }
}

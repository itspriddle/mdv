import Darwin
import Foundation
import Synchronization
import Testing

@testable import PeepApp

/// `FileWatcher` against real files, changed the way editors change them. Writes run in a
/// separate process (`/bin/sh`, `/usr/bin/vim`) where that's how editors do it, since the
/// watcher exists for edits made by other apps.
@Suite("FileWatcher", .timeLimit(.minutes(1)))
struct FileWatcherTests {
    /// Collects events from the watcher's queue.
    final class EventLog: Sendable {
        private let events = Mutex<[(event: FileWatcher.Event, time: ContinuousClock.Instant)]>([])

        func append(_ event: FileWatcher.Event) {
            events.withLock { $0.append((event, .now)) }
        }

        var all: [FileWatcher.Event] { events.withLock { $0.map(\.event) } }

        /// Waits until at least `count` events arrived (or `timeout` passed) and returns them.
        func wait(for count: Int, timeout: Duration = .seconds(3)) async throws -> [FileWatcher.Event] {
            let deadline = ContinuousClock.now + timeout
            while all.count < count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            return all
        }

        /// When the first event arrived.
        var firstEventTime: ContinuousClock.Instant? { events.withLock { $0.first?.time } }
    }

    let folder: URL
    let file: URL
    let log = EventLog()

    init() throws {
        folder = try Self.makeFolder()
        file = folder.appending(path: "notes.md")
        try Data("# One\n".utf8).write(to: file)
    }

    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-watcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func makeWatcher(for url: URL? = nil) -> FileWatcher {
        let watcher = FileWatcher(url: url ?? file) { [log] event in log.append(event) }
        watcher.start()
        return watcher
    }

    /// Runs `script` with `/bin/sh` in the test folder, in a separate process.
    func shell(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sh -c \(script)")
    }

    /// Edits notes.md with Vim (no vimrc, so its defaults: `backupcopy=auto`, `writebackup`),
    /// appending a line and writing with `:w`. `settings` are extra `:set` arguments.
    func vim(_ settings: String = "") throws {
        let set = settings.isEmpty ? "" : "-c 'set \(settings)' "
        try shell("/usr/bin/vim -u NONE -N -n -es \(set)-c 'normal! Goedited in vim' -c wq notes.md")
    }

    func contents() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    /// The path with symlinks resolved (`/var` is `/private/var`), as the kernel reports it.
    static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: Save styles

    @Test("in-place append (echo >>) reports one change, fast")
    func appendInPlace() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        let start = ContinuousClock.now
        try shell("echo 'two' >> notes.md")
        #expect(try await log.wait(for: 1) == [.changed])
        let latency = try #require(log.firstEventTime) - start
        // About 50 ms of debounce; the issue's budget is ~200 ms. Loose for loaded CI machines.
        #expect(latency < .milliseconds(500), "reported after \(latency)")
    }

    @Test("truncate and rewrite in place (VS Code) reports a change")
    func rewriteInPlace() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("printf '# Rewritten\\n' > notes.md")
        #expect(try await log.wait(for: 1) == [.changed])
    }

    @Test("atomic save (write a temp file, rename it over) reports a change and keeps watching")
    func atomicRename() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("printf '# Atomic\\n' > .notes.tmp && mv .notes.tmp notes.md")
        #expect(try await log.wait(for: 1) == [.changed])
        // The new inode is watched: a later in-place change is seen too.
        try shell("echo 'more' >> notes.md")
        #expect(try await log.wait(for: 2) == [.changed, .changed])
    }

    @Test("atomic save by swapping files (TextEdit's safe save) reports a change")
    func renameSwap() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        let temporary = folder.appending(path: ".notes.md.sb-swap")
        try Data("# Swapped\n".utf8).write(to: temporary)
        #expect(
            renamex_np(temporary.path(percentEncoded: false), file.path(percentEncoded: false), UInt32(RENAME_SWAP))
                == 0)
        try FileManager.default.removeItem(at: temporary)
        #expect(try await log.wait(for: 1) == [.changed])
        #expect(try contents() == "# Swapped\n")
        try shell("echo 'more' >> notes.md")
        #expect(try await log.wait(for: 2) == [.changed, .changed])
    }

    @Test(
        "Vim :w reports one change and keeps watching the path",
        arguments: [
            "",  // Vim's defaults: backupcopy=auto, writebackup
            "backupcopy=no",  // rename the original to a backup, write a new file
            "backupcopy=yes",  // copy to a backup, overwrite the original in place
            "backupcopy=no backup",  // keep the renamed backup (notes.md~) around
        ])
    func vimSave(settings: String) async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try vim(settings)
        #expect(try contents().contains("edited in vim"))
        #expect(try await log.wait(for: 1) == [.changed])
        // Never mistaken for a move to the backup name; the path is still watched.
        try shell("echo 'after vim' >> notes.md")
        #expect(try await log.wait(for: 2) == [.changed, .changed])
    }

    // MARK: Deletion, recreation, moves

    @Test("delete reports deleted; recreate reports a change")
    func deleteAndRecreate() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("rm notes.md")
        #expect(try await log.wait(for: 1) == [.deleted])
        try shell("printf '# Back\\n' > notes.md")
        #expect(try await log.wait(for: 2) == [.deleted, .changed])
        try shell("echo 'more' >> notes.md")
        #expect(try await log.wait(for: 3) == [.deleted, .changed, .changed])
    }

    @Test("delete then recreate within the grace period is just a change")
    func quickRecreate() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("rm notes.md && sleep 0.1 && printf '# Back\\n' > notes.md")
        #expect(try await log.wait(for: 1) == [.changed])
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.all == [.changed])
    }

    @Test("rename reports the new location and follows the file")
    func rename() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("mv notes.md renamed.md")
        let events = try await log.wait(for: 1)
        guard case .moved(let newURL)? = events.first else {
            Issue.record("expected a move, got \(events)")
            return
        }
        #expect(Self.realPath(newURL) == Self.realPath(folder.appending(path: "renamed.md")))
        try shell("echo 'more' >> renamed.md")
        #expect(try await log.wait(for: 2).last == .changed)
    }

    @Test("move to another folder reports the new location")
    func moveToFolder() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("mkdir sub && mv notes.md sub/notes.md")
        let events = try await log.wait(for: 1)
        guard case .moved(let newURL)? = events.first else {
            Issue.record("expected a move, got \(events)")
            return
        }
        #expect(Self.realPath(newURL) == Self.realPath(folder.appending(path: "sub/notes.md")))
        // The new folder is watched: an atomic save there is seen.
        try shell("printf 'x\\n' > sub/.tmp && mv sub/.tmp sub/notes.md")
        #expect(try await log.wait(for: 2).last == .changed)
    }

    @Test("a move into the Trash is a deletion")
    func moveToTrash() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("mkdir .Trash && mv notes.md .Trash/notes.md")
        #expect(try await log.wait(for: 1) == [.deleted])
    }

    // MARK: Coalescing and lifecycle

    @Test("a burst of writes is coalesced")
    func burst() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do echo $i >> notes.md; done")
        _ = try await log.wait(for: 1)
        try await Task.sleep(for: .milliseconds(300))
        #expect((1...2).contains(log.all.count), "events: \(log.all)")
    }

    @Test("other files in the folder don't report changes")
    func siblings() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        try shell("echo x > other.md && echo y >> other.md && rm other.md && touch .notes.md.swp")
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.all.isEmpty)
    }

    @Test("reports nothing after stop")
    func stop() async throws {
        let watcher = makeWatcher()
        watcher.stop()
        try shell("echo 'two' >> notes.md && rm notes.md")
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.all.isEmpty)
    }

    @Test("checkForChanges reports only real changes")
    func hint() async throws {
        let watcher = makeWatcher()
        defer { watcher.stop() }
        watcher.checkForChanges()
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.all.isEmpty)
    }
}

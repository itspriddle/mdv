import Foundation
import Testing

@testable import MdvApp

/// The document's folder deleted, recreated, or renamed (#41).
extension FileWatcherTests {
    /// Creates `docs/notes.md` (under `subpath` inside the test folder) and returns its URL.
    func nestedFile(_ subpath: String = "docs") throws -> URL {
        let nested = folder.appending(path: subpath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let url = nested.appending(path: "notes.md")
        try Data("# One\n".utf8).write(to: url)
        return url
    }

    @Test("folder deleted reports deleted; recreated with the file reports a change and keeps watching")
    func folderDeleteAndRecreate() async throws {
        let watcher = makeWatcher(for: try nestedFile())
        defer { watcher.stop() }
        try shell("rm -rf docs")
        #expect(try await log.wait(for: 1) == [.deleted])
        try shell("mkdir docs && printf '# Back\\n' > docs/notes.md")
        #expect(try await log.wait(for: 2) == [.deleted, .changed])
        try shell("echo 'more' >> docs/notes.md")
        #expect(try await log.wait(for: 3) == [.deleted, .changed, .changed])
    }

    @Test("folder recreated empty, then the file written later, reports a change")
    func folderRecreatedThenFile() async throws {
        let watcher = makeWatcher(for: try nestedFile())
        defer { watcher.stop() }
        try shell("rm -rf docs")
        #expect(try await log.wait(for: 1) == [.deleted])
        try shell("mkdir docs")
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.all == [.deleted])
        try shell("printf '# Back\\n' > docs/notes.md")
        #expect(try await log.wait(for: 2) == [.deleted, .changed])
    }

    @Test("folder deleted and recreated within the grace period (git checkout) is just a change")
    func folderQuickRecreate() async throws {
        let watcher = makeWatcher(for: try nestedFile())
        defer { watcher.stop() }
        try shell("rm -rf docs && mkdir docs && printf '# Back\\n' > docs/notes.md")
        #expect(try await log.wait(for: 1) == [.changed])
        try shell("echo 'more' >> docs/notes.md")
        #expect(try await log.wait(for: 2) == [.changed, .changed])
    }

    @Test("several nested folders recreated at once report a change")
    func nestedFoldersRecreated() async throws {
        let watcher = makeWatcher(for: try nestedFile("a/b/c"))
        defer { watcher.stop() }
        try shell("rm -rf a")
        #expect(try await log.wait(for: 1) == [.deleted])
        try shell("mkdir -p a/b/c && printf '# Back\\n' > a/b/c/notes.md")
        #expect(try await log.wait(for: 2) == [.deleted, .changed])
        try shell("echo 'more' >> a/b/c/notes.md")
        #expect(try await log.wait(for: 3) == [.deleted, .changed, .changed])
    }

    @Test("nested folders recreated one at a time report a change")
    func nestedFoldersRecreatedSlowly() async throws {
        let watcher = makeWatcher(for: try nestedFile("a/b"))
        defer { watcher.stop() }
        try shell("rm -rf a")
        #expect(try await log.wait(for: 1) == [.deleted])
        try shell("mkdir a && sleep 0.2 && mkdir a/b && sleep 0.2 && printf '# Back\\n' > a/b/notes.md")
        #expect(try await log.wait(for: 2) == [.deleted, .changed])
    }

    @Test("renaming the folder reports the file's new location")
    func folderRename() async throws {
        let watcher = makeWatcher(for: try nestedFile())
        defer { watcher.stop() }
        try shell("mv docs moved")
        let events = try await log.wait(for: 1)
        guard case .moved(let newURL)? = events.first else {
            Issue.record("expected a move, got \(events)")
            return
        }
        #expect(Self.realPath(newURL) == Self.realPath(folder.appending(path: "moved/notes.md")))
        try shell("echo 'more' >> moved/notes.md")
        #expect(try await log.wait(for: 2).last == .changed)
    }
}

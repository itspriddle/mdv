import Foundation
import PeepCore
import Testing

/// `cmd | peep` (#68): the CLI's private handoff file, and the app's checks before it reads and
/// deletes one. Anything that names a file the app didn't verify as a handoff is untouched.
@Suite("Standard input handoff")
struct StandardInputHandoffTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-handoff-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    static func attributes(_ url: URL) throws -> (permissions: Int, owner: Int) {
        let values = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (
            (values[.posixPermissions] as? NSNumber)?.intValue ?? -1,
            (values[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        )
    }

    /// A folder and file shaped like a handoff, made by hand with the given permissions.
    func fakeHandoff(folderName: String = "peep-stdin.fake1234", folderMode: Int = 0o700, fileMode: Int = 0o600)
        throws -> URL
    {
        let handoffFolder = folder.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: handoffFolder, withIntermediateDirectories: true)
        let file = handoffFolder.appending(path: StandardInputHandoff.fileName)
        try Data("# Fake\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: fileMode], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: folderMode], ofItemAtPath: handoffFolder.path)
        return file
    }

    @Test("the CLI's file is private, in its own new folder, and the app takes it once")
    func roundTrip() throws {
        defer { cleanUp() }
        let file = try StandardInputHandoff.write(Data("# Piped\n".utf8), inFolder: folder)
        let handoffFolder = file.deletingLastPathComponent()
        #expect(file.lastPathComponent == StandardInputHandoff.fileName)
        #expect(handoffFolder.lastPathComponent.hasPrefix(StandardInputHandoff.folderPrefix))
        #expect(try Self.attributes(handoffFolder) == (0o700, Int(getuid())))
        #expect(try Self.attributes(file) == (0o600, Int(getuid())))

        #expect(try StandardInputHandoff.take(file) == "# Piped\n")
        #expect(try contents().isEmpty, "the file and its folder are gone")
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(file) }
    }

    @Test("each write gets a new folder")
    func unpredictable() throws {
        defer { cleanUp() }
        let first = try StandardInputHandoff.write(Data("a".utf8), inFolder: folder)
        let second = try StandardInputHandoff.write(Data("b".utf8), inFolder: folder)
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        StandardInputHandoff.remove(first)
        StandardInputHandoff.remove(second)
        #expect(try contents().isEmpty)
    }

    @Test("writing into a missing folder throws and leaves nothing")
    func writeFailure() throws {
        defer { cleanUp() }
        #expect(throws: (any Error).self) {
            try StandardInputHandoff.write(Data("a".utf8), inFolder: folder.appending(path: "missing"))
        }
        #expect(try contents().isEmpty)
    }

    @Test("a handoff that is too large or not UTF-8 is deleted, with the reason")
    func badContents() throws {
        defer { cleanUp() }
        let large = try StandardInputHandoff.write(
            Data(repeating: 0x61, count: StandardInputHandoff.maximumBytes + 1), inFolder: folder)
        #expect(throws: StandardInputHandoff.Failure.tooLarge) { try StandardInputHandoff.take(large) }
        let binary = try StandardInputHandoff.write(Data([0xFF, 0xFE, 0x00]), inFolder: folder)
        #expect(throws: StandardInputHandoff.Failure.notUTF8) { try StandardInputHandoff.take(binary) }
        #expect(try contents().isEmpty)
        #expect(StandardInputHandoff.Failure.tooLarge.localizedDescription.contains("10 MB"))
    }

    @Test("exactly the maximum is read")
    func maximum() throws {
        defer { cleanUp() }
        let file = try StandardInputHandoff.write(
            Data(repeating: 0x61, count: StandardInputHandoff.maximumBytes), inFolder: folder)
        #expect(try StandardInputHandoff.take(file).utf8.count == StandardInputHandoff.maximumBytes)
    }

    // MARK: Hostile senders: nothing is read or deleted

    @Test("a file that isn't named like a handoff is left alone")
    func ordinaryFiles() throws {
        defer { cleanUp() }
        let notes = folder.appending(path: "notes.md")
        try Data("# Mine\n".utf8).write(to: notes)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: notes.path)
        let wrongFolder = try fakeHandoff(folderName: "stdin-folder")
        let bareFolder = try fakeHandoff(folderName: StandardInputHandoff.folderPrefix)
        for url in [notes, wrongFolder, bareFolder, folder.appending(path: "missing/stdin.md")] {
            #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(url) }
        }
        #expect(FileManager.default.fileExists(atPath: notes.path))
        #expect(FileManager.default.fileExists(atPath: wrongFolder.path))
        #expect(FileManager.default.fileExists(atPath: bareFolder.path))
    }

    @Test(
        "a handoff-shaped file others could read or write is left alone",
        arguments: [(0o755, 0o600), (0o700, 0o644), (0o700, 0o606), (0o770, 0o600)])
    func permissions(folderMode: Int, fileMode: Int) throws {
        defer { cleanUp() }
        let file = try fakeHandoff(folderMode: folderMode, fileMode: fileMode)
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(file) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a hand-made file with the right shape is taken (the check is on shape, not origin)")
    func handMade() throws {
        defer { cleanUp() }
        let file = try fakeHandoff()
        #expect(try StandardInputHandoff.take(file) == "# Fake\n")
        #expect(try contents().isEmpty)
    }

    @Test("a symbolic link, as the file or the folder, is left alone, and so is its target")
    func symbolicLinks() throws {
        defer { cleanUp() }
        let target = folder.appending(path: "secret.md")
        try Data("# Secret\n".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)

        let linkFolder = folder.appending(path: "peep-stdin.link1234", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: linkFolder.path)
        let fileLink = linkFolder.appending(path: StandardInputHandoff.fileName)
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: target)
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(fileLink) }

        let real = try fakeHandoff(folderName: "real-folder")
        let folderLink = folder.appending(path: "peep-stdin.dir12345")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: real.deletingLastPathComponent())
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) {
            try StandardInputHandoff.take(folderLink.appending(path: StandardInputHandoff.fileName))
        }
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: real.path))
        #expect(FileManager.default.fileExists(atPath: fileLink.path))
    }

    @Test("a hard link to another file is left alone")
    func hardLink() throws {
        defer { cleanUp() }
        let target = folder.appending(path: "secret.md")
        try Data("# Secret\n".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let linkFolder = folder.appending(path: "peep-stdin.hard1234", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: linkFolder.path)
        let link = linkFolder.appending(path: StandardInputHandoff.fileName)
        try FileManager.default.linkItem(at: target, to: link)
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(link) }
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: link.path))
    }

    @Test("a FIFO named like a handoff is left alone, without blocking")
    func fifo() throws {
        defer { cleanUp() }
        let fifoFolder = folder.appending(path: "peep-stdin.fifo1234", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fifoFolder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fifoFolder.path)
        let fifo = fifoFolder.appending(path: StandardInputHandoff.fileName)
        #expect(mkfifo(fifo.path(percentEncoded: false), 0o600) == 0)
        #expect(throws: StandardInputHandoff.Failure.notAHandoff) { try StandardInputHandoff.take(fifo) }
        #expect(FileManager.default.fileExists(atPath: fifo.path))
    }
}

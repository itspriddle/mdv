import Foundation
import Testing

@testable import PeepCore

/// `FileSystemFolderReader` (moved from the app for `peep --html`, #65) on a real temp folder.
@Suite("File system folder reader")
struct FileSystemFolderReaderTests {
    @Test("lists regular files and folders; leaves out symbolic links and packages")
    func entries() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "peep-reader-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: folder) }
        try manager.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appending(path: "Tool.app"), withIntermediateDirectories: true)
        try Data("# A\n".utf8).write(to: folder.appending(path: "A.md"))
        try manager.createSymbolicLink(
            at: folder.appending(path: "Link.md"), withDestinationURL: folder.appending(path: "A.md"))
        try manager.createSymbolicLink(
            at: folder.appending(path: "linked-folder"), withDestinationURL: folder.appending(path: "sub"))

        let entries = try #require(FileSystemFolderReader().entries(ofFolderAtPath: folder.path))
        let sorted = entries.sorted { $0.name < $1.name }
        #expect(
            sorted == [
                WikiLinkFolderEntry(name: "A.md", isFolder: false), WikiLinkFolderEntry(name: "sub", isFolder: true),
            ])
        #expect(FileSystemFolderReader().entries(ofFolderAtPath: folder.appending(path: "gone").path) == nil)
    }

    @Test("a file system resolver needs a file URL whose folder exists")
    func resolverForDocument() throws {
        let remote = try #require(URL(string: "https://example.com/a.md"))
        #expect(FolderWikiLinkResolver.fileSystem(forDocumentAt: remote, root: nil) == nil)
        let gone = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/a.md")
        #expect(FolderWikiLinkResolver.fileSystem(forDocumentAt: gone, root: nil) == nil)
    }
}

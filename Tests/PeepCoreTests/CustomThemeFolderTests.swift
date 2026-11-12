import Darwin
import Foundation
import Testing

@testable import PeepCore

/// Reading the custom themes folder (#35): what loads, what is reported, and what is ignored.
@Suite("Custom theme folder")
struct CustomThemeFolderTests {
    /// A temporary folder, removed by the caller.
    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-custom-themes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("a missing folder has no themes and no failures")
    func missingFolder() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "peep-missing-\(UUID().uuidString)")
        #expect(CustomThemeFolder(url: folder).load() == .empty)
    }

    @Test("the folder loads every theme, reports bad files, and ignores everything else")
    func loadFolder() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        try write("zeta.css", "/* peep-theme\nname: Alpha\n*/\np {}")
        try write("beta.CSS", "p {}")
        try write("imports.css", "@import 'x.css';")
        try write("notes.txt", "not a theme")
        try write(".hidden.css", "p {}")
        try write("README", "p {}")
        try Data([0xFF, 0xFE, 0x00, 0x70]).write(to: folder.appending(path: "binary.css"))
        try Data([0x70, 0x20, 0xC3, 0x28]).write(to: folder.appending(path: "latin1.css"))
        try Data([0xEF, 0xBB, 0xBF] + Array("p { color: red }".utf8)).write(to: folder.appending(path: "bom.css"))
        try Data(repeating: 0x20, count: CustomThemeFolder.maximumFileSize + 1).write(
            to: folder.appending(path: "huge.css"))
        try FileManager.default.createDirectory(
            at: folder.appending(path: "folder.css"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "passwd.css"), withDestinationURL: URL(filePath: "/etc/passwd"))
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "inside.css"), withDestinationURL: folder.appending(path: "beta.CSS"))
        #expect(mkfifo(folder.appending(path: "pipe.css").path(percentEncoded: false), 0o600) == 0)

        let catalog = CustomThemeFolder(url: folder).load()
        #expect(catalog.themes.map(\.id) == ["custom:zeta.css", "custom:beta.CSS", "custom:bom.css"])
        #expect(catalog.themes.map(\.displayName) == ["Alpha", "beta", "bom"])
        #expect(catalog.themes.last?.stylesheet == "p { color: red }", "the byte order mark is dropped")
        let failures = Dictionary(uniqueKeysWithValues: catalog.failures.map { ($0.fileName, $0.problem) })
        #expect(
            failures == [
                "imports.css": .importRule(line: 1),
                "binary.css": .containsNUL,
                "latin1.css": .notUTF8,
                "huge.css": .tooLarge(
                    bytes: CustomThemeFolder.maximumFileSize + 1, limit: CustomThemeFolder.maximumFileSize),
                "folder.css": .notRegularFile,
                "passwd.css": .symbolicLink,
                "inside.css": .symbolicLink,
                "pipe.css": .notRegularFile,
            ])
        #expect(
            catalog.failures.first { $0.fileName == "imports.css" }?.message
                == "imports: @import isn’t allowed (line 1)")
    }

    @Test("a themes folder that is a symbolic link is followed")
    func symlinkedFolder() throws {
        let real = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: real) }
        try Data("p {}".utf8).write(to: real.appending(path: "linked.css"))
        let link = FileManager.default.temporaryDirectory.appending(path: "peep-themes-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }
        #expect(CustomThemeFolder(url: link).load().themes.map(\.id) == ["custom:linked.css"])
    }

    @Test("a file where the folder should be is reported")
    func folderIsFile() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Themes")
        try Data().write(to: file)
        let catalog = CustomThemeFolder(url: file).load()
        #expect(catalog.themes.isEmpty)
        #expect(catalog.failures == [CustomThemeFailure(fileName: "Themes", problem: .notRegularFile, isFolder: true)])
    }

    @Test("past the theme limit, the rest are reported once")
    func tooManyThemes() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0...CustomThemeFolder.maximumThemeCount {
            try Data("p {}".utf8).write(to: folder.appending(path: "theme \(index).css"))
        }
        let catalog = CustomThemeFolder(url: folder).load()
        #expect(catalog.themes.count == CustomThemeFolder.maximumThemeCount)
        #expect(catalog.failures.map(\.problem) == [.tooManyThemes(limit: CustomThemeFolder.maximumThemeCount)])
        // Finder order: "theme 100" is the one left out.
        #expect(!catalog.themes.contains { $0.id == "custom:theme 100.css" })
    }

    @Test("a file that grows past the limit while being read is rejected")
    func readLimit() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.css")
        try Data(repeating: 0x20, count: 11).write(to: file)
        #expect(throws: CustomThemeProblem.tooLarge(bytes: 11, limit: 10)) {
            try CustomThemeFolder.readTheme(at: file, limit: 10)
        }
        #expect(try CustomThemeFolder.readTheme(at: file, limit: 11).count == 11)
    }

    @Test("theme file names: visible, .css")
    func fileNames() {
        #expect(CustomThemeFolder.isThemeFileName("a.css"))
        #expect(CustomThemeFolder.isThemeFileName("A.Css"))
        #expect(!CustomThemeFolder.isThemeFileName(".a.css"))
        #expect(!CustomThemeFolder.isThemeFileName("a.css.txt"))
        #expect(!CustomThemeFolder.isThemeFileName("css"))
        #expect(!CustomThemeFolder.isThemeFileName("a.scss"))
    }

    @Test("problems read as short sentences")
    func messages() {
        #expect(
            CustomThemeProblem.tooLarge(bytes: 600 * 1024, limit: 512 * 1024).description
                == "Too large (600 KB; the limit is 512 KB)")
        #expect(
            CustomThemeProblem.externalURL(line: 4).description == "Only data:image URLs are allowed in url() (line 4)")
        #expect(
            CustomThemeFailure(fileName: "x", problem: .notUTF8, isFolder: true).message
                == "Themes folder: Not UTF-8 text")
    }
}

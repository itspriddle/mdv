import AppKit
import Foundation
import MdvCore
import Testing

@testable import MdvApp

/// Open Documents events (#67): `DocumentOpener` opens the files and applies `mdv --theme`'s
/// parameter, which is untrusted input.
@MainActor
@Suite("Opening from Open Documents events", .serialized, .timeLimit(.minutes(1)))
final class DocumentOpenerTests {
    let folder: URL
    let throwawayDefaults: ThrowawayDefaults
    var errors: [any Error] = []
    var opened: [NSDocument] = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-opener-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        throwawayDefaults = try ThrowawayDefaults("mdv-opener-tests")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func file(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data("# \(name)\n".utf8).write(to: url)
        return url
    }

    func opener() -> DocumentOpener {
        DocumentOpener(
            themeSettings: ThemeSettings(defaults: throwawayDefaults.defaults, isPersistent: true),
            presentError: { [weak self] in self?.errors.append($0) })
    }

    /// Opens `urls` with `themeID` and returns each file's window controller.
    func open(_ urls: [URL], themeID: String?) async throws -> [DocumentWindowController] {
        let opener = opener()
        await withCheckedContinuation { continuation in
            opener.open(urls, parameters: AppOpenParameters(themeID: themeID)) {
                continuation.resume()
            }
        }
        return try urls.map { url in
            let document = try #require(NSDocumentController.shared.document(for: url))
            if !opened.contains(where: { $0 === document }) {
                opened.append(document)
            }
            return try #require(document.windowControllers.first as? DocumentWindowController)
        }
    }

    func closeAll() {
        for document in opened {
            document.close()
        }
        opened.removeAll()
    }

    @Test("files open in windows with the theme as the window's pick")
    func theme() async throws {
        defer { closeAll() }
        let controllers = try await open([try file("a.md"), try file("b.md")], themeID: "serif")
        for controller in controllers {
            #expect(controller.pickedThemeID == "serif")
            #expect(controller.theme.id == "serif")
            #expect(controller.window?.isVisible == true)
        }
    }

    @Test("without a theme, a window follows its usual theme")
    func noTheme() async throws {
        defer { closeAll() }
        let controller = try #require(try await open([try file("plain.md")], themeID: nil).first)
        #expect(controller.pickedThemeID == nil)
    }

    @Test("an already-open window switches to the theme, and stays one window")
    func alreadyOpen() async throws {
        defer { closeAll() }
        let url = try file("open.md")
        let first = try #require(try await open([url], themeID: nil).first)
        let second = try #require(try await open([url], themeID: "document").first)
        #expect(first === second)
        #expect(first.pickedThemeID == "document")
        #expect(NSDocumentController.shared.documents.filter { $0.fileURL == url }.count == 1)
    }

    @Test(
        "unknown or implausible theme ids are ignored; custom ids wait for their file",
        arguments: [
            ("nope", nil), ("GITHUB", nil), ("", nil), ("a\u{0}b", nil), (String(repeating: "x", count: 300), nil),
            ("custom:later.css", "custom:later.css"),
        ] as [(String, String?)])
    func hostileThemes(id: String, expected: String?) async throws {
        defer { closeAll() }
        #expect(opener().usableThemeID(id) == expected)
        let controller = try #require(try await open([try file("hostile.md")], themeID: id).first)
        #expect(controller.pickedThemeID == expected)
    }

    @Test("a file that can't open is presented, and the rest still open")
    func failure() async throws {
        defer { closeAll() }
        let missing = folder.appending(path: "missing.md")
        let good = try file("good.md")
        let opener = opener()
        await withCheckedContinuation { continuation in
            opener.open([missing, good], parameters: AppOpenParameters()) { continuation.resume() }
        }
        if let document = NSDocumentController.shared.document(for: good) {
            opened.append(document)
        }
        #expect(errors.count == 1)
        #expect(opened.count == 1)
    }
}

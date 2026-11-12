import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import PeepApp

/// Extensionless text files (`README`) open from the Open panel, drops, and the document
/// controller, while Peep registers as a handler only for Markdown (#41).
@MainActor
@Suite("Opening extensionless files", .serialized, .timeLimit(.minutes(1)))
struct ExtensionlessOpeningTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "peep-extensionless-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ contents: String = "# Title") throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Opens `url` through the shared document controller, without showing it.
    func openThroughController(_ url: URL) async throws -> MarkdownDocument {
        let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: false)
        return try #require(document as? MarkdownDocument)
    }

    @Test(
        "extensionless text sniffing",
        arguments: [
            ("", false, true),
            ("# README\nplain text", false, true),
            ("caf\u{E9} \u{1F600}", false, true),
        ])
    func sniffText(text: String, isTruncated: Bool, expected: Bool) {
        #expect(ExtensionlessText.looksLikeText(Data(text.utf8), isTruncated: isTruncated) == expected)
    }

    @Test("NUL bytes and invalid UTF-8 aren't text; a character cut off by the read is")
    func sniffBinary() {
        #expect(!ExtensionlessText.looksLikeText(Data([0x23, 0x00, 0x41]), isTruncated: false))
        #expect(!ExtensionlessText.looksLikeText(Data([0x23, 0xFF, 0xFE, 0x41]), isTruncated: false))
        // "é" is C3 A9: cut after C3.
        let cut = Data("abc".utf8) + Data([0xC3])
        #expect(ExtensionlessText.looksLikeText(cut, isTruncated: true))
        #expect(!ExtensionlessText.looksLikeText(cut, isTruncated: false))
    }

    @Test("an extensionless text file opens as plain text; binaries, folders, and other types don't")
    func extensionlessTypes() throws {
        let controller = try #require(NSDocumentController.shared as? DocumentController)
        // macOS types some well-known names (`README`, `INSTALL`) as plain text itself; others
        // (`CHANGELOG`, `CONTRIBUTING`) are `public.data`, which is what this override is for.
        let readme = try file("README", "# Read me")
        let changelog = try file("CHANGELOG", "# Changes")
        let empty = try file("EMPTY", "")
        let binary = folder.appending(path: "BINARY")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x00]).write(to: binary)
        let json = try file("data.json", "{}")
        let subfolder = folder.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        #expect(try controller.typeForContents(of: readme) == UTType.plainText.identifier)
        #expect(controller.canOpen(readme))
        #expect(try controller.typeForContents(of: changelog) == UTType.plainText.identifier)
        #expect(controller.canOpen(changelog))
        #expect(controller.canOpen(empty))
        #expect(!controller.canOpen(binary))
        #expect(!controller.canOpen(subfolder))
        #expect(!controller.canOpen(folder.appending(path: "MISSING")))
        // A file with an extension keeps its own type, even when its contents are text.
        #expect(try controller.typeForContents(of: json) != UTType.plainText.identifier)
        #expect(!controller.canOpen(json))
        #expect(controller.canOpen(try file("notes.md")))
    }

    @Test("the Open panel enables Markdown, plain text, README, and folders; not binaries or packages")
    func openPanelFilter() throws {
        let controller = try #require(NSDocumentController.shared as? DocumentController)
        let filter = OpenPanelFilter(controller: controller)
        let panel = NSOpenPanel()
        let binary = folder.appending(path: "BINARY")
        try Data([0x00, 0x01]).write(to: binary)
        let package = folder.appending(path: "Thing.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let subfolder = folder.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        #expect(filter.panel(panel, shouldEnable: try file("a.md")))
        #expect(filter.panel(panel, shouldEnable: try file("b.txt", "plain")))
        #expect(filter.panel(panel, shouldEnable: try file("README", "plain")))
        #expect(filter.panel(panel, shouldEnable: try file("CHANGELOG", "plain")))
        #expect(filter.panel(panel, shouldEnable: subfolder))
        #expect(!filter.panel(panel, shouldEnable: binary))
        #expect(!filter.panel(panel, shouldEnable: try file("c.png", "not really a png")))
        #expect(!filter.panel(panel, shouldEnable: package))
    }

    @Test("a dropped README or CHANGELOG opens; a dropped extensionless binary doesn't")
    func droppedExtensionless() throws {
        let readme = try file("README", "# Read me")
        let changelog = try file("CHANGELOG", "# Changes")
        let binary = folder.appending(path: "BINARY")
        try Data([0x00, 0x01]).write(to: binary)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("peep-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([binary, readme, changelog].map { $0 as NSURL })
        #expect(DocumentDrop.openableFiles(on: pasteboard).map(\.lastPathComponent) == ["README", "CHANGELOG"])
    }

    @Test("a CHANGELOG (typed public.data) opens through the document controller and renders as Markdown")
    func opensChangelog() async throws {
        let changelog = try file("CHANGELOG", "# Read me\n\nText.")
        let document = try await openThroughController(changelog)
        defer { document.close() }
        #expect(document.fileType == UTType.plainText.identifier)
        await document.pendingRender?.value
        #expect(document.content?.source == "# Read me\n\nText.")
        #expect(document.content?.page.title == "Read me")
    }

    @Test("Peep registers as a handler only for Markdown, never plain text or arbitrary data")
    func handlerRegistration() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let ranks = Dictionary(
            types.flatMap { type in
                ((type["LSItemContentTypes"] as? [String]) ?? []).map { ($0, type["LSHandlerRank"] as? String) }
            },
            uniquingKeysWith: { first, _ in first })
        #expect(ranks["public.plain-text"] == "None")
        #expect(ranks["net.daringfireball.markdown"] == "Alternate")
        for broad in ["public.data", "public.item", "public.content", "public.text"] {
            #expect(ranks[broad] == nil, "declares \(broad)")
        }
        let extensions = types.flatMap { ($0["CFBundleTypeExtensions"] as? [String]) ?? [] }
        #expect(!extensions.contains("*"))
    }
}

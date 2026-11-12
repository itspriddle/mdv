import Foundation
import Testing

@testable import PeepCore

/// The per-flavor fixture corpus (`Fixtures/flavors/<flavor id>/`, see its README): each
/// `NAME.md` rendered with its folder's flavor must equal the recorded `NAME.html`.
///
/// Re-record after an intended output change:
///
///     PEEP_RECORD_SNAPSHOTS=1 swift test --filter FlavorCorpusTests
@Suite("Flavor fixture corpus")
struct FlavorCorpusTests {
    struct Fixture: CustomTestStringConvertible, Sendable {
        var flavorID: String
        var name: String
        var testDescription: String { "\(flavorID)/\(name)" }
    }

    static let fixtures: [Fixture] = {
        guard let root = try? rootURL(),
            let folders = try? FileManager.default.contentsOfDirectory(atPath: root.path)
        else {
            return []
        }
        return folders.sorted().flatMap { folder -> [Fixture] in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: folder).path)) ?? []
            return files.filter { $0.hasSuffix(".md") }.sorted().map {
                Fixture(flavorID: folder, name: String($0.dropLast(3)))
            }
        }
    }()

    @Test("every registered flavor has fixtures, and every fixture folder is a registered flavor")
    func foldersMatchRegistry() throws {
        let root = try Self.rootURL()
        var isDirectory: ObjCBool = false
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            FileManager.default.fileExists(atPath: root.appending(path: $0).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        #expect(Set(folders) == Set(FlavorRegistry.bundled.flavors.map(\.id)))
        for flavor in FlavorRegistry.bundled.flavors {
            #expect(Self.fixtures.contains { $0.flavorID == flavor.id }, "\(flavor.id) has no fixtures")
        }
    }

    @Test("output matches the recorded fixture", arguments: fixtures)
    func matchesRecording(_ fixture: Fixture) throws {
        let folder = try Self.rootURL().appending(path: fixture.flavorID)
        let markdown = try String(contentsOf: folder.appending(path: "\(fixture.name).md"), encoding: .utf8)
        var options = RenderOptions(flavor: FlavorRegistry.bundled.flavor(id: fixture.flavorID))
        var renderer = HTMLRenderer(options: options)
        if fixture.name.hasPrefix("wiki-links"), !fixture.name.hasSuffix("-off") {
            options.builtInPreprocessors = [.wikiLinks]
            renderer = HTMLRenderer(options: options, wikiLinkResolver: FakeWikiLinkResolver(Self.wikiLinkPages))
        }
        let html = renderer.render(markdown).html
        if ProcessInfo.processInfo.environment["PEEP_RECORD_SNAPSHOTS"] != nil {
            let source = URL(filePath: #filePath).deletingLastPathComponent()
                .appending(components: "Fixtures", "flavors", fixture.flavorID, "\(fixture.name).html")
            try html.write(to: source, atomically: true, encoding: .utf8)
            return
        }
        let recorded = try String(contentsOf: folder.appending(path: "\(fixture.name).html"), encoding: .utf8)
        #expect(html == recorded, "\(fixture): \(CorpusNormalizer.firstDifference(html, recorded))")
    }

    /// The pages `wiki-links*.md` fixtures resolve against (`.wikiLinks` on). A `-off` fixture
    /// renders with the defaults, wiki links off.
    static let wikiLinkPages = ["Home.md", "Page-Name.md", "guides/Setup.md", "../notes/Other Page.markdown"]

    @Test("CommonMark leaves every GFM construct literal")
    func commonMarkIsStrict() throws {
        let folder = try Self.rootURL().appending(path: "commonmark")
        for name in ["tables", "task-lists", "strikethrough", "autolinks", "footnotes", "emoji", "alerts"] {
            let html = try String(contentsOf: folder.appending(path: "\(name).html"), encoding: .utf8)
            for marker in [
                "<table", "<input", "<del", "<section", "<sup", "🎉", "href=\"https://example.com/path",
                "markdown-alert",
            ] {
                #expect(!html.contains(marker), "commonmark/\(name) contains \(marker)")
            }
        }
    }

    private static func rootURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "flavors", withExtension: nil, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}

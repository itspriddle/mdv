import AppKit
import Foundation
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Wiki links in a document window (#53): resolved against the real folder at render time,
/// clicked through the window's link policy, missing targets inert, Settings and frontmatter
/// turning them on and off. The click-to-open flow in the running app is `WikiLinksUITests`.
@MainActor
@Suite("Wiki links in the app", .serialized, .timeLimit(.minutes(1)))
final class WikiLinkWindowTests: DocumentWindowTestCase {
    /// `folder` as a real path, which links resolve to.
    var realFolder: URL {
        get throws {
            let real = try #require(realpath(folder.path(percentEncoded: false), nil))
            defer { free(real) }
            return URL(filePath: String(cString: real), directoryHint: .isDirectory)
        }
    }

    func write(_ text: String, to path: String) throws {
        let file = folder.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func evaluate(_ body: String, arguments: [String: Any] = [:], in controller: DocumentWindowController)
        async throws -> Any?
    {
        try await controller.coordinator.webView.callAsyncJavaScript(
            body, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    /// Clicks the first `a.wikilink` whose text is `label`, then lets the policy run.
    func click(_ label: String, in controller: DocumentWindowController) async throws {
        let clicked = try await evaluate(
            """
            const link = [...document.querySelectorAll("a.wikilink")].find((a) => a.textContent === label);
            if (link === undefined) { return false; }
            link.click();
            await new Promise((resolve) => setTimeout(resolve, 100));
            return true;
            """, arguments: ["label": label], in: controller)
        #expect(clicked as? Bool == true, "no wiki link \(label)")
    }

    func hrefs(in controller: DocumentWindowController) async throws -> [String] {
        try await evaluate(
            "return [...document.querySelectorAll('a.wikilink')].map((a) => a.getAttribute('href') ?? '');",
            in: controller) as? [String] ?? []
    }

    static let indexSource = """
        ---
        peep: { wikilinks: true }
        ---
        # Index

        [[Page Name#Second Part]], [[Nested]], [[Missing Page]].
        """

    @Test("found pages link to their files; clicking opens them through the link policy")
    func clickOpens() async throws {
        defer { closeAll() }
        try write("# Page\n\n## Second Part\n", to: "Page-Name.md")
        try write("# Nested\n", to: "sub/folder/nested.md")
        let (_, controller) = try await open(Self.indexSource)
        #expect(try await hrefs(in: controller) == ["Page-Name.md#second-part", "sub/folder/nested.md", ""])

        var actions: [LinkAction] = []
        controller.coordinator.linkHandler = { action, _ in actions.append(action) }
        let pageURL = controller.coordinator.webView.url
        try await click("Page Name#Second Part", in: controller)
        try await click("Nested", in: controller)
        let folder = try realFolder
        #expect(
            actions == [
                .openDocument(folder.appending(path: "Page-Name.md"), fragment: "second-part"),
                .openDocument(folder.appending(path: "sub/folder/nested.md"), fragment: nil),
            ])
        #expect(controller.coordinator.webView.url == pageURL)
    }

    @Test("a missing page has no href: clicking it does nothing and the page stays")
    func missingIsInert() async throws {
        defer { closeAll() }
        let (_, controller) = try await open(Self.indexSource)
        let missing = try await evaluate(
            "return [...document.querySelectorAll('a.wikilink-missing')].map((a) => a.textContent);", in: controller)
        #expect(missing as? [String] == ["Page Name#Second Part", "Nested", "Missing Page"])
        let anyHref = try await evaluate(
            "return [...document.querySelectorAll('a.wikilink-missing')].some((a) => a.hasAttribute('href'));",
            in: controller)
        #expect(anyHref as? Bool == false)

        var actions: [LinkAction] = []
        controller.coordinator.linkHandler = { action, _ in actions.append(action) }
        let pageURL = controller.coordinator.webView.url
        try await click("Missing Page", in: controller)
        #expect(actions.isEmpty)
        #expect(controller.coordinator.webView.url == pageURL)
        #expect(controller.coordinator.hasLoadedPage)
    }

    @Test("resolved at render time: a page created later links on the next render")
    func resolvedAtRenderTime() async throws {
        defer { closeAll() }
        let (document, controller) = try await open(Self.indexSource)
        #expect(try await hrefs(in: controller).first?.isEmpty == true)
        try write("# Page\n", to: "Page-Name.md")
        let source = try #require(document.content?.source)
        document.render(source + "\n\nMore.", of: try #require(document.fileURL))
        try await until("the re-render") { try await hrefs(in: controller).first == "Page-Name.md#second-part" }
    }

    @Test("off by default; Settings turns them on in place; frontmatter beats Settings")
    func settingsAndFrontmatter() async throws {
        defer { closeAll() }
        try write("# Page\n", to: "Page-Name.md")
        let store = MarkdownSettings(defaults: defaults, isPersistent: true)
        let (_, plain) = try await open("[[Page Name]]", name: "plain.md", markdownSettings: store)
        #expect(try await hrefs(in: plain).isEmpty)
        let off = "---\npeep: { wikilinks: false }\n---\n[[Page Name]]"
        let (_, optedOut) = try await open(off, name: "opted-out.md", markdownSettings: store)

        store.builtInPreprocessors = [.wikiLinks]
        try await until("wiki links on") { try await hrefs(in: plain) == ["Page-Name.md"] }
        #expect(try await hrefs(in: optedOut).isEmpty)
    }

    @Test("Copy as HTML copies the same relative wiki links")
    func copyAsHTML() async throws {
        defer { closeAll() }
        try write("# Page\n", to: "Page-Name.md")
        let (_, controller) = try await open(Self.indexSource)
        await controller.writeHTML(to: pasteboard)
        let html = try #require(pasteboard.string(forType: .html))
        #expect(html.contains(#"<a class="wikilink" href="Page-Name.md#second-part">"#))
        #expect(html.contains(#"<a class="wikilink wikilink-missing">Missing Page</a>"#))
        #expect(!html.contains("peep-doc:"))
    }

    @Test("the search stays in the allowed root and skips symbolic links")
    func scope() async throws {
        defer { closeAll() }
        let outside = FileManager.default.temporaryDirectory.appending(path: "peep-wiki-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("# Outside\n".utf8).write(to: outside.appending(path: "Outside.md"))
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "Alias.md"), withDestinationURL: outside.appending(path: "Outside.md"))
        let (_, controller) = try await open("---\npeep: { wikilinks: true }\n---\n[[Outside]] [[Alias]]")
        #expect(try await hrefs(in: controller) == ["", ""])
    }
}

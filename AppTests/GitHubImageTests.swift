import AppKit
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// Hosted `WKWebView` tests for GitHub's image conventions: root-relative URLs resolve against
/// the repository (`RootRelativeURL`), and `#gh-dark-mode-only` / `#gh-light-mode-only` images
/// and `<picture>` sources follow the web view's appearance live (`DefaultTheme`).
@MainActor
@Suite("GitHub image conventions", .serialized, .timeLimit(.minutes(1)))
struct GitHubImageTests {
    let coordinator = WebViewCoordinator()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)
    /// `repo/` is a git work tree; `plain/` is not; `outside/` sits next to both.
    let folder: URL

    init() throws {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        let base = FileManager.default.temporaryDirectory.appending(path: "mdv-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let real = try #require(realpath(base.path(percentEncoded: false), nil))
        defer { free(real) }
        folder = URL(filePath: String(cString: real), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "repo/.git"), withIntermediateDirectories: true)
    }

    func write(_ relative: String, _ data: Data) throws {
        let url = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func png(width: Int) throws -> Data {
        try LocalResourceSchemeHandlerTests.raster(.png, width: width, height: 4)
    }

    /// Writes `source` at `relative` and loads it as a document window does (content rendered
    /// with the document's link root, page at its `mdv-doc` URL).
    func loadDocument(_ source: String, at relative: String = "repo/docs/guide/README.md") async throws {
        let fileURL = folder.appending(path: relative)
        try write(relative, Data(source.utf8))
        let content = try DocumentContent(
            data: Data(contentsOf: fileURL), fallbackTitle: "README.md",
            linkRoot: DocumentContent.linkRoot(forDocumentAt: fileURL))
        coordinator.documentFileURL = fileURL
        let baseURL = try #require(coordinator.documentURL(forFileAt: fileURL))
        try await coordinator.load(content.page, baseURL: baseURL)
    }

    func evaluate(_ body: String) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    /// Each `<img>`'s alt text and natural width once it has loaded or failed (0 = broken).
    func imageWidths() async throws -> [String: Int] {
        let result = try await evaluate(
            """
            const images = Array.from(document.images);
            await Promise.all(images.map((img) => img.decode().catch(() => null)));
            return Object.fromEntries(images.map((img) => [img.alt, img.naturalWidth]));
            """)
        return try #require(result as? [String: NSNumber]).mapValues(\.intValue)
    }

    /// Whether each image (by alt) and placeholder (by its alt span) is displayed.
    func displayed() async throws -> [String: Bool] {
        let result = try await evaluate(
            """
            const shown = (element) => getComputedStyle(element).display !== "none";
            const entries = Array.from(document.images).map((img) => [img.alt, shown(img)]);
            for (const placeholder of document.querySelectorAll(".remote-image")) {
              entries.push([placeholder.querySelector(".remote-image-alt").textContent, shown(placeholder)]);
            }
            return Object.fromEntries(entries);
            """)
        return try #require(result as? [String: Bool])
    }

    func setAppearance(_ name: NSAppearance.Name) throws {
        coordinator.webView.appearance = try #require(NSAppearance(named: name))
    }

    /// Polls `condition` for up to two seconds (appearance changes reach the page asynchronously).
    func eventually(_ condition: () async throws -> Bool) async throws -> Bool {
        for _ in 0..<40 {
            if try await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await condition()
    }

    // MARK: Root-relative URLs

    @Test("root-relative images in Markdown, raw HTML, and picture sources resolve against the repository")
    func rootRelativeImages() async throws {
        try write("repo/docs/assets/a.png", try png(width: 21))
        try write("repo/docs/assets/b.png", try png(width: 22))
        try write("repo/top.png", try png(width: 23))
        try write("repo/docs/guide/rel.png", try png(width: 24))
        try write("outside/secret.png", try png(width: 25))
        try await loadDocument(
            """
            ![md](/docs/assets/a.png) ![clamped](/../../docs/assets/a.png) ![dots](/docs/./x/../assets/a.png)
            ![top](/top.png "Title") ![rel](rel.png) ![escape](/../../outside/secret.png)
            ![encoded](/%2e%2e/outside/secret.png) ![slash](/docs%2fassets/a.png)

            <img alt="raw" src="/docs/assets/b.png"> <img alt="raw-entity" src="&#x2f;top.png">
            """)
        let widths = try await imageWidths()
        #expect(
            widths == [
                "md": 21, "clamped": 21, "dots": 21, "top": 23, "rel": 24, "escape": 0, "encoded": 0, "slash": 0,
                "raw": 22, "raw-entity": 23,
            ])
    }

    @Test("without a git repository, root-relative URLs resolve against the document's folder")
    func rootRelativeWithoutRepository() async throws {
        try write("plain/notes/img/a.png", try png(width: 31))
        try write("plain/b.png", try png(width: 32))
        try await loadDocument("![in](/img/a.png) ![above](/../b.png)", at: "plain/notes/README.md")
        #expect(try await imageWidths() == ["in": 31, "above": 0])
    }

    @Test("root-relative links resolve against the repository, like images")
    func rootRelativeLinks() async throws {
        try write("repo/docs/other.md", Data("# Other".utf8))
        try await loadDocument(
            "[doc](/docs/other.md#intro) [up](/../../docs/other.md) [root](/) [web](//example.com/x)")
        let hrefs = try #require(
            try await evaluate("return Array.from(document.links).map((a) => a.href);") as? [String])
        let actions = try hrefs.map {
            try LinkPolicy.action(for: #require(URL(string: $0)), in: coordinator.linkContext)
        }
        let other = folder.appending(path: "repo/docs/other.md")
        #expect(actions[0] == .openDocument(other, fragment: "intro"))
        #expect(actions[1] == .openDocument(other, fragment: nil))
        #expect(
            actions[2]
                == .revealInFinder(URL(filePath: folder.appending(path: "repo").path(), directoryHint: .isDirectory)))
        #expect(hrefs[3] == "mdv-doc://example.com/x", "scheme-relative links are untouched")
    }

    // MARK: Light and dark images

    @Test("#gh-dark-mode-only and #gh-light-mode-only images and placeholders follow the appearance")
    func colorModeImages() async throws {
        try write("repo/docs/guide/light.png", try png(width: 41))
        try write("repo/docs/guide/dark.png", try png(width: 42))
        try setAppearance(.aqua)
        try await loadDocument(
            """
            ![light](light.png#gh-light-mode-only) ![dark](dark.png#gh-dark-mode-only)
            ![root](/docs/guide/dark.png#gh-dark-mode-only)
            <img alt="raw-dark" src="dark.png#gh-dark-mode-only">
            ![remote-light](https://example.invalid/l.png#gh-light-mode-only)
            ![remote-dark](https://example.invalid/d.png#gh-dark-mode-only)
            """)
        // The fragment doesn't stop the scheme handler from serving the image.
        #expect(try await imageWidths() == ["light": 41, "dark": 42, "root": 42, "raw-dark": 42])
        let light = [
            "light": true, "dark": false, "root": false, "raw-dark": false, "remote-light": true, "remote-dark": false,
        ]
        let dark = light.mapValues { !$0 }
        #expect(try await displayed() == light)

        try setAppearance(.darkAqua)
        #expect(try await eventually { try await displayed() == dark }, "dark mode shows only the dark variants")
        try setAppearance(.aqua)
        #expect(try await eventually { try await displayed() == light }, "and back")
    }

    @Test("GitHub's <picture> with a prefers-color-scheme source switches with the appearance")
    func pictureSource() async throws {
        try write("repo/docs/assets/light.png", try png(width: 51))
        try write("repo/docs/assets/dark.png", try png(width: 52))
        try setAppearance(.aqua)
        try await loadDocument(
            """
            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="/docs/assets/dark.png">
              <source media="(prefers-color-scheme: light)" srcset="../assets/light.png">
              <img alt="logo" src="/docs/assets/light.png">
            </picture>
            """)
        func current() async throws -> String {
            let source = try await evaluate(
                """
                const img = document.querySelector("img");
                await img.decode().catch(() => null);
                return img.naturalWidth + " " + img.currentSrc.split("/").pop();
                """)
            return try #require(source as? String)
        }
        #expect(try await current() == "51 light.png")
        try setAppearance(.darkAqua)
        #expect(try await eventually { try await current() == "52 dark.png" })
        try setAppearance(.aqua)
        #expect(try await eventually { try await current() == "51 light.png" })
    }
}

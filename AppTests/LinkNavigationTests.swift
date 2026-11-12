import AppKit
import Foundation
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Hosted tests for link clicks and hover (#19): clicks are driven from the app world with
/// `element.click()`, which WebKit reports as a `.linkActivated` navigation.
@MainActor
@Suite("Link navigation", .serialized, .timeLimit(.minutes(1)))
final class LinkNavigationTests {
    static let filler = (1...120).map { "Filler paragraph \($0)." }.joined(separator: "\n\n")

    let coordinator = WebViewCoordinator()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)
    /// The document's folder, as a real path (`/private/var/...`), like the scheme handler maps.
    let folder: URL
    let documentFile: URL
    var actions: [(LinkAction, LinkOpening)] = []

    init() throws {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        let base = FileManager.default.temporaryDirectory.appending(path: "peep-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let real = try #require(realpath(base.path(percentEncoded: false), nil))
        defer { free(real) }
        folder = URL(filePath: String(cString: real), directoryHint: .isDirectory)
        documentFile = folder.appending(path: "README.md")
        coordinator.linkHandler = { [weak self] action, opening in
            self?.actions.append((action, opening))
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func load(_ source: String) async throws {
        try Data(source.utf8).write(to: documentFile)
        coordinator.documentFileURL = documentFile
        let page = DocumentContent(source: source, fallbackTitle: "README.md").page
        try await coordinator.load(page, baseURL: coordinator.documentURL(forFileAt: documentFile))
    }

    @discardableResult
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    /// Clicks the first link whose `href` attribute is `href`, then lets the policy run.
    func click(href: String) async throws {
        let clicked = try await evaluate(
            """
            const link = [...document.querySelectorAll("a")].find((a) => a.getAttribute("href") === href);
            if (link === undefined) { return false; }
            link.click();
            await new Promise((resolve) => setTimeout(resolve, 100));
            return true;
            """, arguments: ["href": href])
        #expect(clicked as? Bool == true, "no link with href \(href)")
    }

    func scrollY() async throws -> Double {
        try #require(try await evaluate("return window.scrollY;") as? NSNumber).doubleValue
    }

    /// Waits for `condition`, polling (scrolls run in a task after the click).
    func eventually(_ condition: () async throws -> Bool) async throws -> Bool {
        for _ in 0..<50 {
            if try await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test("a heading link scrolls in place without navigating")
    func headingLink() async throws {
        try await load("[Go](#target)\n\n" + Self.filler + "\n\n## Target\n")
        let pageURL = coordinator.webView.url
        try await click(href: "#target")
        #expect(try await eventually { try await scrollY() > 0 })
        #expect(coordinator.webView.url == pageURL)
        #expect(actions.isEmpty)
    }

    @Test("a fragment for a raw HTML id falls back to user-content-")
    func userContentLink() async throws {
        try await load("[Go](#raw)\n\n" + Self.filler + "\n\n<div id=\"raw\">raw</div>\n")
        try await click(href: "#raw")
        #expect(try await eventually { try await scrollY() > 0 })
    }

    @Test("a raw HTML heading's anchor is a link target")
    func rawHeadingLink() async throws {
        try await load("[Go](#raw-heading)\n\n" + Self.filler + "\n\n<h2>Raw heading</h2>\n")
        try await click(href: "#raw-heading")
        #expect(try await eventually { try await scrollY() > 0 })
    }

    @Test("a missing fragment shows a message and doesn't scroll")
    func missingFragment() async throws {
        try await load("[Go](#nowhere)\n\n" + Self.filler)
        try await click(href: "#nowhere")
        #expect(try await eventually { coordinator.linkStatus.message != nil })
        #expect(try await scrollY() == 0)
    }

    @Test("a relative Markdown link goes to the handler as openDocument, with its fragment")
    func markdownLink() async throws {
        try await load("[Other](docs/other.md#setup)")
        let pageURL = coordinator.webView.url
        try await click(href: "docs/other.md#setup")
        #expect(actions.count == 1)
        #expect(actions.first?.0 == .openDocument(folder.appending(path: "docs/other.md"), fragment: "setup"))
        #expect(actions.first?.1 == .normal)
        #expect(coordinator.webView.url == pageURL)
    }

    @Test("a folder link goes to the handler as revealInFinder")
    func folderLink() async throws {
        try await load("[Docs](docs/)")
        try await click(href: "docs/")
        let target = folder.appending(path: "docs", directoryHint: .isDirectory)
        #expect(actions.first?.0 == .revealInFinder(target))
        guard case .revealInFinder(let url) = actions.first?.0 else {
            Issue.record("expected revealInFinder, got \(actions)")
            return
        }
        #expect(url.hasDirectoryPath)
    }

    @Test("an external link goes to the handler and doesn't navigate the view")
    func externalLink() async throws {
        try await load("[Site](https://example.com/page)")
        let pageURL = coordinator.webView.url
        try await click(href: "https://example.com/page")
        #expect(actions.first?.0 == .openExternal(try #require(URL(string: "https://example.com/page"))))
        #expect(coordinator.webView.url == pageURL)
    }

    @Test("links cmark's safe mode blanks are blocked")
    func blankLink() async throws {
        try await load("[secret](file:///etc/passwd) [js](javascript:alert(1))")
        try await click(href: "")
        guard case .blocked = actions.first?.0 else {
            Issue.record("expected a blocked action, got \(actions)")
            return
        }
    }

    @Test("hovering a link shows where it goes; leaving clears it")
    func hover() async throws {
        try await load("[Other](other.md) and [Site](https://example.com/x)")
        let expected = (folder.appending(path: "other.md").path(percentEncoded: false) as NSString)
            .abbreviatingWithTildeInPath
        try await evaluate(
            """
            const link = document.querySelector("a[href='other.md']");
            link.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
            return true;
            """)
        #expect(try await eventually { coordinator.linkStatus.hoverText == expected })
        try await evaluate(
            """
            document.body.dispatchEvent(new MouseEvent("mouseout", { bubbles: true, relatedTarget: null }));
            return true;
            """)
        #expect(try await eventually { coordinator.linkStatus.hoverText == nil })
    }

    @Test("the hover message handler is invisible to the page world")
    func handlerNotInPageWorld() async throws {
        try await load("text")
        let pageWorld = try await coordinator.webView.callAsyncJavaScript(
            "return typeof globalThis.webkit?.messageHandlers?.linkHover;", arguments: [:], in: nil,
            contentWorld: .page)
        #expect(pageWorld as? String == "undefined")
        #expect(
            try await evaluate("return typeof globalThis.webkit?.messageHandlers?.linkHover;") as? String
                == "object")
    }

    @Test("cmd-click and middle-click open in a new tab")
    func opening() {
        #expect(LinkOpening(modifiers: [], buttonNumber: 0) == .normal)
        #expect(LinkOpening(modifiers: [.command], buttonNumber: 0) == .newTab)
        #expect(LinkOpening(modifiers: [], buttonNumber: 2) == .newTab)
        #expect(LinkOpening(modifiers: [.shift], buttonNumber: 0) == .normal)
    }

    @Test("LinkPolicy's Markdown extensions match the app's declared Markdown types")
    func declaredExtensions() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let declarations = try ["UTImportedTypeDeclarations", "UTExportedTypeDeclarations"].flatMap { key in
            try #require(info[key] as? [[String: Any]])
        }
        let identifiers = Set(MarkdownContentTypes.all.map(\.identifier))
        let markdown = declarations.filter { identifiers.contains($0["UTTypeIdentifier"] as? String ?? "") }
        #expect(markdown.count == identifiers.count)
        let extensions = try markdown.flatMap { declaration in
            let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])
            return try #require(tags["public.filename-extension"] as? [String])
        }
        #expect(Set(extensions) == LinkPolicy.markdownExtensions)
    }
}

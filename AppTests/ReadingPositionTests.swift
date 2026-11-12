import AppKit
import Testing
import WebKit

@testable import PeepApp

/// The live-reload position mapping in `DocumentBridge.js` (`readingPosition`,
/// `restorePosition`, `updateContent`), in a hosted `WKWebView`.
@MainActor
@Suite("Reading position", .serialized, .timeLimit(.minutes(1)))
struct ReadingPositionTests {
    /// 200 one-line paragraphs: paragraph N is on line 2N - 1.
    static let longSource = (1...200).map { "Paragraph \($0)." }.joined(separator: "\n\n")

    let coordinator = WebViewCoordinator()
    /// Offscreen, never shown: gives the page an 800x600 viewport.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
    }

    static func page(_ source: String) -> RenderedPage {
        DocumentContent(source: source, fallbackTitle: "test.md").page
    }

    func load(_ source: String) async throws {
        try await coordinator.load(Self.page(source), baseURL: nil)
    }

    func update(_ source: String) async throws {
        try await coordinator.updateContent(with: Self.page(source), baseURL: nil)
    }

    @discardableResult
    func evaluate(_ body: String) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    func number(_ body: String) async throws -> Double {
        try #require(try await evaluate(body) as? NSNumber).doubleValue
    }

    func scrollY() async throws -> Double { try await number("return window.scrollY;") }

    func maximumScrollY() async throws -> Double {
        try await number("return document.documentElement.scrollHeight - window.innerHeight;")
    }

    func scrollToBottom() async throws {
        try await evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return true;")
    }

    // MARK: Line-based restore

    @Test("keeps the top source line when content above it changes height")
    func contentAboveGrows() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 101)
        let before = try await scrollY()
        // Paragraph 5 becomes much taller but stays on one source line.
        let longLine = String(repeating: "Longer paragraph five. ", count: 200)
        try await update(Self.longSource.replacingOccurrences(of: "Paragraph 5.", with: longLine))
        #expect(try await scrollY() > before + 100, "the pixel offset had to change")
        let line = try await coordinator.currentSourceLine()
        #expect(abs(line - 101) < 0.05, "top line \(line)")
    }

    @Test("lands on the closest block at or before the line, plus the offset into it")
    func blockMerged() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 101)
        // Paragraphs 50 and 51 (lines 99 and 101) become one paragraph spanning lines 99-101.
        let merged = Self.longSource.replacingOccurrences(
            of: "Paragraph 50.\n\nParagraph 51.", with: "Paragraph 50.\ncontinued\nParagraph 51 joined.")
        try await update(merged)
        let top = try await evaluate(
            """
            // The last block whose top is at or above the top of the viewport.
            const above = [...document.querySelectorAll("[data-source-line]")].filter(
              (element) => element.getBoundingClientRect().top <= 1);
            return above.at(-1)?.getAttribute("data-source-line") ?? null;
            """)
        #expect(top as? String == "99")
        let line = try await coordinator.currentSourceLine()
        #expect(line > 99 && line < 103, "top line \(line)")
    }

    @Test("a fractional position inside a block survives an update")
    func fractional() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 120.5)
        try await update(Self.longSource + "\n\nAppended.")
        let line = try await coordinator.currentSourceLine()
        #expect(abs(line - 120.5) < 0.05, "top line \(line)")
    }

    @Test("the top of the page stays the top")
    func top() async throws {
        try await load(Self.longSource)
        try await update("# Inserted\n\n" + Self.longSource)
        #expect(try await scrollY() == 0)
    }

    // MARK: Bottom

    @Test("at the bottom, an update that adds content stays at the bottom")
    func bottomSticks() async throws {
        try await load(Self.longSource)
        try await scrollToBottom()
        #expect(try await coordinator.readingPosition().atBottom)
        try await update(Self.longSource + "\n\nNew last paragraph.\n\nAnd another.")
        let maximum = try await maximumScrollY()
        #expect(abs(try await scrollY() - maximum) < 1)
        #expect(try await coordinator.readingPosition().atBottom)
    }

    @Test("near but not at the bottom keeps the line instead")
    func nearBottom() async throws {
        try await load(Self.longSource)
        try await scrollToBottom()
        try await evaluate("window.scrollBy(0, -200); return true;")
        let position = try await coordinator.readingPosition()
        #expect(!position.atBottom)
        try await update(Self.longSource + "\n\nNew last paragraph.\n\nAnd another.")
        let line = try await coordinator.currentSourceLine()
        #expect(abs(line - position.line) < 0.05)
    }

    @Test("a page that fits the window doesn't stick to the bottom as it grows")
    func shortPageGrows() async throws {
        try await load("# Short\n\nOne paragraph.")
        #expect(try await coordinator.readingPosition().atBottom == false)
        try await update("# Short\n\nOne paragraph.\n\n" + Self.longSource)
        #expect(try await scrollY() == 0)
    }

    // MARK: Reload and restore

    @Test("readingPosition and restore round-trip across a full load")
    func reloadAndRestore() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 151)
        let position = try await coordinator.readingPosition()
        try await load("# Title\n\n" + Self.longSource)
        #expect(try await scrollY() == 0)
        try await coordinator.restore(position)
        #expect(abs(try await coordinator.currentSourceLine() - 151) < 0.05)
    }

    @Test("updateContent loads the page when nothing is loaded yet")
    func updateLoads() async throws {
        try await update("# Fresh")
        #expect(coordinator.hasLoadedPage)
        #expect(try await evaluate("return document.title;") as? String == "Fresh")
    }

    @Test("updateContent swaps the body and title in place")
    func swapsInPlace() async throws {
        try await load("text")
        try await evaluate("document.body.dataset.loaded = 'once'; return true;")
        try await update("# New title\n\nnew text")
        #expect(try await evaluate("return document.title;") as? String == "New title")
        #expect(try await evaluate("return document.body.dataset.loaded;") as? String == "once")
    }
}

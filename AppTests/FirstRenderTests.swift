import AppKit
import Foundation
import Testing

@testable import MdvApp

/// The first open renders off the main actor (#32): the window appears before the page is
/// rendered, the main thread keeps running while a large document renders, and a render that
/// something newer overtakes is dropped.
@MainActor
@Suite("First render off main", .serialized, .timeLimit(.minutes(2)))
struct FirstRenderTests {
    static let markdownType = "net.daringfireball.markdown"

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-first-render-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ source: String, to name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(source.utf8).write(to: url)
        return url
    }

    func until(
        _ what: String, timeout: Duration = .seconds(30), _ condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// About `bytes` of varied Markdown (headings, paragraphs with inline markup, lists, code,
    /// tables, block quotes), the shape of a large real document: a heading about every 2.5 KB.
    /// Section N's heading is "Section N".
    nonisolated static func largeSource(bytes: Int) -> String {
        var source = "# Large Document\n\n"
        var section = 0
        while source.utf8.count < bytes {
            section += 1
            source += "## Section \(section)\n\n"
            for _ in 0..<4 {
                source += sectionBody(section)
            }
        }
        return source
    }

    nonisolated private static func sectionBody(_ section: Int) -> String {
        """
        Paragraph with *emphasis*, **strong**, `code`, a [link](https://example.com/\(section)), \
        and a footnote-like reference. Lorem ipsum dolor sit amet, consectetur adipiscing elit, \
        sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

        - item one of \(section)
        - item two with `inline`
          1. nested ordered
          2. another

        ```swift
        let value\(section) = [1, 2, 3].map { $0 * \(section) }
        ```

        | Column A | Column B | Column C |
        | -------- | :------: | -------: |
        | a\(section) | b | c |
        | d | e | f |

        > A block quote in section \(section).


        """
    }

    // MARK: Opening

    @Test("the window is up before the render finishes; the render then fills it")
    func windowBeforeRender() async throws {
        let url = try write(Self.largeSource(bytes: 1_000_000), to: "large.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        defer { document.close() }
        #expect(document.content == nil, "reading doesn't render")
        #expect(document.pendingRender != nil)
        document.makeWindowControllers()
        document.showWindows()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        #expect(controller.window?.isVisible == true)
        #expect(controller.window?.title == "large.md", "the file name until the render names it")
        #expect(!controller.coordinator.webView.isOpaque, "the theme background shows, not a blank page")

        await document.pendingRender?.value
        #expect(document.content?.page.title == "Large Document")
        #expect(controller.window?.title == "Large Document")
        try await until("the page") { controller.coordinator.hasLoadedPage }
    }

    /// Opens a 5 MB document while a hang detector runs on the main actor. Reading and decoding
    /// (on main) and the whole render (off main) must each fit in one frame of main-thread time,
    /// with the outline sidebar shown or hidden.
    ///
    /// The sidebar's first fill (row views and layout, AppKit's, about 15-20 ms whatever the
    /// heading count) used to run when the render landed, before the page load (#32, #45); it
    /// now runs after the first page has painted (#58), so it is in neither measurement.
    @Test(
        "opening a 5 MB document never blocks the main thread for more than a frame",
        arguments: [false, true])
    func mainThreadStaysResponsive(outlineVisible: Bool) async throws {
        let url = try write(Self.largeSource(bytes: 5_000_000), to: "five.md")
        let throwawayDefaults = try ThrowawayDefaults("mdv-first-render")
        let defaults = throwawayDefaults.defaults
        let outlinePreference = OutlinePreference(defaults: defaults, isPersistent: true)
        outlinePreference.showsOutlineInNewWindows = outlineVisible

        // A window for a small document first, so the measurement is the open path, not the
        // first web view and window the test process ever creates.
        let warmUp = try MarkdownDocument(contentsOf: try write("# Warm", to: "warm.md"), ofType: Self.markdownType)
        let warmController = DocumentWindowController(outlinePreference: outlinePreference)
        warmUp.addWindowController(warmController)
        warmUp.showWindows()
        defer { warmUp.close() }
        try await until("the warm-up page") { warmController.coordinator.hasLoadedPage }

        let heartbeat = MainThreadHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        try await Task.sleep(for: .milliseconds(50))
        let readStart = ContinuousClock.now
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let readTime = ContinuousClock.now - readStart
        defer { document.close() }
        let windowStart = ContinuousClock.now
        let controller = DocumentWindowController(outlinePreference: outlinePreference)
        document.addWindowController(controller)
        document.showWindows()
        let windowTime = ContinuousClock.now - windowStart
        // Let the new window lay out and draw its first frames (window building is #40's), then
        // measure the rest of the render, which is still running.
        try await Task.sleep(for: .milliseconds(100))
        try #require(document.content == nil, "the render outlasted the window's first frames")
        let renderStart = ContinuousClock.now
        heartbeat.reset()
        await document.pendingRender?.value
        let renderTime = ContinuousClock.now - renderStart
        let longestGapWhileRendering = heartbeat.longestGap
        let longestBusyWhileRendering = heartbeat.longestBusyGap
        heartbeat.reset()
        try await until("the page") { controller.coordinator.hasLoadedPage }
        // For the record (#40 tracks the open path): the numbers in this test's output.
        print(
            "FirstRenderTests 5 MB, outline \(outlineVisible ? "shown" : "hidden"): read+decode \(readTime), "
                + "window \(windowTime), rest of the render \(renderTime) off main, longest main-thread gap "
                + "while rendering \(longestGapWhileRendering) (busy \(longestBusyWhileRendering)), "
                + "while loading the page \(heartbeat.longestGap) (busy \(heartbeat.longestBusyGap))")

        #expect(document.content?.page.headings.isEmpty == false)
        // One frame at 60 Hz.
        expectTiming(readTime < .milliseconds(17), "read+decode took \(readTime)")
        // Main-thread CPU time between heartbeats, not wall time: on a loaded machine (parallel
        // builds, CI) the main thread also waits to be scheduled, which isn't a stall we caused
        // (wall-clock gaps of 21-44 ms were seen that way while the busy time stayed under 5 ms).
        let bound: Duration = .milliseconds(17)
        expectTiming(longestBusyWhileRendering < bound, "main thread busy for \(longestBusyWhileRendering) at once")
        // A main thread waiting for the render (a lock, a synchronous hop) uses no CPU; it would
        // wait for most of the render, far over this bound.
        expectTiming(longestGapWhileRendering < .milliseconds(250), "main thread stalled \(longestGapWhileRendering)")
        expectTiming(renderTime > longestGapWhileRendering * 4, "the render ran while the main thread kept going")
    }

    // MARK: Preparing the web view

    @Test(
        "the preparation load never stands in for the page, started right after or once it finished",
        arguments: [false, true], [false, true])
    func preparationThenLoad(waitForPreparation: Bool, withBaseURL: Bool) async throws {
        let coordinator = WebViewCoordinator()
        coordinator.prepareForFirstLoad()
        #expect(!coordinator.hasLoadedPage)
        #expect(!coordinator.webView.isOpaque)
        if waitForPreparation {
            try await until("the preparation load") { !coordinator.webView.isLoading }
            #expect(coordinator.expectedLoadURL == nil, "the navigation policy allowed the preparation load")
            #expect(WebViewCoordinator.isPreparationURL(coordinator.webView.url))
        }
        // A page without a base URL loads at about:blank, which the preparation URL must not match.
        let baseURL = withBaseURL ? coordinator.documentURL(forFileAt: try write("# Page", to: "page.md")) : nil
        let page = DocumentContent(source: "# Page", fallbackTitle: "page.md").page
        try await coordinator.load(page, baseURL: baseURL)
        #expect(coordinator.hasLoadedPage)
        let title =
            try await coordinator.webView.callAsyncJavaScript(
                "return document.title;", arguments: [:], in: nil, contentWorld: AppScripts.world) as? String
        #expect(title == "Page")
    }

    @Test("a window for a document that is still rendering prepares its web view; a rendered one doesn't")
    func windowPreparesWebView() async throws {
        let url = try write(Self.largeSource(bytes: 500_000), to: "prepare.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        defer { document.close() }
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? DocumentWindowController)
        #expect(WebViewCoordinator.isPreparationURL(controller.coordinator.webView.url))
        try await until("the page") { controller.coordinator.hasLoadedPage }
        #expect(controller.coordinator.webView.url?.scheme == "mdv-doc")

        let second = DocumentWindowController()
        document.addWindowController(second)
        #expect(!WebViewCoordinator.isPreparationURL(second.coordinator.webView.url))
        try await until("the second window's page") { second.coordinator.hasLoadedPage }
    }

    // MARK: Stale renders

    @Test("content set while a render is in flight wins over the older render")
    func newerContentWins() async throws {
        let url = try write(Self.largeSource(bytes: 500_000), to: "stale.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let render = try #require(document.pendingRender)
        document.setContent(DocumentContent(source: "# Newer", fallbackTitle: "stale.md"))
        await render.value
        #expect(document.content?.source == "# Newer")
    }

    @Test("a revert during the first render ends on the reverted file")
    func revertDuringRender() async throws {
        let url = try write(Self.largeSource(bytes: 1_000_000), to: "revert.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let first = try #require(document.pendingRender)
        try Data("# Reverted".utf8).write(to: url)
        try document.revert(toContentsOf: url, ofType: Self.markdownType)
        await first.value
        await document.pendingRender?.value
        #expect(document.content?.source == "# Reverted")
    }

    @Test("closing a document drops its render")
    func closeDropsRender() async throws {
        let url = try write(Self.largeSource(bytes: 500_000), to: "closed.md")
        let document = try MarkdownDocument(contentsOf: url, ofType: Self.markdownType)
        let render = try #require(document.pendingRender)
        document.close()
        #expect(document.pendingRender == nil)
        await render.value
        #expect(document.content == nil)
    }

    @Test("unreadable and non-UTF-8 files still fail the open itself")
    func readErrors() throws {
        #expect(throws: CocoaError.self) {
            try MarkdownDocument(contentsOf: folder.appending(path: "missing.md"), ofType: Self.markdownType)
        }
        let bad = folder.appending(path: "latin1.md")
        try Data([0x23, 0x20, 0xE9, 0x0A]).write(to: bad)
        #expect(throws: CocoaError(.fileReadInapplicableStringEncoding)) {
            try MarkdownDocument(contentsOf: bad, ofType: Self.markdownType)
        }
    }
}

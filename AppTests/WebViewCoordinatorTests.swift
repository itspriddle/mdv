import AppKit
import PeepCore
import Testing
import WebKit

@testable import PeepApp

/// Hosted `WKWebView` tests for the coordinator, the app-script bridge, and the script policy.
@MainActor
@Suite("WebViewCoordinator", .serialized, .timeLimit(.minutes(1)))
struct WebViewCoordinatorTests {
    /// 200 one-line paragraphs: paragraph N is on line 2N - 1.
    static let longSource = (1...200).map { "Paragraph \($0)." }.joined(separator: "\n\n")

    let coordinator = WebViewCoordinator()
    /// Offscreen, never shown: gives the page a viewport to lay out in.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
    }

    func load(_ source: String) async throws {
        try await coordinator.load(DocumentContent(source: source, fallbackTitle: "test.md").page, baseURL: nil)
    }

    @discardableResult
    func evaluate(_ body: String, in world: WKContentWorld = AppScripts.world) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: world)
    }

    func scrollY() async throws -> Double {
        try #require(try await evaluate("return window.scrollY;") as? NSNumber).doubleValue
    }

    // MARK: Loading

    @Test("the web view is transparent, before and after the first page loads")
    func transparentAroundLoad() async throws {
        #expect(!coordinator.webView.isOpaque, "the window's theme background shows, not WebKit's white")
        #expect(!coordinator.hasLoadedPage)
        try await load("# Hello")
        #expect(!coordinator.webView.isOpaque)
        #expect(!coordinator.webView.isHidden)
        #expect(coordinator.hasLoadedPage)
        #expect(try await evaluate("return document.title;") as? String == "Hello")
    }

    @Test("loads with the document folder as the base URL")
    func baseURL() async throws {
        let folder = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        try await coordinator.load(DocumentContent(source: "text", fallbackTitle: "a.md").page, baseURL: folder)
        #expect(coordinator.webView.url == folder)
    }

    @Test("bridge calls before the first load fail cleanly")
    func bridgeBeforeLoad() async {
        await #expect(throws: WebViewCoordinator.BridgeError.noPage) {
            try await coordinator.currentSourceLine()
        }
    }

    // MARK: Scrolling and position

    @Test("reports line 1 at the top of the page")
    func topOfPage() async throws {
        try await load(Self.longSource)
        #expect(try await coordinator.currentSourceLine() == 1)
    }

    @Test("scrolls to a source line and reads the same line back", arguments: [41.0, 199.0, 120.5])
    func roundTrip(line: Double) async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: line)
        #expect(try await scrollY() > 0)
        let current = try await coordinator.currentSourceLine()
        #expect(abs(current - line) < 0.05, "scrolled to \(line), read back \(current)")
    }

    @Test("line 1 and earlier scroll to the top")
    func scrollToTop() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 99)
        try await coordinator.scroll(toSourceLine: 1)
        #expect(try await scrollY() == 0)
    }

    @Test("ignores footnote items whose lines go back")
    func footnotes() async throws {
        let source = "Text[^1].\n\n[^1]: Early note.\n\n" + Self.longSource
        try await load(source)
        try await coordinator.scroll(toSourceLine: 100)
        let current = try await coordinator.currentSourceLine()
        #expect(abs(current - 100) < 0.05)
    }

    @Test("scrolls to a heading by fragment")
    func fragment() async throws {
        try await load(Self.longSource + "\n\n## Target heading\n\nend")
        #expect(try await coordinator.scroll(toFragment: "target-heading"))
        #expect(try await scrollY() > 0)
    }

    @Test("falls back to the user-content- id that raw HTML gets")
    func userContentFragment() async throws {
        try await load(Self.longSource + "\n\n<div id=\"raw\">raw</div>\n\nend")
        #expect(try await coordinator.scroll(toFragment: "raw"))
        #expect(try await scrollY() > 0)
    }

    @Test("reports a missing fragment without scrolling")
    func missingFragment() async throws {
        try await load(Self.longSource)
        #expect(try await coordinator.scroll(toFragment: "nowhere") == false)
        #expect(try await scrollY() == 0)
    }

    @Test("fragments are values, not script")
    func fragmentIsNotScript() async throws {
        try await load("text")
        #expect(try await coordinator.scroll(toFragment: "\"); document.title = \"pwned\"; (\"") == false)
        #expect(try await evaluate("return document.title;") as? String == "test.md")
    }

    // MARK: In-place swaps

    @Test("swaps content in place, keeping the scroll position")
    func replaceContent() async throws {
        try await load(Self.longSource)
        try await coordinator.scroll(toSourceLine: 101)
        let before = try await scrollY()
        let updated = DocumentContent(source: "# New title\n\n" + Self.longSource, fallbackTitle: "test.md")
        try await coordinator.replaceContent(with: updated.page, baseURL: nil)
        #expect(try await evaluate("return document.title;") as? String == "New title")
        #expect(try await evaluate("return document.querySelector('h1').textContent;") as? String == "New title")
        #expect(try await scrollY() == before)
    }

    @Test("replaceContent loads the page when nothing is loaded yet")
    func replaceContentLoads() async throws {
        try await coordinator.replaceContent(
            with: DocumentContent(source: "# Fresh", fallbackTitle: "a.md").page, baseURL: nil)
        #expect(coordinator.hasLoadedPage)
        #expect(try await evaluate("return document.title;") as? String == "Fresh")
    }

    // MARK: Appearance

    @Test("the page follows appearance changes live, without a reload")
    func appearance() async throws {
        coordinator.webView.appearance = NSAppearance(named: .aqua)
        try await load("text")
        try await evaluate("document.body.dataset.loaded = 'once'; return true;")
        let background = "return getComputedStyle(document.body).backgroundColor;"
        #expect(try await evaluate(background) as? String == "rgb(255, 255, 255)")

        coordinator.webView.appearance = NSAppearance(named: .darkAqua)
        var dark: String?
        for _ in 0..<50 where dark != "rgb(13, 17, 23)" {
            try await Task.sleep(for: .milliseconds(20))
            dark = try await evaluate(background) as? String
        }
        #expect(dark == "rgb(13, 17, 23)")
        // Same document: no reload happened.
        #expect(try await evaluate("return document.body.dataset.loaded;") as? String == "once")
    }

    // MARK: Script policy

    /// A hostile page with no CSP, so only `allowsContentJavaScript = false` stands between its
    /// scripts and the DOM. Every handler would leave a `data-*` marker on `<body>`.
    static let hostilePage = """
        <!doctype html>
        <html><head><title>original</title>
        <script>document.title = "head script ran";</script>
        </head>
        <body onload="document.body.setAttribute('data-onload', 'ran')">
        <script>document.body.setAttribute('data-script', 'ran');</script>
        <img id="img" src="data:," onerror="document.body.setAttribute('data-onerror', 'ran')">
        <div id="clicky" onclick="document.body.setAttribute('data-onclick', 'ran')">click</div>
        <a id="js" href="javascript:document.body.setAttribute('data-javascript-url', 'ran')">link</a>
        <article class="markdown-body"><p data-source-line="1">text</p></article>
        </body></html>
        """

    static let markersScript = """
        return ["data-onload", "data-script", "data-onerror", "data-onclick", "data-javascript-url"]
          .filter((name) => document.body.hasAttribute(name));
        """

    @Test("document scripts, inline handlers, and javascript: URLs don't run; app scripts do")
    func pageScriptsBlocked() async throws {
        try await coordinator.load(html: Self.hostilePage, baseURL: nil)
        // App-world script runs, and drives the events that would fire the page's handlers.
        try await evaluate(
            """
            document.getElementById("clicky").click();
            document.getElementById("js").click();
            await new Promise((resolve) => setTimeout(resolve, 100));
            return true;
            """)
        #expect(try await evaluate("return document.title;") as? String == "original")
        #expect(try await evaluate(Self.markersScript) as? [String] == [])
        // The bridge works on the same page.
        #expect(try await coordinator.currentSourceLine() == 1)
    }

    @Test("control: the hostile page's scripts do run with page JavaScript on")
    func hostilePageControl() async throws {
        let configuration = WebViewConfiguration.make()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let unsafe = WebViewCoordinator(configuration: configuration)
        window.contentView = unsafe.webView
        try await unsafe.load(html: Self.hostilePage, baseURL: nil)
        let evaluate = { (body: String) in
            try await unsafe.webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: AppScripts.world)
        }
        _ = try await evaluate(
            """
            document.getElementById("clicky").click();
            document.getElementById("js").click();
            await new Promise((resolve) => setTimeout(resolve, 100));
            return true;
            """)
        #expect(try await evaluate("return document.title;") as? String == "head script ran")
        #expect(
            try await evaluate(Self.markersScript) as? [String] == [
                "data-onload", "data-script", "data-onerror", "data-onclick", "data-javascript-url",
            ])
    }

    @Test("handlers in swapped-in content don't run")
    func swappedHandlersBlocked() async throws {
        try await load("text")
        let hostile = RenderedPage(
            rendered: RenderedDocument(
                html: """
                    <img src="data:," onerror="document.body.setAttribute('data-onerror', 'ran')">
                    <script>document.body.setAttribute('data-script', 'ran');</script>
                    <div id="clicky" onclick="document.body.setAttribute('data-onclick', 'ran')">x</div>
                    """),
            fallbackTitle: "swapped")
        try await coordinator.replaceContent(with: hostile, baseURL: nil)
        try await evaluate(
            """
            document.getElementById("clicky").click();
            await new Promise((resolve) => setTimeout(resolve, 100));
            return true;
            """)
        #expect(try await evaluate("return document.title;") as? String == "swapped")
        #expect(try await evaluate(Self.markersScript) as? [String] == [])
    }

    @Test("the bridge lives in the app world, invisible to the page world")
    func worldIsolation() async throws {
        try await load("text")
        #expect(try await evaluate("return typeof peep;") as? String == "object")
        #expect(try await evaluate("return typeof peep;", in: .page) as? String == "undefined")
    }

    @Test("the page keeps its CSP")
    func contentSecurityPolicy() async throws {
        try await load("text")
        let csp = try await evaluate(
            "return document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content;")
        #expect(csp as? String == ContentSecurityPolicy.viewer.header)
    }
}

// MARK: The preparation load (#32, #40)

extension WebViewCoordinatorTests {
    @Test("WebKit's percent-encoded spelling of the preparation URL (macOS 26) still matches")
    func preparationURLSpellings() throws {
        #expect(WebViewCoordinator.isPreparationURL(URL(string: "about:blank#peep-prepare")))
        #expect(WebViewCoordinator.isPreparationURL(URL(string: "about:blank%23peep-prepare")))
        #expect(!WebViewCoordinator.isPreparationURL(URL(string: "about:blank")))
        #expect(!WebViewCoordinator.isPreparationURL(URL(string: "about:blank#other")))
        #expect(!WebViewCoordinator.isPreparationURL(nil))

        let coordinator = WebViewCoordinator()
        coordinator.expectedLoadURL = WebViewCoordinator.preparationURL
        #expect(coordinator.isExpectedLoad(try #require(URL(string: "about:blank%23peep-prepare"))))
        #expect(!coordinator.isExpectedLoad(try #require(URL(string: "about:blank"))))
        // Only the preparation URL is compared loosely: a real load must match exactly.
        coordinator.expectedLoadURL = URL(string: "peep-doc://token/a%20b.md")
        #expect(coordinator.isExpectedLoad(try #require(URL(string: "peep-doc://token/a%20b.md"))))
        #expect(!coordinator.isExpectedLoad(try #require(URL(string: "peep-doc://token/a%2520b.md"))))
    }
}

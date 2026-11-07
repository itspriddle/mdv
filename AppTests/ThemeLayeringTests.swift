import AppKit
import MdvCore
import Testing
import WebKit

@testable import MdvApp

/// Hosted `WKWebView` tests for the theme cascade layers (`ThemeLayer`): the base layer's
/// protected rules survive a hostile theme in WebKit, and ordinary theme rules still apply.
@MainActor
@Suite("Theme layering", .serialized, .timeLimit(.minutes(1)))
struct ThemeLayeringTests {
    let coordinator = WebViewCoordinator()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    init() throws {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        coordinator.webView.appearance = try #require(NSAppearance(named: .aqua))
    }

    static let body = """
        <p><span id="sr" class="sr-only">hidden label</span></p>
        <span id="placeholder" class="remote-image" role="img"><span class="remote-image-alt">a</span></span>
        <span id="dark-placeholder" class="remote-image gh-dark-mode-only" role="img"></span>
        <pre id="code">x</pre>
        """

    func load(_ theme: Theme) async throws {
        let html = HTMLDocument(title: "t", body: Self.body, theme: theme, contentSecurityPolicy: .viewer).html
        try await coordinator.load(html: html, baseURL: nil)
    }

    /// `property` of the computed style of each element, by id.
    func computed(_ property: String, of ids: [String]) async throws -> [String: String] {
        let result = try await coordinator.webView.callAsyncJavaScript(
            "return Object.fromEntries(ids.map((id) => "
                + "[id, getComputedStyle(document.getElementById(id)).getPropertyValue(property)]));",
            arguments: ["ids": ids, "property": property], in: nil, contentWorld: AppScripts.world)
        return try #require(result as? [String: String])
    }

    @Test("a hostile theme, inside or outside its layer and with !important, can't undo protected rules")
    func hostileTheme() async throws {
        let hostile = Theme(
            id: "hostile", displayName: "Hostile", background: Theme.github.background,
            stylesheet: """
                .sr-only, #sr { position: static !important; width: auto !important; }
                .remote-image, #placeholder { display: none !important; visibility: hidden !important; }
                #dark-placeholder { display: inline-flex !important; }
                } /* escapes the theme layer: unlayered from here */
                .sr-only, #sr { position: static !important; }
                #placeholder { display: none !important; }
                #dark-placeholder { display: block !important; }
                """)
        try await load(hostile)
        #expect(try await computed("position", of: ["sr"]) == ["sr": "absolute"])
        #expect(try await computed("width", of: ["sr"]) == ["sr": "1px"])
        #expect(
            try await computed("display", of: ["placeholder", "dark-placeholder"])
                == ["placeholder": "inline-flex", "dark-placeholder": "none"])
        #expect(try await computed("visibility", of: ["placeholder"]) == ["placeholder": "visible"])
    }

    @Test("ordinary theme rules override the base layer's defaults, whatever their specificity")
    func themeOverridesDefaults() async throws {
        let theme = Theme(
            id: "plain", displayName: "Plain", background: Theme.github.background,
            stylesheet: "span { color: rgb(1, 2, 3); } pre { overflow: hidden; }")
        try await load(theme)
        // The base layer's `.remote-image` color (a class selector) loses to the theme's `span`.
        #expect(try await computed("color", of: ["placeholder"]) == ["placeholder": "rgb(1, 2, 3)"])
        #expect(try await computed("overflow", of: ["code"]) == ["code": "hidden"])
    }

    @Test("the default theme paints its background and keeps the screen layout")
    func defaultTheme() async throws {
        try await load(ThemeRegistry.bundled.defaultTheme)
        let background = try await coordinator.webView.callAsyncJavaScript(
            "return getComputedStyle(document.body).backgroundColor;", arguments: [:], in: nil,
            contentWorld: AppScripts.world)
        #expect(background as? String == "rgb(255, 255, 255)")
        #expect(try await computed("overflow", of: ["code"]) == ["code": "auto"])
        #expect(try await computed("display", of: ["placeholder"]) == ["placeholder": "inline-flex"])
    }
}

import MdvCore
import WebKit

/// The Swift side of `App/Scripts/DocumentBridge.js`. Each call runs a fixed function body in
/// `AppScripts.world` with its values as arguments. Call only after `load(_:baseURL:)` returns.
extension WebViewCoordinator {
    /// The source line at the top of the viewport; fractional between annotated blocks. `1` at
    /// the top of the page.
    func currentSourceLine() async throws -> Double {
        let result = try await callBridge("return mdv.currentSourceLine();")
        guard let line = (result as? NSNumber)?.doubleValue else {
            throw BridgeError.unexpectedResult
        }
        return line
    }

    /// The source line the outline reads its current section at: `currentSourceLine()` a few
    /// pixels below the top of the viewport, so a heading scrolled to the top is in its own
    /// section. Read after each `ScrollPosition.js` report.
    func sectionSourceLine() async throws -> Double {
        let result = try await callBridge("return mdv.sectionSourceLine();")
        guard let line = (result as? NSNumber)?.doubleValue else {
            throw BridgeError.unexpectedResult
        }
        return line
    }

    /// Scrolls so `line` (1-based, in the original file, fractional allowed) is at the top of
    /// the viewport.
    func scroll(toSourceLine line: Double) async throws {
        _ = try await callBridge("return mdv.scrollToSourceLine(line);", arguments: ["line": line])
    }

    /// Scrolls to the element a URL fragment names (without `#`; raw percent-encoded or already
    /// decoded): the first match of `LinkPolicy.fragmentIDCandidates`, so `foo` falls back to
    /// `user-content-foo`. An empty fragment or `top` with no match scrolls to the top. Returns
    /// `false` when nothing matches.
    @discardableResult
    func scroll(toFragment fragment: String) async throws -> Bool {
        let ids = LinkPolicy.fragmentIDCandidates(fragment)
        let result = try await callBridge("return mdv.scrollToFirstID(ids);", arguments: ["ids": ids])
        if (result as? NSNumber)?.boolValue == true {
            return true
        }
        if LinkPolicy.fragmentMeansTop(fragment) {
            try await scroll(toSourceLine: 1)
            return true
        }
        return false
    }

    /// Swaps the loaded page's body and title for `page`'s, keeping the stylesheet and scroll
    /// position. Falls back to a full `load` when there is no page to swap into.
    func replaceContent(with page: RenderedPage, baseURL: URL?) async throws {
        if hasLoadedPage {
            let result = try await callBridge(
                "return mdv.replaceContent(html, title);", arguments: ["html": page.body, "title": page.title])
            if (result as? NSNumber)?.boolValue == true {
                return
            }
        }
        try await load(page, baseURL: baseURL)
    }

    /// Live reload: swaps in `page` and keeps the reading position (`ReadingPosition`): the
    /// closest block at or before the top source line plus the offset into it, or the bottom if
    /// the view was at the bottom. One script run, so nothing paints in between. Falls back to a
    /// full `load` when there is no page to swap into.
    func updateContent(with page: RenderedPage, baseURL: URL?) async throws {
        if hasLoadedPage {
            let result = try await callBridge(
                "return mdv.updateContent(html, title);", arguments: ["html": page.body, "title": page.title])
            if (result as? NSNumber)?.boolValue == true {
                return
            }
        }
        try await load(page, baseURL: baseURL)
    }

    /// Replaces the loaded page's theme (the `mdv-theme` style element's text, `Theme.layerCSS`)
    /// and keeps the reading position, in one script run. Returns `false` when the page has no
    /// theme element. Use `show(_:)`, which tracks what the page holds.
    func replaceTheme(css: String) async throws -> Bool {
        let result = try await callBridge(
            "return mdv.replaceStyle(id, css);", arguments: ["id": ThemeLayer.theme.name, "css": css])
        return (result as? NSNumber)?.boolValue == true
    }

    /// The reading position to keep across a reload.
    func readingPosition() async throws -> ReadingPosition {
        let result = try await callBridge("return mdv.readingPosition();")
        guard let object = result as? [String: Any], let line = (object["line"] as? NSNumber)?.doubleValue,
            let atBottom = (object["atBottom"] as? NSNumber)?.boolValue
        else {
            throw BridgeError.unexpectedResult
        }
        return ReadingPosition(line: line, atBottom: atBottom)
    }

    /// Scrolls back to a position from `readingPosition()`.
    func restore(_ position: ReadingPosition) async throws {
        _ = try await callBridge(
            "return mdv.restorePosition({ line, atBottom });",
            arguments: ["line": position.line, "atBottom": position.atBottom])
    }

    /// Returns after `count` animation frames of the loaded page: after two, the frame that
    /// was pending when this was called has been drawn (`LaunchTiming`'s first paint).
    func waitForAnimationFrames(_ count: Int) async throws {
        _ = try await callBridge(
            "for (let i = 0; i < count; i++) { await new Promise(resolve => requestAnimationFrame(resolve)); }",
            arguments: ["count": count])
    }

    /// Calls `completion` after `count` animation frames of the loaded page, or never, when
    /// WebKit runs no frames for it (a window that isn't on screen, or closed). Unlike
    /// `waitForAnimationFrames(_:)`, nothing waiting holds the web view: WebKit keeps the
    /// pending reply only, so a page that never draws doesn't keep its web view, window, and
    /// document alive (and its web content process running) after the window closes.
    func requestAnimationFrames(_ count: Int, completion: @escaping @MainActor () -> Void) {
        guard hasLoadedPage else {
            completion()
            return
        }
        webView.callAsyncJavaScript(
            "for (let i = 0; i < count; i++) { await new Promise(resolve => requestAnimationFrame(resolve)); }",
            arguments: ["count": count], in: nil, in: AppScripts.world
        ) { _ in
            MainActor.assumeIsolated {
                completion()
            }
        }
    }

    /// Runs a fixed bridge function body in the app world. `body` must be a literal; pass every
    /// value through `arguments`.
    func callBridge(_ body: StaticString, arguments: [String: Any] = [:]) async throws -> Any? {
        guard hasLoadedPage else {
            throw BridgeError.noPage
        }
        return try await webView.callAsyncJavaScript(
            body.description, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    /// Where the reader is in the document, in source terms, so it survives a content change.
    struct ReadingPosition: Equatable, Sendable {
        /// The source line at the top of the viewport (`currentSourceLine()`).
        var line: Double
        /// Whether the view was scrolled to the bottom of a page taller than the viewport.
        var atBottom: Bool
    }

    enum BridgeError: Error, Equatable {
        /// No page has finished loading yet.
        case noPage
        /// The script returned a value of the wrong type.
        case unexpectedResult
    }
}

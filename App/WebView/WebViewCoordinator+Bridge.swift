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

    /// Runs a fixed bridge function body in the app world. `body` must be a literal; pass every
    /// value through `arguments`.
    func callBridge(_ body: StaticString, arguments: [String: Any] = [:]) async throws -> Any? {
        guard hasLoadedPage else {
            throw BridgeError.noPage
        }
        return try await webView.callAsyncJavaScript(
            body.description, arguments: arguments, in: nil, contentWorld: AppScripts.world)
    }

    enum BridgeError: Error, Equatable {
        /// No page has finished loading yet.
        case noPage
        /// The script returned a value of the wrong type.
        case unexpectedResult
    }
}

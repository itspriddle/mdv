import Foundation
import WebKit

/// Scripts that ship in the app bundle and run in the document web view.
///
/// Policy (VISION, security model): page JavaScript stays disabled; app scripts run only in
/// `world`, an isolated `WKContentWorld` the page cannot see, and receive values only as
/// `callAsyncJavaScript` arguments, never spliced into script source. Every script is a file in
/// `App/Scripts/` (bundle resources), so it is reviewed and linted like any other source.
@MainActor
enum AppScripts {
    /// The isolated world app scripts run in. Shares the DOM with the page, not its globals.
    static let world = WKContentWorld.world(name: "mdv")

    /// Scripts installed in every document web view, at document start, main frame only.
    static let userScripts: [WKUserScript] = bundledScriptNames.map { name in
        WKUserScript(
            source: source(named: name), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)
    }

    /// Bundled scripts to install, by file name (without `.js`), in order.
    private static let bundledScriptNames = ["DocumentBridge", "LinkHover", "ScrollPosition", "FindInPage"]

    /// The source of a bundled script. A missing script is a packaging bug, not a runtime
    /// condition, so it traps rather than shipping a window without its bridge.
    static func source(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("App script \(name).js is missing from the app bundle")
        }
        return source
    }
}

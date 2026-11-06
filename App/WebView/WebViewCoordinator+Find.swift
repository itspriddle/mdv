import WebKit

/// The Swift side of `App/Scripts/FindInPage.js`: fixed function bodies run in
/// `AppScripts.world`, with the query and indexes passed as arguments.
extension WebViewCoordinator: FindInPageHost {
    func findMatches(of query: String, caseSensitive: Bool, fromCurrent: Bool) async throws -> FindMatches {
        let result = try await callBridge(
            "return mdvFind.search(query, caseSensitive, fromCurrent);",
            arguments: ["query": query, "caseSensitive": caseSensitive, "fromCurrent": fromCurrent])
        guard let object = result as? [String: Any], let count = (object["count"] as? NSNumber)?.intValue,
            let isLimited = (object["limited"] as? NSNumber)?.boolValue,
            let first = (object["first"] as? NSNumber)?.intValue, count >= 0, first >= 0, first <= max(count - 1, 0)
        else {
            throw BridgeError.unexpectedResult
        }
        return FindMatches(count: count, isLimited: isLimited, first: first)
    }

    func selectMatch(at index: Int, reveal: Bool) async throws {
        _ = try await callBridge(
            "return mdvFind.select(index, reveal);", arguments: ["index": index, "reveal": reveal])
    }

    func clearMatches(selectingCurrent: Bool) async throws {
        _ = try await callBridge("return mdvFind.clear(selectCurrent);", arguments: ["selectCurrent": selectingCurrent])
    }

    func selectedText() async throws -> String {
        try await callBridge("return mdvFind.selectionText();") as? String ?? ""
    }

    func focusPage() {
        webView.window?.makeFirstResponder(webView)
    }
}

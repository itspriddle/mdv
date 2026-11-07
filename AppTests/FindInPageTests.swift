import AppKit
import Testing
import WebKit

@testable import MdvApp

/// Find in page (`FindInPage`, `App/Scripts/FindInPage.js`) in a hosted `WKWebView`.
@MainActor
@Suite("Find in page", .serialized, .timeLimit(.minutes(1)))
struct FindInPageTests {
    let coordinator = WebViewCoordinator()
    /// Stands in for the system find pasteboard, which tests must not change.
    let findPasteboard = FakeFindPasteboard()
    /// Offscreen, never shown: gives the page an 800x600 viewport.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered,
        defer: false)

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = coordinator.webView
        coordinator.find.pasteboard = findPasteboard
    }

    var find: FindInPage { coordinator.find }

    static func page(_ source: String) -> RenderedPage {
        DocumentContent(source: source, fallbackTitle: "test.md").page
    }

    func load(_ source: String) async throws {
        try await coordinator.load(Self.page(source), baseURL: nil)
    }

    @discardableResult
    func evaluate(_ body: String) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    /// Opens the bar and searches for `query`.
    func search(_ query: String, caseSensitive: Bool = false) async {
        find.show()
        find.setCaseSensitive(caseSensitive)
        find.setQuery(query)
        await find.waitUntilIdle()
    }

    func highlightSize(_ name: String) async throws -> Int {
        let size = try await coordinator.webView.callAsyncJavaScript(
            "return CSS.highlights.get(name)?.size ?? 0;", arguments: ["name": name], in: nil,
            contentWorld: AppScripts.world)
        return try #require(size as? NSNumber).intValue
    }

    // MARK: Matching

    @Test("is case-insensitive by default, with a case-sensitive option")
    func caseSensitivity() async throws {
        try await load("Apple apple APPLE pineapple")
        await search("apple")
        #expect(find.matchCount == 4)
        find.setCaseSensitive(true)
        await find.waitUntilIdle()
        #expect(find.matchCount == 2)
        #expect(find.status == "1 of 2")
    }

    @Test("matches across inline markup and soft line breaks")
    func acrossInlineMarkup() async throws {
        try await load("foo **bar** `baz`\n\nfoo\nbar")
        await search("foo bar baz")
        #expect(find.matchCount == 1)
        await search("foo bar")
        #expect(find.matchCount == 2)
    }

    @Test("never matches across blocks; shows Not found")
    func notAcrossBlocks() async throws {
        try await load("the end\n\nstart again\n\n- item\n  - nested")
        await search("end start")
        #expect(find.matchCount == 0)
        #expect(find.isNotFound)
        #expect(find.status == "Not found")
        await search("item nested")
        #expect(find.matchCount == 0)
    }

    @Test("treats the query as literal text")
    func literalQuery() async throws {
        try await load("axb a.b (x) [y] a\\b $1")
        for (query, count) in [("a.b", 1), ("(x)", 1), ("[y]", 1), ("a\\b", 1), ("$1", 1), ("x)", 1), ("a*", 0)] {
            await search(query)
            #expect(find.matchCount == count, "\(query)")
        }
    }

    @Test("skips text that isn't rendered")
    func hiddenText() async throws {
        try await load("<details><summary>Summary</summary>\n\nsecret word\n\n</details>\n\nvisible word")
        await search("word")
        #expect(find.matchCount == 1)
    }

    @Test("stops counting at the limit")
    func limit() async throws {
        try await load(String(repeating: "x ", count: 1500))
        await search("x")
        #expect(find.matchCount == 1000)
        #expect(find.isLimited)
        #expect(find.status == "1 of 1000+")
    }

    @Test("a blank query finds nothing and reports nothing")
    func blankQuery() async throws {
        try await load("a b c")
        await search("   ")
        #expect(find.matchCount == 0)
        #expect(find.status == nil)
        #expect(!find.isNotFound)
    }

    // MARK: Stepping and highlights

    @Test("next and previous wrap around")
    func wrapping() async throws {
        try await load("one cat\n\ntwo cat\n\nthree cat")
        await search("cat")
        #expect(find.status == "1 of 3")
        for expected in ["2 of 3", "3 of 3", "1 of 3"] {
            find.next()
            await find.waitUntilIdle()
            #expect(find.status == expected)
        }
        find.previous()
        await find.waitUntilIdle()
        #expect(find.status == "3 of 3")
        #expect(try await highlightSize("mdv-find") == 3)
        #expect(try await highlightSize("mdv-find-current") == 1)
    }

    @Test("starts at the first match in view and scrolls the current match into view")
    func scrolling() async throws {
        let source = (1...200).map { $0 == 150 ? "Paragraph \($0) needle." : "Paragraph \($0)." }
            .joined(separator: "\n\n")
        try await load(source)
        await search("needle")
        #expect(find.status == "1 of 1")
        let visible = try await evaluate(
            """
            const rect = CSS.highlights.get("mdv-find-current").values().next().value.getBoundingClientRect();
            return rect.top >= 0 && rect.bottom <= window.innerHeight;
            """)
        #expect(visible as? Bool == true)
        #expect(try #require(try await evaluate("return window.scrollY;") as? NSNumber).doubleValue > 0)
    }

    @Test("highlights paint on the page from the app's content world")
    func highlightsPaint() async throws {
        try await load("# needle needle needle")
        let before = try await snapshot()
        await search("needle")
        let after = try await snapshot()
        #expect(before != after)
        find.hide()
        await find.waitUntilIdle()
        try await evaluate("getSelection().removeAllRanges(); return true;")
        #expect(try await snapshot() == before)
    }

    /// The web view's pixels, after giving WebKit time to paint the last change.
    func snapshot() async throws -> Data? {
        try await evaluate("await new Promise((resolve) => setTimeout(resolve, 100)); return true;")
        let image = try await coordinator.webView.takeSnapshot(configuration: nil)
        return image.tiffRepresentation
    }

    @Test("closing removes the highlights and selects the current match")
    func hideSelectsCurrent() async throws {
        try await load("alpha Beta gamma")
        await search("beta")
        find.hide()
        await find.waitUntilIdle()
        #expect(!find.isVisible)
        #expect(try await highlightSize("mdv-find") == 0)
        #expect(try await evaluate("return getSelection().toString();") as? String == "Beta")
        #expect(find.query == "beta", "the query is kept")
    }

    @Test("Use Selection for Find takes the page's selection")
    func useSelection() async throws {
        try await load("alpha beta\ngamma delta")
        try await evaluate(
            """
            const range = document.createRange();
            range.selectNodeContents(document.querySelector("article p"));
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return true;
            """)
        find.useSelection()
        await find.waitUntilIdle()
        #expect(find.query == "alpha beta gamma delta")
        find.next()
        await find.waitUntilIdle()
        #expect(find.isVisible)
        #expect(find.status == "1 of 1")
    }

    @Test("Return right after typing goes to the next match, after the search")
    func stepAfterTyping() async throws {
        try await load("cat\n\ncat\n\ncat")
        find.show()
        find.setQuery("cat")
        find.next()
        await find.waitUntilIdle()
        #expect(find.status == "2 of 3")
    }

    // MARK: Live reload

    @Test("the search runs again on swapped-in content, keeping the match number")
    func refreshAfterReload() async throws {
        try await load("cat\n\ncat\n\ndog")
        await search("cat")
        find.next()
        await find.waitUntilIdle()
        #expect(find.status == "2 of 2")
        try await coordinator.updateContent(with: Self.page("cat\n\ncat\n\ncat cat"), baseURL: nil)
        await find.refresh()
        #expect(find.status == "2 of 4")
        #expect(try await highlightSize("mdv-find") == 4)
        try await coordinator.load(Self.page("dog"), baseURL: nil)
        await find.refresh()
        #expect(find.status == "Not found")
    }

    @Test("a reload with the bar closed does nothing")
    func refreshWhileHidden() async throws {
        try await load("cat")
        await search("cat")
        find.hide()
        await find.waitUntilIdle()
        await find.refresh()
        #expect(find.status == nil)
        #expect(try await highlightSize("mdv-find") == 0)
    }

    // MARK: Isolation

    @Test("the find script is invisible to the page world")
    func notInPageWorld() async throws {
        try await load("text")
        let pageWorld = try await coordinator.webView.callAsyncJavaScript(
            "return typeof globalThis.mdvFind;", arguments: [:], in: nil, contentWorld: .page)
        #expect(pageWorld as? String == "undefined")
        #expect(try await evaluate("return typeof globalThis.mdvFind;") as? String == "object")
    }

    @Test("a query is passed as a value, never run")
    func hostileQuery() async throws {
        try await load("text \"); globalThis.pwned = 1; (\"")
        await search("\"); globalThis.pwned = 1; (\"")
        #expect(find.matchCount == 1)
        #expect(try await evaluate("return typeof globalThis.pwned;") as? String == "undefined")
    }
}

@MainActor
@Suite("Find in page logic")
struct FindInPageLogicTests {
    @Test("steps wrap around in both directions")
    func stepping() {
        #expect(FindInPage.steppedIndex(from: nil, count: 3, forward: true) == 0)
        #expect(FindInPage.steppedIndex(from: nil, count: 3, forward: false) == 2)
        #expect(FindInPage.steppedIndex(from: 2, count: 3, forward: true) == 0)
        #expect(FindInPage.steppedIndex(from: 0, count: 3, forward: false) == 2)
        #expect(FindInPage.steppedIndex(from: 1, count: 3, forward: true) == 2)
        #expect(FindInPage.steppedIndex(from: 7, count: 3, forward: true) == 0)
        #expect(FindInPage.steppedIndex(from: 0, count: 0, forward: true) == nil)
    }

    @Test("status text")
    func status() {
        #expect(FindInPage.statusText(query: "a", hasSearched: false, count: 0, isLimited: false, current: nil) == nil)
        #expect(FindInPage.statusText(query: " ", hasSearched: true, count: 0, isLimited: false, current: nil) == nil)
        #expect(
            FindInPage.statusText(query: "a", hasSearched: true, count: 0, isLimited: false, current: nil)
                == "Not found")
        #expect(
            FindInPage.statusText(query: "a", hasSearched: true, count: 5, isLimited: false, current: 1) == "2 of 5")
        #expect(
            FindInPage.statusText(query: "a", hasSearched: true, count: 1000, isLimited: true, current: 0)
                == "1 of 1000+")
        #expect(
            FindInPage.statusText(query: "a", hasSearched: true, count: 5, isLimited: false, current: nil)
                == "5 matches")
    }

    @Test("Edit > Find has the standard commands")
    func menu() throws {
        let edit = MainMenu.build(contributions: [FindMenu.self]).item(withTitle: "Edit")?.submenu
        let find = try #require(edit?.item(withTitle: "Find")?.submenu)
        /// Title, key, and `NSTextFinder.Action` per item.
        func describe(_ item: NSMenuItem) -> String {
            let shift = item.keyEquivalentModifierMask.contains(.shift) ? "shift-" : ""
            return "\(item.title) cmd-\(shift)\(item.keyEquivalent) \(item.tag)"
        }
        #expect(
            find.items.map(describe) == [
                "Find… cmd-f \(NSTextFinder.Action.showFindInterface.rawValue)",
                "Find Next cmd-g \(NSTextFinder.Action.nextMatch.rawValue)",
                "Find Previous cmd-shift-g \(NSTextFinder.Action.previousMatch.rawValue)",
                "Use Selection for Find cmd-e \(NSTextFinder.Action.setSearchString.rawValue)",
                "Jump to Selection cmd-j 0",
            ])
        #expect(find.items.allSatisfy { $0.keyEquivalentModifierMask.contains(.command) })
        #expect(
            find.items.dropLast().allSatisfy { $0.action == #selector(NSResponder.performTextFinderAction(_:)) })
        #expect(find.items.last?.action == #selector(NSResponder.centerSelectionInVisibleArea(_:)))
    }

    @Test("find commands reach the window controller, also from the find field")
    func responderChain() {
        let selector = #selector(NSResponder.performTextFinderAction(_:))
        // WKWebView has no public find bar, so the commands pass it by.
        #expect(!WKWebView().responds(to: selector))
        #expect(DocumentWindowController().responds(to: selector))
        // The standard field editor would take (and disable) them; the find field's doesn't.
        let field = FindSearchField()
        #expect(field.cell is FindSearchFieldCell)
        #expect(!(field.cell?.fieldEditor(for: field)?.responds(to: selector) ?? true))
        let standard = NSTextView()
        standard.isFieldEditor = true
        #expect(standard.responds(to: selector))
    }

    @Test("a focus request made before the field is in a window focuses it once it is")
    func focusWaitsForWindow() {
        // SwiftUI calls `updateNSView` (which requests focus) before adding a new field to the
        // window, as when Cmd-F first opens the bar.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        let field = FindSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        field.requestFocus()
        #expect(field.currentEditor() == nil)
        window.contentView?.addSubview(field)
        #expect(field.currentEditor() != nil)
        #expect(window.firstResponder === field.currentEditor())
    }

    @Test("menu commands drive the window's find")
    func commands() {
        let controller = DocumentWindowController()
        controller.coordinator.find.pasteboard = nil
        let item = NSMenuItem(
            "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), key: "f")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        controller.performTextFinderAction(item)
        #expect(controller.coordinator.find.isVisible)
        controller.cancelOperation(nil)
        #expect(!controller.coordinator.find.isVisible)
    }
}

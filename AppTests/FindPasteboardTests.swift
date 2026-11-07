import AppKit
import Testing
import WebKit

@testable import MdvApp

/// The find pasteboard and Jump to Selection (#42), in a hosted `WKWebView`.
@MainActor
@Suite("Find pasteboard and Jump to Selection", .serialized, .timeLimit(.minutes(1)))
struct FindPasteboardTests {
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

    func load(_ source: String) async throws {
        try await coordinator.load(FindInPageTests.page(source), baseURL: nil)
    }

    @discardableResult
    func evaluate(_ body: String) async throws -> Any? {
        try await coordinator.webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: AppScripts.world)
    }

    /// Opens the bar and searches for `query`.
    func search(_ query: String) async {
        find.show()
        find.setQuery(query)
        await find.waitUntilIdle()
    }

    // MARK: Find pasteboard (#42)

    @Test("opening the bar takes a search made in another app from the find pasteboard")
    func pasteboardFillsBar() async throws {
        try await load("cat\n\ncat\n\ndog")
        findPasteboard.write("cat")
        find.show()
        await find.waitUntilIdle()
        #expect(find.query == "cat")
        #expect(find.status == "1 of 2")
    }

    @Test("a new query is written to the find pasteboard")
    func queryWritesPasteboard() async throws {
        try await load("cat dog")
        await search("dog")
        #expect(findPasteboard.string == "dog")
        await search("   ")
        #expect(findPasteboard.string == "dog", "a blank query isn't shared")
    }

    @Test("Find Next takes a newer search from the find pasteboard, but not its own")
    func nextAdoptsPasteboard() async throws {
        try await load("cat\n\ncat\n\ncat dog")
        await search("cat")
        find.next()
        await find.waitUntilIdle()
        #expect(find.status == "2 of 3", "its own write isn't taken as a new search")
        findPasteboard.write("dog")
        find.next()
        await find.waitUntilIdle()
        #expect(find.query == "dog")
        #expect(find.status == "1 of 1")
        find.next()
        await find.waitUntilIdle()
        #expect(find.query == "dog")
    }

    @Test("Find Next with the bar closed and a search from another app opens the bar on it")
    func nextOpensWithPasteboard() async throws {
        try await load("cat\n\ncat")
        findPasteboard.write("cat")
        find.next()
        await find.waitUntilIdle()
        #expect(find.isVisible)
        #expect(find.status == "1 of 2")
    }

    @Test("Use Selection for Find writes the find pasteboard, also when the query is unchanged")
    func useSelectionWritesPasteboard() async throws {
        try await load("alpha beta")
        try await selectFirstParagraph()
        find.useSelection()
        await find.waitUntilIdle()
        #expect(findPasteboard.string == "alpha beta")
        findPasteboard.write("other")
        find.useSelection()
        await find.waitUntilIdle()
        #expect(findPasteboard.string == "alpha beta")
    }

    func selectFirstParagraph() async throws {
        try await evaluate(
            """
            const range = document.createRange();
            range.selectNodeContents(document.querySelector("article p"));
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return true;
            """)
    }

    // MARK: Jump to Selection (#42)

    /// Whether the selection, or with `match` the current find match, is in the viewport.
    func isInView(match: Bool = false) async throws -> Bool {
        let result = try await coordinator.webView.callAsyncJavaScript(
            """
            const range = match
                ? CSS.highlights.get("mdv-find-current").values().next().value
                : getSelection().getRangeAt(0);
            const rect = range.getBoundingClientRect();
            return rect.top >= 0 && rect.bottom <= window.innerHeight;
            """, arguments: ["match": match], in: nil, contentWorld: AppScripts.world)
        return try #require(result as? Bool)
    }

    static let longSource = (1...200).map { $0 == 150 ? "Paragraph \($0) needle." : "Paragraph \($0)." }
        .joined(separator: "\n\n")

    @Test("Jump to Selection scrolls the selected text into view")
    func jumpToSelectedText() async throws {
        try await load(Self.longSource)
        try await evaluate(
            """
            const paragraph = [...document.querySelectorAll("article p")][149];
            const range = document.createRange();
            range.selectNodeContents(paragraph);
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            window.scrollTo(0, 0);
            return true;
            """)
        #expect(try await !isInView())
        find.jumpToSelection()
        await find.waitUntilIdle()
        #expect(try await isInView())
    }

    @Test("Jump to Selection goes back to the current match while the bar is open")
    func jumpToMatch() async throws {
        try await load(Self.longSource)
        await search("needle")
        try await evaluate("window.scrollTo(0, 0); return true;")
        #expect(try await !isInView(match: true))
        find.jumpToSelection()
        await find.waitUntilIdle()
        #expect(try await isInView(match: true))
    }

    @Test("Jump to Selection without a selection does nothing")
    func jumpWithoutSelection() async throws {
        try await load(Self.longSource)
        try await evaluate("getSelection().removeAllRanges(); window.scrollTo(0, 400); return true;")
        find.jumpToSelection()
        await find.waitUntilIdle()
        #expect(try #require(try await evaluate("return window.scrollY;") as? NSNumber).doubleValue == 400)
    }
}

@MainActor
@Suite("Find commands")
struct FindCommandTests {
    @Test("Jump to Selection reaches the window controller, past the web view and the find field")
    func jumpResponderChain() {
        let selector = #selector(NSResponder.centerSelectionInVisibleArea(_:))
        let controller = DocumentWindowController()
        #expect(controller.responds(to: selector))
        #expect(!controller.coordinator.webView.responds(to: selector))
        let field = FindSearchField()
        #expect(!(field.cell?.fieldEditor(for: field)?.responds(to: selector) ?? true))
    }

    @Test("Find items are enabled for the commands the window performs")
    func validation() {
        let controller = DocumentWindowController()
        func item(_ action: NSTextFinder.Action) -> NSMenuItem {
            let item = NSMenuItem(
                "", action: #selector(NSResponder.performTextFinderAction(_:)), key: "")
            item.tag = action.rawValue
            return item
        }
        for action in [NSTextFinder.Action.showFindInterface, .nextMatch, .previousMatch, .setSearchString] {
            #expect(controller.validateMenuItem(item(action)), "\(action.rawValue)")
        }
        #expect(!controller.validateMenuItem(item(.replaceAll)))
        #expect(!controller.validateMenuItem(item(.hideFindInterface)))
        controller.coordinator.find.pasteboard = nil
        controller.coordinator.find.show()
        #expect(controller.validateMenuItem(item(.hideFindInterface)))
        let jump = NSMenuItem("", action: #selector(NSResponder.centerSelectionInVisibleArea(_:)), key: "")
        #expect(controller.validateMenuItem(jump))
    }
}

/// A find pasteboard for tests: `changeCount` moves on every write, as the system's does.
@MainActor
final class FakeFindPasteboard: FindPasteboard {
    private(set) var changeCount = 0
    private(set) var string: String?

    func findString() -> String? {
        string
    }

    func writeFindString(_ string: String) -> Int {
        write(string)
        return changeCount
    }

    /// Writes `string`, as this app does or (in tests) another app would.
    func write(_ string: String) {
        self.string = string
        changeCount += 1
    }
}

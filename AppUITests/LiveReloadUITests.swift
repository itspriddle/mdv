import XCTest

/// Live reload: editing the open file updates the window in place, keeping the reading position.
@MainActor
final class LiveReloadUITests: XCTestCase {
    private var mdv: MdvUITestApp?
    private var folder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A writable copy of the `live-reload.md` fixture (150 one-line paragraphs).
    private func copyFixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "mdv-ui-live-reload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        let file = folder.appending(path: "live-reload.md")
        try FileManager.default.copyItem(at: try Fixtures.url(named: "live-reload.md"), to: file)
        return file
    }

    private func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testEditKeepsScrollPosition() throws {
        let file = try copyFixture()
        let mdv = MdvUITestApp.launch(opening: file)
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Live Reload Fixture")
        let webView = mdv.webView(in: window)
        mdv.waitForRenderedText("Paragraph 1.", in: window)

        // Scroll well into the document (the web view is first responder).
        for _ in 0..<4 {
            webView.typeKey(.pageDown, modifierFlags: [])
        }
        let anchor = try XCTUnwrap(firstVisibleParagraph(in: window), "a paragraph at the top of the view")
        let label = anchor.displayedText
        let before = anchor.frame.minY
        XCTAssertNotEqual(label, "Paragraph 1.", "the view scrolled")

        try append("\nAppended at the end.\n", to: file)
        mdv.waitForRenderedText("Appended at the end.", in: window)

        // Same paragraph, same place: the page was swapped in place, not reloaded to the top.
        let after = mdv.renderedText(label, in: window)
        XCTAssertTrue(after.exists)
        XCTAssertEqual(after.frame.minY, before, accuracy: 2, "\(label) moved")
    }

    func testDeletedFileShowsBanner() throws {
        let file = try copyFixture()
        let mdv = MdvUITestApp.launch(opening: file)
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Live Reload Fixture")
        mdv.waitForRenderedText("Paragraph 1.", in: window)

        try FileManager.default.removeItem(at: file)
        let banner = window.descendants(matching: .any)["file-status-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "deleted banner")
        // The last render stays.
        XCTAssertTrue(mdv.renderedText("Paragraph 1.", in: window).exists)

        try Data("# Live Reload Fixture\n\nRecreated.\n".utf8).write(to: file)
        mdv.waitForRenderedText("Recreated.", in: window)
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: banner)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: MdvUITestApp.defaultTimeout), .completed)
    }

    /// The topmost "Paragraph N." text whose top is inside the web view.
    ///
    /// The web area's frame is the whole scrollable page, so "inside" means below the top of the
    /// `WKWebView`'s visible bounds. WebKit puts a text run's string in its value (a heading's
    /// value is its level, a number, hence the cast; see `MdvUITestApp.renderedText`).
    private func firstVisibleParagraph(in window: XCUIElement) -> XCUIElement? {
        guard let mdv else {
            return nil
        }
        let top = mdv.webViewContainer(in: window).frame.minY
        let paragraphs = mdv.webView(in: window).staticTexts.matching(
            NSPredicate(format: "CAST(value, 'NSString') BEGINSWITH 'Paragraph ' OR label BEGINSWITH 'Paragraph '"))
        return paragraphs.allElementsBoundByIndex.first { $0.frame.minY >= top }
    }
}

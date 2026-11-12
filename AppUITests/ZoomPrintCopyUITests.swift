import AppKit
import XCTest

/// Zoom shortcuts, the Copy menu items (#26), and the context menu's Copy Link (#42).
///
/// These tests write to and read the **general pasteboard** (the app copies there); they
/// overwrite whatever was on it. Printing is not driven here (the print panel needs a user);
/// hosted `ZoomPrintCopyTests` print to PDF without a panel instead.
@MainActor
final class ZoomPrintCopyUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func launchSmoke() throws -> PeepUITestApp {
        let peep = try PeepUITestApp.launch(openingFixture: "smoke.md")
        self.peep = peep
        peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.")
        return peep
    }

    private func menuItem(_ title: String, in menu: String, of peep: PeepUITestApp) -> XCUIElement {
        peep.app.menuBars.menuBarItems[menu].menuItems[title]
    }

    private func click(_ title: String, in menu: String, of peep: PeepUITestApp) {
        peep.app.menuBars.menuBarItems[menu].click()
        menuItem(title, in: menu, of: peep).click()
    }

    private func waitForPasteboard(_ type: NSPasteboard.PasteboardType, toContain text: String) {
        let contains = NSPredicate { _, _ in
            NSPasteboard.general.string(forType: type)?.contains(text) ?? false
        }
        let expectation = XCTNSPredicateExpectation(predicate: contains, object: nil)
        let found = XCTWaiter().wait(for: [expectation], timeout: PeepUITestApp.defaultTimeout)
        XCTAssertEqual(
            found, .completed, "pasteboard \(type.rawValue): \(NSPasteboard.general.string(forType: type) ?? "nil")")
    }

    func testZoomShortcutsResizeTheText() throws {
        let peep = try launchSmoke()
        let paragraph = peep.renderedText("The quick brown fox renders in Peep.")
        let height = paragraph.frame.height

        peep.app.typeKey("=", modifierFlags: .command)
        peep.app.typeKey("=", modifierFlags: .command)
        let larger = NSPredicate { _, _ in paragraph.frame.height > height * 1.15 }
        wait(for: [XCTNSPredicateExpectation(predicate: larger, object: nil)], timeout: 5)
        XCTAssertTrue(menuItem("Actual Size", in: "View", of: peep).isEnabled)

        peep.app.typeKey("0", modifierFlags: .command)
        let actual = NSPredicate { _, _ in abs(paragraph.frame.height - height) < 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: actual, object: nil)], timeout: 5)

        peep.app.typeKey("-", modifierFlags: .command)
        let smaller = NSPredicate { _, _ in paragraph.frame.height < height * 0.95 }
        wait(for: [XCTNSPredicateExpectation(predicate: smaller, object: nil)], timeout: 5)
        peep.app.typeKey("0", modifierFlags: .command)
    }

    func testCopyMarkdownSource() throws {
        let peep = try launchSmoke()
        let source = try String(contentsOf: Fixtures.url(named: "smoke.md"), encoding: .utf8)
        NSPasteboard.general.clearContents()
        click("Copy Markdown Source", in: "Edit", of: peep)
        waitForPasteboard(.string, toContain: "# Smoke Test Fixture")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), source)
        XCTAssertEqual(NSPasteboard.general.string(forType: .init("net.daringfireball.markdown")), source)
    }

    func testCopyAsHTML() throws {
        let peep = try launchSmoke()
        NSPasteboard.general.clearContents()
        click("Copy as HTML", in: "Edit", of: peep)
        waitForPasteboard(.html, toContain: "<h1")
        let html = try XCTUnwrap(NSPasteboard.general.string(forType: .html))
        XCTAssertTrue(html.contains("<li>First list item</li>"), html)
        XCTAssertFalse(html.contains("data-source-line"), html)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), html)
    }

    func testCopySelectionAsRichAndPlainText() throws {
        let peep = try launchSmoke()
        NSPasteboard.general.clearContents()
        peep.webView().click()
        peep.app.typeKey("a", modifierFlags: .command)
        peep.app.typeKey("c", modifierFlags: .command)
        waitForPasteboard(.string, toContain: "The quick brown fox renders in Peep.")
        let types = NSPasteboard.general.types ?? []
        XCTAssertTrue(types.contains(.rtf) || types.contains(.html), "rich text: \(types)")
    }

    /// The context menu's Copy Link (#42): a relative link is copied as the `file:` URL it
    /// names, never the window's internal `peep-doc:` URL; an external link as written.
    func testCopyLinkCopiesFileURLsForRelativeLinks() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "links.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Links Fixture")
        peep.waitForRenderedText("Jump to", in: window)

        NSPasteboard.general.clearContents()
        peep.link("the target document", in: window).rightClick()
        peep.app.menuItems["Copy Link"].firstMatch.click()
        waitForPasteboard(.string, toContain: "links-target.md")
        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(copied.hasPrefix("file:///"), copied)
        XCTAssertTrue(copied.hasSuffix("/Fixtures/links-target.md#target-section"), copied)
        for type in NSPasteboard.general.types ?? [] {
            let value = NSPasteboard.general.string(forType: type) ?? ""
            XCTAssertFalse(value.lowercased().contains("peep-doc"), "\(type.rawValue): \(value)")
        }

        NSPasteboard.general.clearContents()
        peep.link("the example site", in: window).rightClick()
        peep.app.menuItems["Copy Link"].firstMatch.click()
        waitForPasteboard(.string, toContain: "example.com")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://example.com/peep-ui-test")
    }

    func testDocumentCommandsAreDisabledWithoutADocumentWindow() {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        peep.app.menuBars.menuBarItems["Edit"].click()
        XCTAssertFalse(menuItem("Copy Markdown Source", in: "Edit", of: peep).isEnabled)
        XCTAssertFalse(menuItem("Copy as HTML", in: "Edit", of: peep).isEnabled)
        peep.app.typeKey(.escape, modifierFlags: [])
        peep.app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(menuItem("Zoom In", in: "View", of: peep).isEnabled)
        XCTAssertFalse(menuItem("Actual Size", in: "View", of: peep).isEnabled)
        peep.app.typeKey(.escape, modifierFlags: [])
        peep.app.menuBars.menuBarItems["File"].click()
        XCTAssertFalse(menuItem("Print…", in: "File", of: peep).isEnabled)
        peep.app.typeKey(.escape, modifierFlags: [])
    }
}

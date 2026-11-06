import AppKit
import XCTest

/// Zoom shortcuts and the Copy menu items (#26).
///
/// These tests write to and read the **general pasteboard** (the app copies there); they
/// overwrite whatever was on it. Printing is not driven here (the print panel needs a user);
/// hosted `ZoomPrintCopyTests` print to PDF without a panel instead.
@MainActor
final class ZoomPrintCopyUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    private func launchSmoke() throws -> MdvUITestApp {
        let mdv = try MdvUITestApp.launch(openingFixture: "smoke.md")
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForRenderedText("The quick brown fox renders in mdv.")
        return mdv
    }

    private func menuItem(_ title: String, in menu: String, of mdv: MdvUITestApp) -> XCUIElement {
        mdv.app.menuBars.menuBarItems[menu].menuItems[title]
    }

    private func click(_ title: String, in menu: String, of mdv: MdvUITestApp) {
        mdv.app.menuBars.menuBarItems[menu].click()
        menuItem(title, in: menu, of: mdv).click()
    }

    private func waitForPasteboard(_ type: NSPasteboard.PasteboardType, toContain text: String) {
        let contains = NSPredicate { _, _ in
            NSPasteboard.general.string(forType: type)?.contains(text) ?? false
        }
        let expectation = XCTNSPredicateExpectation(predicate: contains, object: nil)
        let found = XCTWaiter().wait(for: [expectation], timeout: MdvUITestApp.defaultTimeout)
        XCTAssertEqual(
            found, .completed, "pasteboard \(type.rawValue): \(NSPasteboard.general.string(forType: type) ?? "nil")")
    }

    func testZoomShortcutsResizeTheText() throws {
        let mdv = try launchSmoke()
        let paragraph = mdv.renderedText("The quick brown fox renders in mdv.")
        let height = paragraph.frame.height

        mdv.app.typeKey("=", modifierFlags: .command)
        mdv.app.typeKey("=", modifierFlags: .command)
        let larger = NSPredicate { _, _ in paragraph.frame.height > height * 1.15 }
        wait(for: [XCTNSPredicateExpectation(predicate: larger, object: nil)], timeout: 5)
        XCTAssertTrue(menuItem("Actual Size", in: "View", of: mdv).isEnabled)

        mdv.app.typeKey("0", modifierFlags: .command)
        let actual = NSPredicate { _, _ in abs(paragraph.frame.height - height) < 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: actual, object: nil)], timeout: 5)

        mdv.app.typeKey("-", modifierFlags: .command)
        let smaller = NSPredicate { _, _ in paragraph.frame.height < height * 0.95 }
        wait(for: [XCTNSPredicateExpectation(predicate: smaller, object: nil)], timeout: 5)
        mdv.app.typeKey("0", modifierFlags: .command)
    }

    func testCopyMarkdownSource() throws {
        let mdv = try launchSmoke()
        let source = try String(contentsOf: Fixtures.url(named: "smoke.md"), encoding: .utf8)
        NSPasteboard.general.clearContents()
        click("Copy Markdown Source", in: "Edit", of: mdv)
        waitForPasteboard(.string, toContain: "# Smoke Test Fixture")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), source)
        XCTAssertEqual(NSPasteboard.general.string(forType: .init("net.daringfireball.markdown")), source)
    }

    func testCopyAsHTML() throws {
        let mdv = try launchSmoke()
        NSPasteboard.general.clearContents()
        click("Copy as HTML", in: "Edit", of: mdv)
        waitForPasteboard(.html, toContain: "<h1")
        let html = try XCTUnwrap(NSPasteboard.general.string(forType: .html))
        XCTAssertTrue(html.contains("<li>First list item</li>"), html)
        XCTAssertFalse(html.contains("data-source-line"), html)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), html)
    }

    func testCopySelectionAsRichAndPlainText() throws {
        let mdv = try launchSmoke()
        NSPasteboard.general.clearContents()
        mdv.webView().click()
        mdv.app.typeKey("a", modifierFlags: .command)
        mdv.app.typeKey("c", modifierFlags: .command)
        waitForPasteboard(.string, toContain: "The quick brown fox renders in mdv.")
        let types = NSPasteboard.general.types ?? []
        XCTAssertTrue(types.contains(.rtf) || types.contains(.html), "rich text: \(types)")
    }

    func testDocumentCommandsAreDisabledWithoutADocumentWindow() {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        mdv.app.menuBars.menuBarItems["Edit"].click()
        XCTAssertFalse(menuItem("Copy Markdown Source", in: "Edit", of: mdv).isEnabled)
        XCTAssertFalse(menuItem("Copy as HTML", in: "Edit", of: mdv).isEnabled)
        mdv.app.typeKey(.escape, modifierFlags: [])
        mdv.app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(menuItem("Zoom In", in: "View", of: mdv).isEnabled)
        XCTAssertFalse(menuItem("Actual Size", in: "View", of: mdv).isEnabled)
        mdv.app.typeKey(.escape, modifierFlags: [])
        mdv.app.menuBars.menuBarItems["File"].click()
        XCTAssertFalse(menuItem("Print…", in: "File", of: mdv).isEnabled)
        mdv.app.typeKey(.escape, modifierFlags: [])
    }
}

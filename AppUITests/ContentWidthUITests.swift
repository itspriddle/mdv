import XCTest

/// View > Content Width (#37): picking a preset reflows the open window in place.
@MainActor
final class ContentWidthUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    private func choose(_ title: String, in mdv: MdvUITestApp) {
        let view = mdv.app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Content Width"]
        submenu.hover()
        submenu.menuItems[title].click()
    }

    private func waitForWidth(
        of element: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line,
        _ condition: @escaping (CGFloat) -> Bool
    ) {
        let predicate = NSPredicate { _, _ in condition(element.frame.width) }
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: MdvUITestApp.defaultTimeout)
        XCTAssertEqual(result, .completed, "\(description): width \(element.frame.width)", file: file, line: line)
    }

    func testContentWidthPresetsReflowTheWindow() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "content-width.md")
        self.mdv = mdv
        mdv.waitForWindow(titled: "Content Width Fixture")
        let paragraph = mdv.waitForRenderedText("Long paragraph start")
        let themeWidth = paragraph.frame.width
        XCTAssertGreaterThan(themeWidth, 0)

        choose("Narrow", in: mdv)
        waitForWidth(of: paragraph, "Narrow is narrower than the theme default") { $0 < themeWidth * 0.8 }

        choose("Full Width", in: mdv)
        waitForWidth(of: paragraph, "Full Width is at least the theme default") { $0 >= themeWidth - 1 }

        choose("Theme Default", in: mdv)
        waitForWidth(of: paragraph, "Theme Default restores the theme's width") { abs($0 - themeWidth) < 2 }
    }
}

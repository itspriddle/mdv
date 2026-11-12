import XCTest

/// View > Content Width (#37): picking a preset reflows the open window in place. Zoom and
/// content width change only the front window (#47).
@MainActor
final class ContentWidthUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func choose(_ title: String, in peep: PeepUITestApp) {
        let view = peep.app.menuBars.menuBarItems["View"]
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
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: PeepUITestApp.defaultTimeout)
        XCTAssertEqual(result, .completed, "\(description): width \(element.frame.width)", file: file, line: line)
    }

    func testContentWidthPresetsReflowTheWindow() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "content-width.md")
        self.peep = peep
        peep.waitForWindow(titled: "Content Width Fixture")
        let paragraph = peep.waitForRenderedText("Long paragraph start")
        let themeWidth = paragraph.frame.width
        XCTAssertGreaterThan(themeWidth, 0)

        choose("Narrow", in: peep)
        waitForWidth(of: paragraph, "Narrow is narrower than the theme default") { $0 < themeWidth * 0.8 }

        choose("Full Width", in: peep)
        waitForWidth(of: paragraph, "Full Width is at least the theme default") { $0 >= themeWidth - 1 }

        choose("Theme Default", in: peep)
        waitForWidth(of: paragraph, "Theme Default restores the theme's width") { abs($0 - themeWidth) < 2 }
    }

    /// Two windows of the same long paragraph: View > Content Width and Cmd-+ change the front
    /// one only (#47).
    func testWidthAndZoomChangeOnlyTheFrontWindow() throws {
        let peep = try PeepUITestApp.launch(openingFixtures: ["content-width.md", "content-width-other.md"])
        self.peep = peep
        let first = peep.waitForWindow(titled: "Content Width Fixture")
        let second = peep.waitForWindow(titled: "Content Width Other Fixture")
        let firstParagraph = peep.waitForRenderedText("Long paragraph start", in: first)
        let secondParagraph = peep.waitForRenderedText("Long paragraph start", in: second)
        let firstFrame = firstParagraph.frame
        let secondFrame = secondParagraph.frame

        // The last one opened is in front.
        XCTAssertEqual(peep.frontWindow.title, "Content Width Other Fixture")
        choose("Narrow", in: peep)
        waitForWidth(of: secondParagraph, "the front window narrows") { $0 < secondFrame.width * 0.8 }
        XCTAssertEqual(firstParagraph.frame.width, firstFrame.width, accuracy: 1, "the other window keeps its width")

        // A Narrow column is 32em, so zooming in widens it on screen.
        let narrowWidth = secondParagraph.frame.width
        peep.app.typeKey("=", modifierFlags: .command)
        peep.app.typeKey("=", modifierFlags: .command)
        waitForWidth(of: secondParagraph, "the front window zooms in") { $0 > narrowWidth * 1.15 }
        XCTAssertEqual(firstParagraph.frame.width, firstFrame.width, accuracy: 1, "the other window keeps its zoom")
        XCTAssertEqual(firstParagraph.frame.height, firstFrame.height, accuracy: 1)
    }
}

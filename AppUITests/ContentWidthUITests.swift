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

    /// Settings' custom width overrides the window's preset, shows in View > Content Width, and
    /// turning it off puts the preset back.
    func testCustomWidthOverridesThePreset() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "content-width.md")
        self.peep = peep
        peep.waitForWindow(titled: "Content Width Fixture")
        let paragraph = peep.waitForRenderedText("Long paragraph start")
        choose("Full Width", in: peep)
        let fullWidth = paragraph.frame.width
        waitForWidth(of: paragraph, "Full Width is wider than the custom width") { $0 > 400 }

        let settings = peep.openSettings()
        let field = settings.textFields["settings-custom-width-points"]
        XCTAssertTrue(field.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(field.isEnabled, "the field is off until the custom width is")
        settings.checkBoxes["settings-custom-width"].click()
        XCTAssertTrue(field.isEnabled)
        XCTAssertFalse(settings.popUpButtons["settings-content-width"].isEnabled, "the preset picker is overridden")
        field.doubleClick()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("400\r")
        settings.typeKey("w", modifierFlags: .command)

        waitForWidth(of: paragraph, "the column is 400px of text") { $0 > 380 && $0 <= 401 }

        let view = peep.app.menuBars.menuBarItems["View"]
        view.click()
        let submenu = view.menuItems["Content Width"]
        submenu.hover()
        let custom = submenu.menuItems["Custom: 400px"]
        XCTAssertTrue(custom.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(submenu.menuItems["Narrow"].isEnabled, "presets are disabled while it is on")
        peep.app.typeKey(.escape, modifierFlags: [])
        peep.app.typeKey(.escape, modifierFlags: [])

        let reopened = peep.openSettings()
        reopened.checkBoxes["settings-custom-width"].click()
        reopened.typeKey("w", modifierFlags: .command)
        waitForWidth(of: paragraph, "the window's preset is back") { abs($0 - fullWidth) < 2 }
    }
}

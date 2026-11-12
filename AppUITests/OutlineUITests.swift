import XCTest

/// The outline sidebar (#24): toggled from the View menu shortcut, a click on a heading scrolls
/// the document to it; Expand All and Collapse All from the View menu and the context menu (#43).
@MainActor
final class OutlineUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testToggleOutlineAndJumpToHeading() throws {
        // Start hidden regardless of the reader's default (UI tests never write it).
        let peep = try PeepUITestApp.launch(openingFixture: "outline.md", arguments: ["-OutlineVisible", "NO"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Outline Fixture")
        peep.waitForRenderedText("Intro paragraph.", in: window)
        let outline = peep.outline(in: window)
        XCTAssertFalse(outline.isHittable, "the outline starts hidden")

        // View > Show Outline.
        window.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(outline.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        let final = peep.outlineText("Final Section", in: window)
        XCTAssertTrue(final.waitForExistence(timeout: PeepUITestApp.defaultTimeout))

        let paragraph = peep.renderedText("The final paragraph is here.", in: window)
        XCTAssertTrue(paragraph.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(paragraph.isHittable, "the final paragraph starts below the fold")

        final.click()

        let scrolled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: paragraph)
        wait(for: [scrolled], timeout: PeepUITestApp.defaultTimeout)

        // View > Hide Outline.
        window.typeKey("s", modifierFlags: [.command, .control])
        let hidden = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: final)
        wait(for: [hidden], timeout: PeepUITestApp.defaultTimeout)
    }

    func testCollapseAllAndExpandAll() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "outline.md", arguments: ["-OutlineVisible", "YES"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Outline Fixture")
        let middle = peep.outlineText("Middle Section", in: window)
        XCTAssertTrue(middle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))

        // View > Collapse All Headings hides the nested entries.
        peep.app.menuBars.menuBarItems["View"].click()
        peep.app.menuBars.menuBarItems["View"].menuItems["Collapse All Headings"].click()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: middle)
        wait(for: [gone], timeout: PeepUITestApp.defaultTimeout)

        // The sidebar's context menu > Expand All shows them again.
        peep.outlineText("Outline Fixture", in: window).rightClick()
        peep.outline(in: window).menuItems["Expand All"].click()
        XCTAssertTrue(middle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
    }
}

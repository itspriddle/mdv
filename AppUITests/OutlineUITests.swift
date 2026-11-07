import XCTest

/// The outline sidebar (#24): toggled from the View menu shortcut, a click on a heading scrolls
/// the document to it; Expand All and Collapse All from the View menu and the context menu (#43).
@MainActor
final class OutlineUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testToggleOutlineAndJumpToHeading() throws {
        // Start hidden regardless of the reader's default (UI tests never write it).
        let mdv = try MdvUITestApp.launch(openingFixture: "outline.md", arguments: ["-OutlineVisible", "NO"])
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Outline Fixture")
        mdv.waitForRenderedText("Intro paragraph.", in: window)
        let outline = mdv.outline(in: window)
        XCTAssertFalse(outline.isHittable, "the outline starts hidden")

        // View > Show Outline.
        window.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(outline.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        let final = mdv.outlineText("Final Section", in: window)
        XCTAssertTrue(final.waitForExistence(timeout: MdvUITestApp.defaultTimeout))

        let paragraph = mdv.renderedText("The final paragraph is here.", in: window)
        XCTAssertTrue(paragraph.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        XCTAssertFalse(paragraph.isHittable, "the final paragraph starts below the fold")

        final.click()

        let scrolled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: paragraph)
        wait(for: [scrolled], timeout: MdvUITestApp.defaultTimeout)

        // View > Hide Outline.
        window.typeKey("s", modifierFlags: [.command, .control])
        let hidden = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: final)
        wait(for: [hidden], timeout: MdvUITestApp.defaultTimeout)
    }

    func testCollapseAllAndExpandAll() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "outline.md", arguments: ["-OutlineVisible", "YES"])
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Outline Fixture")
        let middle = mdv.outlineText("Middle Section", in: window)
        XCTAssertTrue(middle.waitForExistence(timeout: MdvUITestApp.defaultTimeout))

        // View > Collapse All Headings hides the nested entries.
        mdv.app.menuBars.menuBarItems["View"].click()
        mdv.app.menuBars.menuBarItems["View"].menuItems["Collapse All Headings"].click()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: middle)
        wait(for: [gone], timeout: MdvUITestApp.defaultTimeout)

        // The sidebar's context menu > Expand All shows them again.
        mdv.outlineText("Outline Fixture", in: window).rightClick()
        mdv.outline(in: window).menuItems["Expand All"].click()
        XCTAssertTrue(middle.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
    }
}

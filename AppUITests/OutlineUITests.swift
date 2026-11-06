import XCTest

/// The outline sidebar (#24): toggled from the View menu shortcut, a click on a heading scrolls
/// the document to it.
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
}

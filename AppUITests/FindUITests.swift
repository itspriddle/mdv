import XCTest

/// Find in page: the find bar, its shortcuts, and the match count.
@MainActor
final class FindUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testFindStepsThroughMatchesAndWraps() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "find.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Find Fixture")
        mdv.waitForRenderedText("The first lantern", in: window)

        window.typeKey("f", modifierFlags: .command)
        let field = mdv.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the find bar opened")
        field.typeText("lantern")
        // Case-insensitive by default: "Lantern" counts.
        mdv.waitForFindStatus("1 of 3", in: window)

        window.typeKey("g", modifierFlags: .command)
        mdv.waitForFindStatus("2 of 3", in: window)
        field.typeText("\r")
        mdv.waitForFindStatus("3 of 3", in: window)
        window.typeKey("g", modifierFlags: .command)
        mdv.waitForFindStatus("1 of 3", in: window)
        window.typeKey("g", modifierFlags: [.command, .shift])
        mdv.waitForFindStatus("3 of 3", in: window)

        // Match Case drops "Lantern" and searches from the current match (the third lantern,
        // still a match), so it stays current: now the second of two.
        window.checkBoxes["find-case-sensitive"].firstMatch.click()
        mdv.waitForFindStatus("2 of 2", in: window)

        field.typeKey(.delete, modifierFlags: [])
        field.typeText("x")
        mdv.waitForFindStatus("Not found", in: window)

        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "Esc closed the find bar")
    }
}

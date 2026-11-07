import AppKit
import XCTest

/// Find in page: the find bar, its shortcuts, and the match count; the shared find pasteboard
/// and Jump to Selection (#42).
///
/// The find pasteboard tests write to and read the system **find pasteboard**, as searching in
/// any app does; they overwrite whatever was on it.
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

    /// A search made in another app fills the find bar on Find Next; a search typed in mdv, and
    /// Use Selection for Find, are written back for other apps.
    func testFindSharesTheFindPasteboard() throws {
        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        findPasteboard.setString("lantern", forType: .string)

        let mdv = try MdvUITestApp.launch(openingFixture: "find.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Find Fixture")
        mdv.waitForRenderedText("The first lantern", in: window)

        // Cmd-G with the bar closed: opens it on the other app's search.
        window.typeKey("g", modifierFlags: .command)
        let field = mdv.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the find bar opened")
        mdv.waitForFindStatus("1 of 3", in: window)
        XCTAssertEqual(field.value as? String, "lantern")

        // Typing in mdv shares the search.
        window.typeKey("f", modifierFlags: .command)
        field.typeText("garden")
        mdv.waitForFindStatus("1 of 1", in: window)
        MdvUITestApp.waitForString("garden", on: findPasteboard)

        // Esc leaves the match selected; Cmd-E puts the selection back on the pasteboard after
        // another app changed it, and Cmd-G then finds it.
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout))
        findPasteboard.clearContents()
        findPasteboard.setString("porch", forType: .string)
        window.typeKey("e", modifierFlags: .command)
        MdvUITestApp.waitForString("garden", on: findPasteboard)
        window.typeKey("g", modifierFlags: .command)
        mdv.waitForFindStatus("1 of 1", in: window)
        XCTAssertEqual(field.value as? String, "garden")
    }

    /// Jump to Selection (Cmd-J) scrolls the selection back into view.
    func testJumpToSelectionScrollsTheSelectionIntoView() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "links.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Links Fixture")
        let target = mdv.waitForRenderedText("Filler paragraph 5.", in: window)

        // Select the paragraph's text: find it, then close the bar, which selects the match.
        window.typeKey("f", modifierFlags: .command)
        let field = mdv.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        field.typeText("Filler paragraph 5.")
        mdv.waitForFindStatus("1 of 1", in: window)
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout))

        window.typeKey(.end, modifierFlags: [])
        let bottom = mdv.renderedText("The bottom paragraph is here.", in: window)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: bottom)], timeout: 5)
        XCTAssertFalse(target.isHittable, "scrolled away from the selection")

        window.typeKey("j", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: target)], timeout: 5)
    }
}

import AppKit
import XCTest

/// Find in page: the find bar, its shortcuts, and the match count; the shared find pasteboard
/// and Jump to Selection (#42).
///
/// The find pasteboard tests write to and read the system **find pasteboard**, as searching in
/// any app does; they overwrite whatever was on it.
@MainActor
final class FindUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testFindStepsThroughMatchesAndWraps() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "find.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Find Fixture")
        peep.waitForRenderedText("The first lantern", in: window)

        window.typeKey("f", modifierFlags: .command)
        let field = peep.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the find bar opened")
        field.typeText("lantern")
        // Case-insensitive by default: "Lantern" counts.
        peep.waitForFindStatus("1 of 3", in: window)

        window.typeKey("g", modifierFlags: .command)
        peep.waitForFindStatus("2 of 3", in: window)
        field.typeText("\r")
        peep.waitForFindStatus("3 of 3", in: window)
        window.typeKey("g", modifierFlags: .command)
        peep.waitForFindStatus("1 of 3", in: window)
        window.typeKey("g", modifierFlags: [.command, .shift])
        peep.waitForFindStatus("3 of 3", in: window)

        // Match Case drops "Lantern" and searches from the current match (the third lantern,
        // still a match), so it stays current: now the second of two.
        window.checkBoxes["find-case-sensitive"].firstMatch.click()
        peep.waitForFindStatus("2 of 2", in: window)

        field.typeKey(.delete, modifierFlags: [])
        field.typeText("x")
        peep.waitForFindStatus("Not found", in: window)

        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout), "Esc closed the find bar")
    }

    /// A search made in another app fills the find bar on Find Next; a search typed in Peep, and
    /// Use Selection for Find, are written back for other apps.
    func testFindSharesTheFindPasteboard() throws {
        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        findPasteboard.setString("lantern", forType: .string)

        let peep = try PeepUITestApp.launch(openingFixture: "find.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Find Fixture")
        peep.waitForRenderedText("The first lantern", in: window)

        // Cmd-G with the bar closed: opens it on the other app's search.
        window.typeKey("g", modifierFlags: .command)
        let field = peep.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the find bar opened")
        peep.waitForFindStatus("1 of 3", in: window)
        XCTAssertEqual(field.value as? String, "lantern")

        // Typing in Peep shares the search.
        window.typeKey("f", modifierFlags: .command)
        field.typeText("garden")
        peep.waitForFindStatus("1 of 1", in: window)
        PeepUITestApp.waitForString("garden", on: findPasteboard)

        // Esc leaves the match selected; Cmd-E puts the selection back on the pasteboard after
        // another app changed it, and Cmd-G then finds it.
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout))
        findPasteboard.clearContents()
        findPasteboard.setString("porch", forType: .string)
        window.typeKey("e", modifierFlags: .command)
        PeepUITestApp.waitForString("garden", on: findPasteboard)
        window.typeKey("g", modifierFlags: .command)
        peep.waitForFindStatus("1 of 1", in: window)
        XCTAssertEqual(field.value as? String, "garden")
    }

    /// Jump to Selection (Cmd-J) scrolls the selection back into view.
    func testJumpToSelectionScrollsTheSelectionIntoView() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "links.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Links Fixture")
        let target = peep.waitForRenderedText("Filler paragraph 5.", in: window)

        // Select the paragraph's text: find it, then close the bar, which selects the match.
        window.typeKey("f", modifierFlags: .command)
        let field = peep.findField(in: window)
        XCTAssertTrue(field.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        field.typeText("Filler paragraph 5.")
        peep.waitForFindStatus("1 of 1", in: window)
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout))

        window.typeKey(.end, modifierFlags: [])
        let bottom = peep.renderedText("The bottom paragraph is here.", in: window)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: bottom)], timeout: 5)
        XCTAssertFalse(target.isHittable, "scrolled away from the selection")

        window.typeKey("j", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: target)], timeout: 5)
    }
}

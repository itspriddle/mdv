import XCTest

/// The status bar: the document's word count, hidden and shown with View > Hide/Show Status Bar
/// (Command-/).
@MainActor
final class StatusBarUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testWordCountAndToggle() throws {
        // Start shown regardless of the reader's default (UI tests never write it).
        let peep = try PeepUITestApp.launch(openingFixture: "smoke.md", arguments: ["-StatusBarVisible", "YES"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)

        let count = peep.wordCount(in: window)
        XCTAssertTrue(count.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        // macOS reports a static text's string as its value.
        XCTAssertEqual(count.value as? String, "18 words")

        // View > Hide Status Bar.
        window.typeKey("/", modifierFlags: .command)
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: count)
        wait(for: [hidden], timeout: PeepUITestApp.defaultTimeout)

        // View > Show Status Bar.
        peep.app.menuBars.menuBarItems["View"].click()
        peep.app.menuBars.menuBarItems["View"].menuItems["Show Status Bar"].click()
        XCTAssertTrue(count.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
    }
}

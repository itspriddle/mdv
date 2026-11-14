import XCTest

/// The status bar: the document's word count and the pin and outline toggles, hidden and shown
/// with View > Hide/Show Status Bar (Command-/).
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

    func testOutlineToggleButton() throws {
        let peep = try PeepUITestApp.launch(
            openingFixture: "outline.md", arguments: ["-StatusBarVisible", "YES", "-OutlineVisible", "NO"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Outline Fixture")
        peep.waitForRenderedText("Intro paragraph.", in: window)
        let outline = peep.outline(in: window)
        XCTAssertFalse(outline.isHittable, "the outline starts hidden")

        let toggle = peep.outlineToggle(in: window)
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        toggle.click()
        let final = peep.outlineText("Final Section", in: window)
        XCTAssertTrue(final.waitForExistence(timeout: PeepUITestApp.defaultTimeout))

        toggle.click()
        let hidden = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: final)
        wait(for: [hidden], timeout: PeepUITestApp.defaultTimeout)
    }

    func testPinToggleAndMenu() throws {
        let peep = try PeepUITestApp.launch(
            openingFixture: "smoke.md", arguments: ["-StatusBarVisible", "YES", "-PinNewWindows", "NO"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)

        let toggle = peep.pinToggle(in: window)
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? String, "off")
        toggle.click()
        let pinned = expectation(for: NSPredicate(format: "value == 'on'"), evaluatedWith: toggle)
        wait(for: [pinned], timeout: PeepUITestApp.defaultTimeout)

        // Window > Unpin Window.
        peep.app.menuBars.menuBarItems["Window"].click()
        peep.app.menuBars.menuBarItems["Window"].menuItems["Unpin Window"].click()
        let unpinned = expectation(for: NSPredicate(format: "value == 'off'"), evaluatedWith: toggle)
        wait(for: [unpinned], timeout: PeepUITestApp.defaultTimeout)
    }
}

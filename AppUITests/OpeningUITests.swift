import XCTest

/// Opening documents (#22): File > Open, duplicate opens, native tabs, and window restoration.
///
/// Finder double-click, Open With, Dock drops, drops on a window, the Dock menu, Open Recent
/// contents, and the system "Prefer tabs" setting can't be driven from XCUITest; they are
/// manual checks (see the #22 handoff and `DocumentController`).
@MainActor
final class OpeningUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testFileOpenShowsOpenPanel() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "smoke.md")
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")

        mdv.app.typeKey("o", modifierFlags: .command)
        let panel = mdv.openPanel
        XCTAssertTrue(panel.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "Open panel")
        mdv.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "Open panel dismissed")
    }

    func testFileMenuHasOneOpenRecent() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "smoke.md")
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")

        let file = mdv.app.menuBars.menuBarItems["File"]
        file.click()
        XCTAssertEqual(file.menuItems.matching(NSPredicate(format: "title == 'Open Recent'")).count, 1)
        mdv.app.typeKey(.escape, modifierFlags: [])
    }

    func testOpeningAnOpenFileAgainKeepsOneWindow() throws {
        let mdv = try MdvUITestApp.launch(openingFixtures: ["smoke.md", "smoke.md"])
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForRenderedText("The quick brown fox renders in mdv.")
        mdv.waitForWindowCount(1)
    }

    func testMergeAllWindowsMakesTabs() throws {
        let mdv = try MdvUITestApp.launch(openingFixtures: ["smoke.md", "links-target.md"])
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForWindow(titled: "Link Target")
        mdv.waitForWindowCount(2)

        mdv.app.menuBars.menuBarItems["Window"].click()
        mdv.app.menuItems["Merge All Windows"].click()

        mdv.waitForWindowCount(1)
        let window = mdv.frontWindow
        XCTAssertTrue(mdv.tab(titled: "Smoke Test Fixture", in: window).waitForExistence(timeout: 5))
        XCTAssertTrue(mdv.tab(titled: "Link Target", in: window).exists)

        // Cmd-Shift-] shows the next tab.
        let before = window.title
        mdv.app.typeKey("]", modifierFlags: [.command, .shift])
        let changed = NSPredicate { _, _ in mdv.frontWindow.title != before }
        wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5)
    }

    /// Quit and relaunch restores the window and its reading position. This test saves real
    /// restoration state for mdv's bundle ID (shared with a Debug mdv you use day to day), so it
    /// runs only when asked: `TEST_RUNNER_MDV_UI_TEST_RESTORATION=1 make test-ui` (CI sets it).
    /// It ends by closing its window and quitting, so the saved state is left empty.
    func testRelaunchRestoresWindowAndScrollPosition() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MDV_UI_TEST_RESTORATION"] == "1",
            "Set TEST_RUNNER_MDV_UI_TEST_RESTORATION=1 to run (writes real saved state)")
        let first = try MdvUITestApp.launch(openingFixtures: ["restoration.md"], restoresState: true)
        mdv = first
        let window = first.waitForWindow(titled: "Restoration Fixture")
        let last = first.waitForRenderedText("Restoration paragraph 150.", in: window)
        // Scroll to the end; ScrollPosition.js reports the position after the scroll settles.
        first.webView(in: window).click()
        first.app.typeKey(.end, modifierFlags: [])
        XCTAssertTrue(last.waitForHittable(timeout: 5), "scrolled to the end")
        Thread.sleep(forTimeInterval: 1)
        first.app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(first.app.wait(for: .notRunning, timeout: MdvUITestApp.defaultTimeout))

        // No document argument: the window comes back from saved state alone.
        let second = MdvUITestApp.launch(restoresState: true)
        mdv = second
        let restored = second.waitForWindow(titled: "Restoration Fixture")
        let restoredLast = second.waitForRenderedText("Restoration paragraph 150.", in: restored)
        XCTAssertTrue(restoredLast.waitForHittable(timeout: 5), "the reading position is restored")
        XCTAssertFalse(second.renderedText("Restoration paragraph 1.", in: restored).isHittable)

        // Leave no restorable windows behind.
        second.app.typeKey("w", modifierFlags: .command)
        second.waitForWindowCount(0)
        second.app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(second.app.wait(for: .notRunning, timeout: MdvUITestApp.defaultTimeout))
    }
}

extension XCUIElement {
    /// Waits until the element exists and is hittable (on screen, not covered).
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout)
            == .completed
    }
}

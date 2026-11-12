import XCTest

/// `peep FILE` (#67): the embedded CLI opens files in the running app through Launch Services,
/// focuses a file that is already open, and passes `--theme` as the window's pick.
@MainActor
final class CommandLineUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testOpensFileInRunningAppAndFocusesItAgain() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let smoke = try PeepUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let first = try PeepUITestApp.runCommandLine([smoke])
        XCTAssertEqual(first.status, 0, first.stderr)
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)

        // Another window in front, then Peep on the first file again: it comes forward, still one.
        let other = try PeepUITestApp.temporaryCopy(ofFixture: "links-target.md").path(percentEncoded: false)
        XCTAssertEqual(try PeepUITestApp.runCommandLine([other]).status, 0)
        peep.waitForWindowCount(2)
        XCTAssertNotEqual(peep.frontWindow.title, "Smoke Test Fixture")

        let again = try PeepUITestApp.runCommandLine([smoke])
        XCTAssertEqual(again.status, 0, again.stderr)
        waitUntil("the open window came forward") { peep.frontWindow.title == "Smoke Test Fixture" }
        peep.waitForWindowCount(2)
    }

    /// `--theme` on a document whose frontmatter names Serif: the window opens in GitHub as its
    /// View > Theme pick (so Document's Theme is offered), and going back to the document's
    /// theme restyles the page; then `--theme serif` on the open file switches it again.
    func testThemeFlagBecomesTheWindowsPick() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let themed = try PeepUITestApp.temporaryCopy(ofFixture: "document-theme.md").path(percentEncoded: false)

        let result = try PeepUITestApp.runCommandLine(["--theme", "github", themed])
        XCTAssertEqual(result.status, 0, result.stderr)
        let window = peep.waitForWindow(titled: "Document Theme Fixture")
        let paragraph = peep.waitForRenderedText("This paragraph is set in the theme", in: window)
        let githubWidth = paragraph.frame.width
        XCTAssertTrue(peep.documentThemeItemIsEnabled(expected: true), "the pick hides the document's theme")

        peep.chooseDocumentTheme()
        waitUntil("the document's Serif restyles the page") { abs(paragraph.frame.width - githubWidth) > 1 }
        XCTAssertFalse(peep.documentThemeItemIsEnabled(expected: false), "no pick any more")

        // Already open: the window switches to the flag's theme.
        XCTAssertEqual(try PeepUITestApp.runCommandLine(["--theme", "github", themed]).status, 0)
        waitUntil("GitHub again") { abs(paragraph.frame.width - githubWidth) < 1 }
        XCTAssertTrue(peep.documentThemeItemIsEnabled(expected: true))
        peep.waitForWindowCount(1)
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                timeout: PeepUITestApp.defaultTimeout),
            .completed, description)
    }

    func testBadPathOpensNothing() throws {
        let peep = PeepUITestApp.launch()
        self.peep = peep
        let smoke = try PeepUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)
        let missing = FileManager.default.temporaryDirectory.appending(path: "peep-missing-\(UUID().uuidString).md")

        let result = try PeepUITestApp.runCommandLine([smoke, missing.path(percentEncoded: false)])
        XCTAssertEqual(result.status, 66)
        XCTAssertTrue(result.stderr.contains("No such file or directory"), result.stderr)
        XCTAssertFalse(peep.window(titled: "Smoke Test Fixture").waitForExistence(timeout: 2))
    }
}

import XCTest

/// `mdv FILE` (#67): the embedded CLI opens files in the running app through Launch Services,
/// focuses a file that is already open, and passes `--theme` as the window's pick.
@MainActor
final class CommandLineUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testOpensFileInRunningAppAndFocusesItAgain() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let smoke = try MdvUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)

        let first = try MdvUITestApp.runCommandLine([smoke])
        XCTAssertEqual(first.status, 0, first.stderr)
        let window = mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForRenderedText("The quick brown fox renders in mdv.", in: window)

        // Another window in front, then mdv on the first file again: it comes forward, still one.
        let other = try MdvUITestApp.temporaryCopy(ofFixture: "links-target.md").path(percentEncoded: false)
        XCTAssertEqual(try MdvUITestApp.runCommandLine([other]).status, 0)
        mdv.waitForWindowCount(2)
        XCTAssertNotEqual(mdv.frontWindow.title, "Smoke Test Fixture")

        let again = try MdvUITestApp.runCommandLine([smoke])
        XCTAssertEqual(again.status, 0, again.stderr)
        waitUntil("the open window came forward") { mdv.frontWindow.title == "Smoke Test Fixture" }
        mdv.waitForWindowCount(2)
    }

    /// `--theme` on a document whose frontmatter names Serif: the window opens in GitHub as its
    /// View > Theme pick (so Document's Theme is offered), and going back to the document's
    /// theme restyles the page; then `--theme serif` on the open file switches it again.
    func testThemeFlagBecomesTheWindowsPick() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let themed = try MdvUITestApp.temporaryCopy(ofFixture: "document-theme.md").path(percentEncoded: false)

        let result = try MdvUITestApp.runCommandLine(["--theme", "github", themed])
        XCTAssertEqual(result.status, 0, result.stderr)
        let window = mdv.waitForWindow(titled: "Document Theme Fixture")
        let paragraph = mdv.waitForRenderedText("This paragraph is set in the theme", in: window)
        let githubWidth = paragraph.frame.width
        XCTAssertTrue(mdv.documentThemeItemIsEnabled(), "the pick hides the document's theme")

        mdv.chooseDocumentTheme()
        waitUntil("the document's Serif restyles the page") { abs(paragraph.frame.width - githubWidth) > 1 }
        XCTAssertFalse(mdv.documentThemeItemIsEnabled(), "no pick any more")

        // Already open: the window switches to the flag's theme.
        XCTAssertEqual(try MdvUITestApp.runCommandLine(["--theme", "github", themed]).status, 0)
        waitUntil("GitHub again") { abs(paragraph.frame.width - githubWidth) < 1 }
        XCTAssertTrue(mdv.documentThemeItemIsEnabled())
        mdv.waitForWindowCount(1)
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                timeout: MdvUITestApp.defaultTimeout),
            .completed, description)
    }

    func testBadPathOpensNothing() throws {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv
        let smoke = try MdvUITestApp.temporaryCopy(ofFixture: "smoke.md").path(percentEncoded: false)
        let missing = FileManager.default.temporaryDirectory.appending(path: "mdv-missing-\(UUID().uuidString).md")

        let result = try MdvUITestApp.runCommandLine([smoke, missing.path(percentEncoded: false)])
        XCTAssertEqual(result.status, 66)
        XCTAssertTrue(result.stderr.contains("No such file or directory"), result.stderr)
        XCTAssertFalse(mdv.window(titled: "Smoke Test Fixture").waitForExistence(timeout: 2))
    }
}

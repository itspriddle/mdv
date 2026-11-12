import XCTest

/// Link handling (#19): in-page links scroll, relative Markdown links open in Peep, and external
/// links never navigate the view. In UI-test mode external opens are shown in the link status
/// overlay instead of launching the browser (`UITestHooks.opensLinksOutsideApp`).
@MainActor
final class LinkNavigationUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func launch() throws -> (PeepUITestApp, XCUIElement) {
        let peep = try PeepUITestApp.launch(openingFixture: "links.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Links Fixture")
        peep.waitForRenderedText("Jump to", in: window)
        return (peep, window)
    }

    func testHeadingLinkScrollsInPlace() throws {
        let (peep, window) = try launch()
        let bottom = peep.renderedText("The bottom paragraph is here.", in: window)
        XCTAssertTrue(bottom.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(bottom.isHittable, "the bottom paragraph starts below the fold")

        peep.link("the bottom section", in: window).click()

        let scrolled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: bottom)
        wait(for: [scrolled], timeout: PeepUITestApp.defaultTimeout)
        XCTAssertTrue(window.exists, "same window, same document")
        XCTAssertEqual(peep.app.windows.count, 1)
    }

    func testRelativeMarkdownLinkOpensDocument() throws {
        let (peep, window) = try launch()
        peep.link("the target document", in: window).click()

        let target = peep.waitForWindow(titled: "Link Target")
        peep.waitForRenderedText("Target section text.", in: target)
        // The original document is still open and unchanged.
        XCTAssertTrue(peep.window(titled: "Links Fixture").exists)
    }

    func testExternalLinkDoesNotNavigateView() throws {
        let (peep, window) = try launch()
        peep.link("the example site", in: window).click()

        let status = peep.linkStatus(in: window)
        XCTAssertTrue(status.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        let shown = status.displayedText
        XCTAssertTrue(shown.contains("https://example.com/peep-ui-test"), "status: \(shown)")
        // Still showing the document.
        XCTAssertTrue(peep.window(titled: "Links Fixture").exists)
        XCTAssertTrue(peep.renderedText("Jump to", in: window).exists)
    }
}

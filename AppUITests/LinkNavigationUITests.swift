import XCTest

/// Link handling (#19): in-page links scroll, relative Markdown links open in mdv, and external
/// links never navigate the view. In UI-test mode external opens are shown in the link status
/// overlay instead of launching the browser (`UITestHooks.opensLinksOutsideApp`).
@MainActor
final class LinkNavigationUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    private func launch() throws -> (MdvUITestApp, XCUIElement) {
        let mdv = try MdvUITestApp.launch(openingFixture: "links.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Links Fixture")
        mdv.waitForRenderedText("Jump to", in: window)
        return (mdv, window)
    }

    func testHeadingLinkScrollsInPlace() throws {
        let (mdv, window) = try launch()
        let bottom = mdv.renderedText("The bottom paragraph is here.", in: window)
        XCTAssertTrue(bottom.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        XCTAssertFalse(bottom.isHittable, "the bottom paragraph starts below the fold")

        mdv.link("the bottom section", in: window).click()

        let scrolled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: bottom)
        wait(for: [scrolled], timeout: MdvUITestApp.defaultTimeout)
        XCTAssertTrue(window.exists, "same window, same document")
        XCTAssertEqual(mdv.app.windows.count, 1)
    }

    func testRelativeMarkdownLinkOpensDocument() throws {
        let (mdv, window) = try launch()
        mdv.link("the target document", in: window).click()

        let target = mdv.waitForWindow(titled: "Link Target")
        mdv.waitForRenderedText("Target section text.", in: target)
        // The original document is still open and unchanged.
        XCTAssertTrue(mdv.window(titled: "Links Fixture").exists)
    }

    func testExternalLinkDoesNotNavigateView() throws {
        let (mdv, window) = try launch()
        mdv.link("the example site", in: window).click()

        let status = mdv.linkStatus(in: window)
        XCTAssertTrue(status.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        let shown = status.displayedText
        XCTAssertTrue(shown.contains("https://example.com/mdv-ui-test"), "status: \(shown)")
        // Still showing the document.
        XCTAssertTrue(mdv.window(titled: "Links Fixture").exists)
        XCTAssertTrue(mdv.renderedText("Jump to", in: window).exists)
    }
}

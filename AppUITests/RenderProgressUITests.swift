import XCTest

/// Feedback for slow renders (#58): a custom preprocessor (`slow.sh`, 4 s) holds up the first
/// render, so the window shows its progress indicator over the blank page, and the indicator
/// goes once the page is shown.
@MainActor
final class RenderProgressUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testSlowFirstRenderShowsIndicatorUntilThePageIsShown() throws {
        let mdv = try MdvUITestApp.launch(
            openingFixture: "preprocessor.md", arguments: try MdvUITestApp.preprocessorArguments(fixture: "slow.sh"))
        self.mdv = mdv
        // The file name is the title until the render names the window.
        mdv.waitForWindow(titled: "preprocessor.md")
        // In the front window (resolved per query: the title changes when the render lands),
        // never app-wide, where CI's Touch Bar can mirror controls.
        let indicator = mdv.frontWindow.descendants(matching: .any)["render-progress"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the progress indicator")

        let rendered = mdv.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        mdv.waitForRenderedText("Processed by the script.", in: rendered)
        XCTAssertTrue(indicator.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "gone once shown")
        XCTAssertFalse(rendered.descendants(matching: .any)["render-progress-update"].firstMatch.exists)
    }
}

import XCTest

/// Feedback for slow renders (#58): a Debug-only launch hook (`-PeepUITestRenderDelay`) holds up
/// the first render, so the window shows its progress indicator over the blank page, and the
/// indicator goes once the page is shown. The delay is long enough that a slow CI launch still
/// finds the indicator, and doesn't depend on a script or the machine's speed.
@MainActor
final class RenderProgressUITests: XCTestCase {
    /// How long the first render waits: well past the 300 ms indicator delay plus a slow launch.
    private static let renderDelay: TimeInterval = 8

    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testSlowFirstRenderShowsIndicatorUntilThePageIsShown() throws {
        let peep = try PeepUITestApp.launch(
            openingFixture: "smoke.md", arguments: ["-PeepUITestRenderDelay", "\(Self.renderDelay)"])
        self.peep = peep
        // The file name is the title until the render names the window.
        peep.waitForWindow(titled: "smoke.md")
        // In the front window (resolved per query: the title changes when the render lands),
        // never app-wide, where CI's Touch Bar can mirror controls.
        let indicator = peep.frontWindow.descendants(matching: .any)["render-progress"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the progress indicator")

        let timeout = Self.renderDelay + PeepUITestApp.defaultTimeout
        let rendered = peep.waitForWindow(titled: "Smoke Test Fixture", timeout: timeout)
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: rendered)
        XCTAssertTrue(indicator.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout), "gone once shown")
        XCTAssertFalse(rendered.descendants(matching: .any)["render-progress-update"].firstMatch.exists)
    }
}

import XCTest

/// Feedback for slow renders (#58): a Debug-only launch hook (`-MdvUITestRenderDelay`) holds up
/// the first render, so the window shows its progress indicator over the blank page, and the
/// indicator goes once the page is shown. The delay is long enough that a slow CI launch still
/// finds the indicator, and doesn't depend on a script or the machine's speed.
@MainActor
final class RenderProgressUITests: XCTestCase {
    /// How long the first render waits: well past the 300 ms indicator delay plus a slow launch.
    private static let renderDelay: TimeInterval = 8

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
            openingFixture: "smoke.md", arguments: ["-MdvUITestRenderDelay", "\(Self.renderDelay)"])
        self.mdv = mdv
        // The file name is the title until the render names the window.
        mdv.waitForWindow(titled: "smoke.md")
        // In the front window (resolved per query: the title changes when the render lands),
        // never app-wide, where CI's Touch Bar can mirror controls.
        let indicator = mdv.frontWindow.descendants(matching: .any)["render-progress"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the progress indicator")

        let timeout = Self.renderDelay + MdvUITestApp.defaultTimeout
        let rendered = mdv.waitForWindow(titled: "Smoke Test Fixture", timeout: timeout)
        mdv.waitForRenderedText("The quick brown fox renders in mdv.", in: rendered)
        XCTAssertTrue(indicator.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "gone once shown")
        XCTAssertFalse(rendered.descendants(matching: .any)["render-progress-update"].firstMatch.exists)
    }
}

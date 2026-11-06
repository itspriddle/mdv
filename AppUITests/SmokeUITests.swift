import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testOpensFixtureWithTitleAndRenderedText() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "smoke.md")
        self.mdv = mdv

        // The window title is the document's first h1.
        let window = mdv.waitForWindow(titled: "Smoke Test Fixture")
        mdv.waitForWebView(in: window)
        // A reference for how this macOS version exposes a rendered page (the tree differs
        // between versions); kept in the result bundle.
        mdv.attachAccessibilityTree(named: "Rendered document accessibility tree")
        mdv.waitForRenderedText("The quick brown fox renders in mdv.", in: window)
        mdv.waitForRenderedText("Second list item", in: window)
    }

    func testLaunchWithoutDocumentShowsNoOpenPanel() {
        let mdv = MdvUITestApp.launch()
        self.mdv = mdv

        XCTAssertTrue(mdv.app.wait(for: .runningForeground, timeout: MdvUITestApp.defaultTimeout))
        // In UI-test mode the launch Open panel (a modal window) is skipped.
        XCTAssertEqual(mdv.app.windows.count, 0, "windows: \(mdv.app.windows.allElementsBoundByIndex.map(\.title))")
    }
}

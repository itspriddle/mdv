import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testOpensFixtureWithTitleAndRenderedText() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "smoke.md")
        self.peep = peep

        // The window title is the document's first h1.
        let window = peep.waitForWindow(titled: "Smoke Test Fixture")
        peep.waitForWebView(in: window)
        peep.waitForRenderedText("The quick brown fox renders in Peep.", in: window)
        // A reference for how this macOS version exposes a rendered page (the tree differs
        // between versions); kept in the result bundle.
        peep.attachAccessibilityTree(named: "Rendered document accessibility tree")
        peep.waitForRenderedText("Second list item", in: window)
    }

    func testLaunchWithoutDocumentShowsNoOpenPanel() {
        let peep = PeepUITestApp.launch()
        self.peep = peep

        XCTAssertTrue(peep.app.wait(for: .runningForeground, timeout: PeepUITestApp.defaultTimeout))
        // In UI-test mode the launch Open panel (a modal window) is skipped.
        XCTAssertEqual(peep.app.windows.count, 0, "windows: \(peep.app.windows.allElementsBoundByIndex.map(\.title))")
    }
}

import XCTest

/// GitHub alerts (#52): a GFM document's `> [!NOTE]` renders as an alert with its title, and
/// alert titles stay out of the outline (headings inside an alert's body are listed).
@MainActor
final class AlertsUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testAlertsRenderWithTitlesThatStayOutOfTheOutline() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "alerts.md", arguments: ["-OutlineVisible", "YES"])
        self.peep = peep
        let window = peep.waitForWindow(titled: "Alerts Fixture")
        peep.waitForRenderedText("The note body.", in: window)
        XCTAssertTrue(peep.renderedText("Careful with this.", in: window).exists)
        XCTAssertFalse(peep.renderedText("[!NOTE]", in: window).exists, "the marker is gone")
        XCTAssertTrue(peep.renderedText("Warning", in: window).exists, "the title is rendered")

        let inside = peep.outlineText("Inside the warning", in: window)
        XCTAssertTrue(inside.waitForExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertFalse(peep.outlineText("Note", in: window).exists)
        XCTAssertFalse(peep.outlineText("Warning", in: window).exists)
    }
}

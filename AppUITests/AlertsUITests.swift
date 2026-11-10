import XCTest

/// GitHub alerts (#52): a GFM document's `> [!NOTE]` renders as an alert with its title, and
/// alert titles stay out of the outline (headings inside an alert's body are listed).
@MainActor
final class AlertsUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testAlertsRenderWithTitlesThatStayOutOfTheOutline() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "alerts.md", arguments: ["-OutlineVisible", "YES"])
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Alerts Fixture")
        mdv.waitForRenderedText("The note body.", in: window)
        XCTAssertTrue(mdv.renderedText("Careful with this.", in: window).exists)
        XCTAssertFalse(mdv.renderedText("[!NOTE]", in: window).exists, "the marker is gone")
        XCTAssertTrue(mdv.renderedText("Warning", in: window).exists, "the title is rendered")

        let inside = mdv.outlineText("Inside the warning", in: window)
        XCTAssertTrue(inside.waitForExistence(timeout: MdvUITestApp.defaultTimeout))
        XCTAssertFalse(mdv.outlineText("Note", in: window).exists)
        XCTAssertFalse(mdv.outlineText("Warning", in: window).exists)
    }
}

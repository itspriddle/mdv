import XCTest

/// Remote images are blocked behind a bar until the user chooses Load, for that window only.
@MainActor
final class RemoteImagesUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testBarLoadsHTTPSImagesOnly() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "remote-images/remote.md")
        self.mdv = mdv

        let window = mdv.waitForWindow(titled: "Remote Images Fixture")
        mdv.waitForRenderedText("Remote images end here.", in: window)

        let load = window.buttons["load-remote-images"]
        XCTAssertTrue(load.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "the remote images bar")
        XCTAssertTrue(window.staticTexts["Remote images blocked"].exists)
        // Both images are labeled placeholders, not <img>s.
        XCTAssertTrue(mdv.renderedText("Blocked remote image: Remote badge", in: window).exists)
        XCTAssertTrue(mdv.renderedText("Blocked remote image: Cleartext image", in: window).exists)

        load.click()

        // The bar goes away; the https image is now an image, the http one stays a placeholder.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: load)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: MdvUITestApp.defaultTimeout), .completed)
        let badgePlaceholder = mdv.renderedText("Blocked remote image: Remote badge", in: window)
        let replaced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: badgePlaceholder)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: MdvUITestApp.defaultTimeout), .completed)
        XCTAssertTrue(mdv.renderedText("Blocked remote image: Cleartext image", in: window).exists)
        mdv.waitForRenderedText("Remote images end here.", in: window)
    }
}

import XCTest

/// Remote images are blocked behind a bar until the user chooses Load, for that window only.
@MainActor
final class RemoteImagesUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testBarLoadsHTTPSImagesOnly() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "remote-images/remote.md")
        self.peep = peep

        let window = peep.waitForWindow(titled: "Remote Images Fixture")
        peep.waitForRenderedText("Remote images end here.", in: window)

        let load = window.buttons["load-remote-images"]
        XCTAssertTrue(load.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the remote images bar")
        XCTAssertTrue(window.staticTexts["Remote images blocked"].exists)
        // Both images are labeled placeholders, not <img>s.
        XCTAssertTrue(peep.renderedText("Blocked remote image: Remote badge", in: window).exists)
        XCTAssertTrue(peep.renderedText("Blocked remote image: Cleartext image", in: window).exists)

        load.click()

        // The bar goes away; the https image is now an image, the http one stays a placeholder.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: load)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: PeepUITestApp.defaultTimeout), .completed)
        let badgePlaceholder = peep.renderedText("Blocked remote image: Remote badge", in: window)
        let replaced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: badgePlaceholder)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: PeepUITestApp.defaultTimeout), .completed)
        XCTAssertTrue(peep.renderedText("Blocked remote image: Cleartext image", in: window).exists)
        peep.waitForRenderedText("Remote images end here.", in: window)
    }
}

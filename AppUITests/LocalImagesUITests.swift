import XCTest

/// Relative images in a document load through the app's scoped `peep-doc` scheme handler.
@MainActor
final class LocalImagesUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testRelativePNGAndSVGRender() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "images/images.md")
        self.peep = peep

        let window = peep.waitForWindow(titled: "Relative Images Fixture")
        peep.waitForRenderedText("Images rendered.", in: window)
        // A loaded image lays out at its intrinsic size; a broken one shows its alt text instead.
        assertImage("Relative PNG", in: window, size: CGSize(width: 64, height: 48))
        assertImage("Relative SVG", in: window, size: CGSize(width: 80, height: 30))
    }

    private func assertImage(
        _ alt: String, in window: XCUIElement, size: CGSize, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let peep else {
            return XCTFail("no app", file: file, line: line)
        }
        let image = peep.webView(in: window).images[alt].firstMatch
        XCTAssertTrue(
            image.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "image \"\(alt)\"", file: file, line: line)
        let predicate = NSPredicate { object, _ in
            guard let frame = (object as? XCUIElement)?.frame else {
                return false
            }
            // Accessibility frames are whole points, rounded outward from the image's
            // fractional position in the line box, so allow a point either way.
            return abs(frame.width - size.width) <= 1 && abs(frame.height - size.height) <= 1
        }
        let loaded = XCTNSPredicateExpectation(predicate: predicate, object: image)
        XCTAssertEqual(
            XCTWaiter().wait(for: [loaded], timeout: PeepUITestApp.defaultTimeout), .completed,
            "image \"\(alt)\" frame \(image.frame.size), expected \(size)", file: file, line: line)
    }
}

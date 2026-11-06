import XCTest

/// Relative images in a document load through the app's scoped `mdv-doc` scheme handler.
@MainActor
final class LocalImagesUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testRelativePNGAndSVGRender() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "images/images.md")
        self.mdv = mdv

        let window = mdv.waitForWindow(titled: "Relative Images Fixture")
        mdv.waitForRenderedText("Images rendered.", in: window)
        // A loaded image lays out at its intrinsic size; a broken one shows its alt text instead.
        assertImage("Relative PNG", in: window, size: CGSize(width: 64, height: 48))
        assertImage("Relative SVG", in: window, size: CGSize(width: 80, height: 30))
    }

    private func assertImage(
        _ alt: String, in window: XCUIElement, size: CGSize, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let mdv else {
            return XCTFail("no app", file: file, line: line)
        }
        let image = mdv.webView(in: window).images[alt].firstMatch
        XCTAssertTrue(
            image.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "image \"\(alt)\"", file: file, line: line)
        let predicate = NSPredicate { object, _ in
            guard let frame = (object as? XCUIElement)?.frame else {
                return false
            }
            return abs(frame.width - size.width) < 1 && abs(frame.height - size.height) < 1
        }
        let loaded = XCTNSPredicateExpectation(predicate: predicate, object: image)
        XCTAssertEqual(
            XCTWaiter().wait(for: [loaded], timeout: MdvUITestApp.defaultTimeout), .completed,
            "image \"\(alt)\" frame \(image.frame.size), expected \(size)", file: file, line: line)
    }
}

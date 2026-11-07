import XCTest

/// The bundled themes (#33) and the theme picker (#34). The showcase test opens the fixture (`themes/showcase.md`, every construct a theme styles) that
/// manual checks and the visual regression check (#39) use.
@MainActor
final class ThemesUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    func testShowcaseFixtureRendersInDefaultTheme() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "themes/showcase.md")
        self.mdv = mdv

        let window = mdv.waitForWindow(titled: "Theme Showcase")
        mdv.waitForWebView(in: window)
        mdv.waitForRenderedText("Third-level heading", in: window)
        mdv.waitForRenderedText("Text after a thematic break. Theme showcase ends here.", in: window)
    }

    /// View > Theme switches the window's theme in place: the text reflows in the new theme's
    /// font, and the paragraph at the top of the view stays there (no reload to the top).
    func testThemeSwitchRestylesInPlaceAndKeepsPosition() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "live-reload.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Live Reload Fixture")
        let webView = mdv.webView(in: window)
        mdv.waitForRenderedText("Paragraph 1.", in: window)

        for _ in 0..<4 {
            webView.typeKey(.pageDown, modifierFlags: [])
        }
        let anchor = try XCTUnwrap(mdv.firstVisibleText(startingWith: "Paragraph ", in: window))
        let label = anchor.displayedText
        XCTAssertNotEqual(label, "Paragraph 1.", "the view scrolled")
        let before = anchor.frame

        mdv.chooseTheme("Serif")

        // The computed style changed: the same text run has another size in the serif font.
        let paragraph = mdv.renderedText(label, in: window)
        let restyled = NSPredicate { _, _ in abs(paragraph.frame.width - before.width) > 1 }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: restyled, object: nil)],
                timeout: MdvUITestApp.defaultTimeout),
            .completed, "\(label) kept its width \(before.width)")
        // Same paragraph at the top of the view: the stylesheet was swapped, not the page reloaded.
        XCTAssertTrue(paragraph.exists)
        XCTAssertEqual(paragraph.frame.minY, before.minY, accuracy: 8, "\(label) moved")
    }
}

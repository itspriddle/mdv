import XCTest

/// The bundled themes (#33). Until the picker (#34) the window uses the default theme (GitHub);
/// this opens the showcase fixture (`themes/showcase.md`, every construct a theme styles) that
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
}

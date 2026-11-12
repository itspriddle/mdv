import XCTest

/// Extensionless text files (#41): `README` and `CHANGELOG` open from the Open panel.
///
/// Drops on a window can't be driven from XCUITest (no drag source outside the app); the hosted
/// `ExtensionlessOpeningTests` cover the drop filter, and dropping a `README` from Finder is a
/// manual check.
@MainActor
final class ExtensionlessFilesUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    /// `README` (which recent macOS types as plain text by name) and `CHANGELOG` (which it
    /// types as `public.data`) both open from File > Open.
    func testExtensionlessFilesOpenFromOpenPanel() throws {
        let folder = try Fixtures.url(named: "extensionless")
        let peep = try PeepUITestApp.launch(openingFixture: "smoke.md")
        self.peep = peep
        peep.waitForWindow(titled: "Smoke Test Fixture")

        for (name, title, text) in [
            ("README", "Extensionless Readme Fixture", "A README with no file extension opens in Peep."),
            ("CHANGELOG", "Extensionless Changelog Fixture", "A CHANGELOG with no file extension opens in Peep."),
        ] {
            peep.app.typeKey("o", modifierFlags: .command)
            let panel = peep.openPanel
            XCTAssertTrue(panel.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "Open panel")
            peep.chooseInOpenPanel(folder.appending(path: name))
            XCTAssertTrue(panel.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout), "Open panel dismissed")
            let window = peep.window(titled: title)
            peep.waitForWindow(titled: title)
            peep.waitForRenderedText(text, in: window)
        }
    }
}

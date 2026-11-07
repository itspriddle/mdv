import XCTest

/// Extensionless text files (#41): `README` and `CHANGELOG` open from the Open panel.
///
/// Drops on a window can't be driven from XCUITest (no drag source outside the app); the hosted
/// `ExtensionlessOpeningTests` cover the drop filter, and dropping a `README` from Finder is a
/// manual check.
@MainActor
final class ExtensionlessFilesUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    /// `README` (which recent macOS types as plain text by name) and `CHANGELOG` (which it
    /// types as `public.data`) both open from File > Open.
    func testExtensionlessFilesOpenFromOpenPanel() throws {
        let folder = try Fixtures.url(named: "extensionless")
        let mdv = try MdvUITestApp.launch(openingFixture: "smoke.md")
        self.mdv = mdv
        mdv.waitForWindow(titled: "Smoke Test Fixture")

        for (name, title, text) in [
            ("README", "Extensionless Readme Fixture", "A README with no file extension opens in mdv."),
            ("CHANGELOG", "Extensionless Changelog Fixture", "A CHANGELOG with no file extension opens in mdv."),
        ] {
            mdv.app.typeKey("o", modifierFlags: .command)
            let panel = mdv.openPanel
            XCTAssertTrue(panel.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "Open panel")
            mdv.chooseInOpenPanel(folder.appending(path: name))
            XCTAssertTrue(panel.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "Open panel dismissed")
            let window = mdv.window(titled: title)
            mdv.waitForWindow(titled: title)
            mdv.waitForRenderedText(text, in: window)
        }
    }
}

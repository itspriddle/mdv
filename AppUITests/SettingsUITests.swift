import XCTest

/// The Settings window (#36): Command-comma opens it, and the default theme applies to windows
/// opened after the change, not to the ones already open.
@MainActor
final class SettingsUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    /// The same one-line text in both fixtures: in Serif (19px) its line is taller than in
    /// GitHub (16px), so its height tells the themes apart. (Widths can coincide: serif glyphs
    /// are narrower.)
    private static let line = "A short line in the theme."

    func testDefaultThemeAppliesToNewWindows() throws {
        let mdv = try MdvUITestApp.launch(openingFixture: "settings/first.md")
        self.mdv = mdv
        let first = mdv.waitForWindow(titled: "Settings First")
        let github = mdv.waitForRenderedText(Self.line, in: first).frame
        XCTAssertGreaterThan(github.height, 0)

        let settings = mdv.openSettings()
        XCTAssertEqual(settings.title, "General")
        XCTAssertTrue(settings.popUpButtons["settings-zoom"].exists)
        XCTAssertTrue(settings.popUpButtons["settings-content-width"].exists)
        XCTAssertTrue(settings.checkBoxes["settings-outline"].exists)
        mdv.chooseSetting("Serif", in: "settings-default-theme")
        XCTAssertEqual(settings.popUpButtons["settings-default-theme"].value as? String, "Serif")

        // The setting is the default for new windows; the open window keeps its theme.
        XCTAssertEqual(mdv.renderedText(Self.line, in: first).frame.height, github.height, accuracy: 0.5)

        // Command-comma again brings back the same window, not a second one.
        settings.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settings.waitForNonExistence(timeout: MdvUITestApp.defaultTimeout), "Settings closed")
        mdv.openSettings()
        XCTAssertEqual(mdv.app.windows.matching(identifier: "settings-window").count, 1)
        XCTAssertEqual(mdv.settingsWindow.popUpButtons["settings-default-theme"].value as? String, "Serif")
        mdv.settingsWindow.typeKey("w", modifierFlags: .command)

        // File > Open. (`XCUIApplication.open(_:)` can hand the file to a new instance, which
        // isn't in UI-test mode.)
        mdv.app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(mdv.openPanel.waitForExistence(timeout: MdvUITestApp.defaultTimeout), "Open panel")
        mdv.chooseInOpenPanel(try Fixtures.url(named: "settings/second.md"))
        let second = mdv.waitForWindow(titled: "Settings Second")
        let serif = mdv.waitForRenderedText(Self.line, in: second).frame
        XCTAssertGreaterThan(serif.height, github.height + 1, "the new window uses Serif")
    }
}

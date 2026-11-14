import XCTest

/// The Settings window (#36): Command-comma opens it, and the default theme applies to windows
/// opened after the change, not to the ones already open.
@MainActor
final class SettingsUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    /// The same one-line text in both fixtures: in Serif (19px) its line is taller than in
    /// GitHub (16px), so its height tells the themes apart. (Widths can coincide: serif glyphs
    /// are narrower.)
    private static let line = "A short line in the theme."

    func testDefaultThemeAppliesToNewWindows() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "settings/first.md")
        self.peep = peep
        let first = peep.waitForWindow(titled: "Settings First")
        let github = peep.waitForRenderedText(Self.line, in: first).frame
        XCTAssertGreaterThan(github.height, 0)

        let settings = peep.openSettings()
        XCTAssertEqual(settings.title, "General")
        XCTAssertTrue(settings.popUpButtons["settings-appearance"].exists)
        XCTAssertTrue(settings.popUpButtons["settings-zoom"].exists)
        XCTAssertTrue(settings.popUpButtons["settings-content-width"].exists)
        XCTAssertTrue(settings.checkBoxes["settings-outline"].exists)
        XCTAssertTrue(settings.checkBoxes["settings-pin-new-windows"].exists)
        peep.chooseSetting("Serif", in: "settings-default-theme")
        XCTAssertEqual(settings.popUpButtons["settings-default-theme"].value as? String, "Serif")

        // The setting is the default for new windows; the open window keeps its theme.
        XCTAssertEqual(peep.renderedText(Self.line, in: first).frame.height, github.height, accuracy: 0.5)

        // Command-comma again brings back the same window, not a second one.
        settings.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settings.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout), "Settings closed")
        peep.openSettings()
        XCTAssertEqual(peep.app.windows.matching(identifier: "settings-window").count, 1)
        XCTAssertEqual(peep.settingsWindow.popUpButtons["settings-default-theme"].value as? String, "Serif")
        peep.settingsWindow.typeKey("w", modifierFlags: .command)

        // File > Open. (`XCUIApplication.open(_:)` can hand the file to a new instance, which
        // isn't in UI-test mode.)
        peep.app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(peep.openPanel.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "Open panel")
        peep.chooseInOpenPanel(try Fixtures.url(named: "settings/second.md"))
        let second = peep.waitForWindow(titled: "Settings Second")
        let serif = peep.waitForRenderedText(Self.line, in: second).frame
        XCTAssertGreaterThan(serif.height, github.height + 1, "the new window uses Serif")
    }

    /// Settings > Markdown (#55): the default flavor applies to open documents at once. In
    /// CommonMark the table is plain text.
    func testDefaultFlavorReRendersOpenDocuments() throws {
        let peep = try PeepUITestApp.launch(openingFixture: "settings/flavor.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Settings Flavor")
        peep.waitForRenderedText("After the table.", in: window)
        let webView = peep.webView(in: window)
        XCTAssertTrue(webView.tables.firstMatch.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "GFM table")

        peep.openSettings()
        peep.showSettingsPane("Markdown")
        XCTAssertTrue(peep.settingsWindow.popUpButtons["settings-frontmatter"].exists)
        XCTAssertEqual(
            peep.settingsWindow.popUpButtons["settings-default-flavor"].value as? String, "GitHub Flavored Markdown")
        peep.chooseSetting("CommonMark", in: "settings-default-flavor")

        // The open window re-renders: the table's rows are now a paragraph of pipes.
        peep.waitForRenderedText("| Alpha | Beta |", in: window)
        XCTAssertTrue(webView.tables.firstMatch.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout), "no table")

        peep.chooseSetting("GitHub Flavored Markdown", in: "settings-default-flavor")
        XCTAssertTrue(webView.tables.firstMatch.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "table back")
    }
}

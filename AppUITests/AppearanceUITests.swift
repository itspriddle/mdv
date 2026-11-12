import XCTest

/// The app-wide appearance: Settings > Appearance and View > Appearance override the system
/// live, and stay in step with each other. (GitHub's page background is #0d1117 / #ffffff.)
@MainActor
final class AppearanceUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private static let line = "A short line in the theme."

    private func launch() throws -> (PeepUITestApp, XCUIElement) {
        let peep = try PeepUITestApp.launch(openingFixture: "settings/first.md")
        self.peep = peep
        let window = peep.waitForWindow(titled: "Settings First")
        peep.waitForRenderedText(Self.line, in: window)
        return (peep, peep.webViewContainer(in: window))
    }

    func testSettingsAppearanceOverridesTheSystemLive() throws {
        let (peep, page) = try launch()
        peep.openSettings()
        for (mode, isDark) in [("Dark", true), ("Light", false), ("Dark", true)] {
            peep.chooseSetting(mode, in: "settings-appearance")
            XCTAssertEqual(peep.settingsWindow.popUpButtons["settings-appearance"].value as? String, mode)
            peep.waitForPage(page, isDark: isDark)
        }
    }

    func testViewMenuAppearanceOverridesTheSystemAndUpdatesSettings() throws {
        let (peep, page) = try launch()
        for (mode, isDark) in [("Dark", true), ("Light", false)] {
            peep.chooseAppearanceInMenu(mode)
            peep.waitForPage(page, isDark: isDark)
        }
        peep.chooseAppearanceInMenu("Dark")
        peep.waitForPage(page, isDark: true)

        // Settings shows the menu's choice (the menu's checkmark is covered by AppearanceTests).
        peep.openSettings()
        XCTAssertEqual(peep.settingsWindow.popUpButtons["settings-appearance"].value as? String, "Dark")
    }
}

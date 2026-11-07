import XCTest

/// The app-wide appearance: Settings > Appearance and View > Appearance override the system
/// live, and stay in step with each other. (GitHub's page background is #0d1117 / #ffffff.)
@MainActor
final class AppearanceUITests: XCTestCase {
    private var mdv: MdvUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        mdv?.terminate()
        mdv = nil
    }

    private static let line = "A short line in the theme."

    private func launch() throws -> (MdvUITestApp, XCUIElement) {
        let mdv = try MdvUITestApp.launch(openingFixture: "settings/first.md")
        self.mdv = mdv
        let window = mdv.waitForWindow(titled: "Settings First")
        mdv.waitForRenderedText(Self.line, in: window)
        return (mdv, mdv.webViewContainer(in: window))
    }

    func testSettingsAppearanceOverridesTheSystemLive() throws {
        let (mdv, page) = try launch()
        mdv.openSettings()
        for (mode, isDark) in [("Dark", true), ("Light", false), ("Dark", true)] {
            mdv.chooseSetting(mode, in: "settings-appearance")
            XCTAssertEqual(mdv.settingsWindow.popUpButtons["settings-appearance"].value as? String, mode)
            mdv.waitForPage(page, isDark: isDark)
        }
    }

    func testViewMenuAppearanceOverridesTheSystemAndUpdatesSettings() throws {
        let (mdv, page) = try launch()
        for (mode, isDark) in [("Dark", true), ("Light", false)] {
            mdv.chooseAppearanceInMenu(mode)
            mdv.waitForPage(page, isDark: isDark)
        }
        mdv.chooseAppearanceInMenu("Dark")
        mdv.waitForPage(page, isDark: true)

        // Settings shows the menu's choice (the menu's checkmark is covered by AppearanceTests).
        mdv.openSettings()
        XCTAssertEqual(mdv.settingsWindow.popUpButtons["settings-appearance"].value as? String, "Dark")
    }
}

import XCTest

/// Sparkle updates (#81) without the network: a UI-test launch never gets an updater, even when
/// asked for one with `-PeepUpdateFeedURL` (port 9, discard, so a request would go nowhere), so
/// App menu > Check for Updates… is there but disabled, and Settings > General's update rows
/// toggle the in-memory stand-in.
@MainActor
final class UpdatesUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    func testCheckForUpdatesIsOffAndSettingsRowsToggle() throws {
        let peep = try PeepUITestApp.launch(
            openingFixture: "settings/first.md", arguments: ["-PeepUpdateFeedURL", "http://127.0.0.1:9/appcast.xml"])
        self.peep = peep
        peep.waitForWindow(titled: "Settings First")

        let appMenu = peep.app.menuBars.menuBarItems.element(boundBy: 1)
        appMenu.click()
        let check = appMenu.menuItems["Check for Updates…"]
        XCTAssertTrue(check.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "Check for Updates…")
        XCTAssertFalse(check.isEnabled, "UI-test launches never check")
        peep.app.typeKey(.escape, modifierFlags: [])

        let settings = peep.openSettings()
        let checks = settings.checkBoxes["settings-update-checks"]
        let downloads = settings.checkBoxes["settings-update-downloads"]
        XCTAssertTrue(checks.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "automatic checks row")
        XCTAssertTrue(downloads.exists, "automatic downloads row")
        XCTAssertTrue(settings.staticTexts["This build doesn’t check for updates."].exists)
        XCTAssertEqual(checks.value as? Int, 0)
        XCTAssertFalse(downloads.isEnabled, "downloads need automatic checks")

        checks.click()
        XCTAssertEqual(checks.value as? Int, 1)
        XCTAssertTrue(downloads.isEnabled)
        downloads.click()
        XCTAssertEqual(downloads.value as? Int, 1)

        checks.click()
        XCTAssertEqual(checks.value as? Int, 0)
        XCTAssertFalse(downloads.isEnabled)
    }
}

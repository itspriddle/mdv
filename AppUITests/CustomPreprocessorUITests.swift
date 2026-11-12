import XCTest

/// The custom preprocessor (#57), configured with the Debug-only `-PeepUITestPreprocessor` hook
/// so tests never depend on the reader's settings: its output renders, a failing script shows
/// the bar (with stderr behind Show Details) instead of an alert, and turning it back on in
/// Settings > Markdown needs the warning.
@MainActor
final class CustomPreprocessorUITests: XCTestCase {
    private var peep: PeepUITestApp?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        peep?.terminate()
        peep = nil
    }

    private func launch(script name: String) throws -> PeepUITestApp {
        let peep = try PeepUITestApp.launch(
            openingFixture: "preprocessor.md", arguments: try PeepUITestApp.preprocessorArguments(fixture: name))
        self.peep = peep
        return peep
    }

    func testPreprocessorOutputRenders() throws {
        let peep = try launch(script: "upcase.sh")
        let window = peep.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        peep.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)
        XCTAssertFalse(peep.preprocessorFailureBar(in: window).exists)
    }

    func testFailingScriptShowsBar() throws {
        let peep = try launch(script: "fail.sh")
        // The document renders without the preprocessor.
        let window = peep.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        peep.waitForRenderedText("Processed by the script.", in: window)

        let bar = peep.preprocessorFailureBar(in: window)
        XCTAssertTrue(bar.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "failure bar")
        let message = bar.descendants(matching: .any)["preprocessor-failure-message"].firstMatch
        XCTAssertTrue(message.displayedText.contains("exited with status 3"), message.displayedText)
        XCTAssertEqual(peep.app.dialogs.count, 0, "no alert")
        XCTAssertEqual(window.sheets.count, 0, "no sheet")

        let details = bar.descendants(matching: .any)["preprocessor-failure-details"].firstMatch
        XCTAssertFalse(details.exists)
        bar.buttons["preprocessor-failure-details-button"].click()
        XCTAssertTrue(details.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "stderr details")
        XCTAssertTrue(details.displayedText.contains("line 3: boom"), details.displayedText)
    }

    func testTurningOnAgainNeedsTheWarning() throws {
        let peep = try launch(script: "upcase.sh")
        let window = peep.waitForWindow(titled: "PREPROCESSOR FIXTURE")
        peep.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)

        let settings = peep.openSettings()
        peep.showSettingsPane("Markdown")
        let toggle = settings.checkBoxes["settings-custom-preprocessor"]
        XCTAssertTrue(toggle.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "toggle")
        XCTAssertEqual(toggle.value as? Int, 1)
        let path = settings.descendants(matching: .any)["settings-custom-preprocessor-path"].firstMatch
        XCTAssertTrue(path.displayedText.hasSuffix("/upcase.sh"), path.displayedText)

        // Off: open windows render without it, in place.
        toggle.click()
        peep.waitForRenderedText("Processed by the script.", in: window)

        // On: the warning first; Cancel keeps it off.
        toggle.click()
        // Scoped to the Settings window: on CI the Touch Bar mirrors the alert's buttons, and
        // an app-wide query can match the Touch Bar copy, which can't be clicked.
        let turnOn = settings.buttons["settings-custom-preprocessor-confirm"].firstMatch
        XCTAssertTrue(turnOn.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the warning")
        settings.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(turnOn.waitForNonExistence(timeout: PeepUITestApp.defaultTimeout))
        XCTAssertEqual(toggle.value as? Int, 0)

        toggle.click()
        XCTAssertTrue(turnOn.waitForExistence(timeout: PeepUITestApp.defaultTimeout), "the warning")
        turnOn.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        peep.waitForRenderedText("PROCESSED BY THE SCRIPT.", in: window)
    }
}
